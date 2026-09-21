import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'server_sessions.dart';

const int _diagnosticBytes = 256;
const int _maximumManagerOutputBytes = 64 * 1024;

final class NativeServerException implements Exception {
  const NativeServerException(this.code);

  final String code;

  @override
  String toString() => 'NativeServerException($code)';
}

final class NativeServerMutation {
  const NativeServerMutation({
    required this.sessionId,
    required this.rosterRevision,
  });

  final int sessionId;
  final int rosterRevision;
}

final class NativeServerManager {
  NativeServerManager._(this.endpoint, this.roster, this.control);

  final String endpoint;
  final NativeServerRosterObserver roster;
  final NativeServerControl control;

  static Future<NativeServerManager> create({required String endpoint}) async {
    NativeServerRosterObserver? roster;
    NativeServerControl? control;
    try {
      roster = await NativeServerRosterObserver.create(endpoint: endpoint);
      control = await NativeServerControl.create(endpoint: endpoint);
      return NativeServerManager._(endpoint, roster, control);
    } catch (_) {
      await control?.close();
      await roster?.close();
      rethrow;
    }
  }

  Future<void> close() async {
    Object? firstFailure;
    StackTrace? firstStack;
    try {
      await roster.close();
    } catch (error, stackTrace) {
      firstFailure = error;
      firstStack = stackTrace;
    }
    try {
      await control.close();
    } catch (error, stackTrace) {
      firstFailure ??= error;
      firstStack ??= stackTrace;
    }
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStack!);
    }
  }
}

final class NativeServerRosterObserver {
  NativeServerRosterObserver._(
    this._commands,
    this._responses,
    this._isolate,
    this._cancellation,
    this._cancelCancellation,
    this._destroyCancellation,
  ) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  final ffi.Pointer<ffi.Void> _cancellation;
  final _CancellationCancelDart _cancelCancellation;
  final _CancellationDestroyDart _destroyCancellation;
  final Map<int, Completer<HowlServerRoster>> _pending =
      <int, Completer<HowlServerRoster>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeServerRosterObserver> create({
    required String endpoint,
  }) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final library = _serverLibrary();
    final cancelCancellation = library
        .lookupFunction<_CancellationCancelNative, _CancellationCancelDart>(
          'howl_native_host_cancellation_cancel',
        );
    final destroyCancellation = library
        .lookupFunction<_CancellationDestroyNative, _CancellationDestroyDart>(
          'howl_native_host_cancellation_destroy',
        );
    final isolate = await Isolate.spawn<List<Object?>>(
      _serverRosterWorker,
      <Object?>[ready.sendPort, responses.sendPort, endpoint],
      debugName: 'Howl server roster',
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    final first = await _awaitServerWorkerStartup(
      ready: ready,
      errors: errors,
      exits: exits,
      errorCode: 'roster_worker_isolate_error',
      exitCode: 'roster_worker_isolate_exit',
    );
    if (first is! List<Object?> ||
        first.length != 2 ||
        first[0] is! SendPort ||
        first[1] is! int ||
        (first[1]! as int) == 0) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeServerException(
        first is String ? first : 'roster_worker_start',
      );
    }
    return NativeServerRosterObserver._(
      first[0]! as SendPort,
      responses,
      isolate,
      ffi.Pointer<ffi.Void>.fromAddress(first[1]! as int),
      cancelCancellation,
      destroyCancellation,
    );
  }

  Future<HowlServerRoster> observe({required int afterRevision}) {
    if (_closed) throw const NativeServerException('roster_worker_closed');
    if (afterRevision < 0) {
      throw const NativeServerException('roster_revision');
    }
    final id = _nextId++;
    final completer = Completer<HowlServerRoster>();
    _pending[id] = completer;
    _commands.send(<Object?>[0, id, afterRevision]);
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final cancelCode = _cancelCancellation(_cancellation);
    if (cancelCode != 0) {
      _closed = false;
      throw NativeServerException('roster_cancel_$cancelCode');
    }
    final id = _nextId++;
    final closeCompleter = Completer<HowlServerRoster>();
    _pending[id] = closeCompleter;
    _commands.send(<Object?>[1, id]);
    try {
      await closeCompleter.future;
    } on _RosterClosedSignal {
      // Expected acknowledgement; no roster payload accompanies shutdown.
    } finally {
      _destroyCancellation(_cancellation);
      _responses.close();
      _isolate.kill(priority: Isolate.beforeNextEvent);
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(
            const NativeServerException('roster_worker_closed'),
          );
        }
      }
      _pending.clear();
    }
  }

  void _onResponse(Object? message) {
    if (message is! List<Object?> || message.length < 2) return;
    final id = message[0];
    final code = message[1];
    if (id is! int || code is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (code == -1) {
      completer.completeError(const _RosterClosedSignal());
      return;
    }
    if (code != 0) {
      completer.completeError(NativeServerException(_managerFailureCode(code)));
      return;
    }
    if (message.length != 3 || message[2] is! String) {
      completer.completeError(
        const NativeServerException('roster_worker_response'),
      );
      return;
    }
    try {
      completer.complete(parseHowlServerRoster(message[2]! as String));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}

final class _RosterClosedSignal implements Exception {
  const _RosterClosedSignal();
}

final class NativeServerControl {
  NativeServerControl._(this._commands, this._responses, this._isolate) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  final Map<int, Completer<NativeServerMutation>> _pending =
      <int, Completer<NativeServerMutation>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeServerControl> create({required String endpoint}) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _serverControlWorker,
      <Object?>[ready.sendPort, responses.sendPort, endpoint],
      debugName: 'Howl server control',
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    final first = await _awaitServerWorkerStartup(
      ready: ready,
      errors: errors,
      exits: exits,
      errorCode: 'server_control_isolate_error',
      exitCode: 'server_control_isolate_exit',
    );
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeServerException(
        first is String ? first : 'server_control_start',
      );
    }
    return NativeServerControl._(first, responses, isolate);
  }

  Future<NativeServerMutation> createSession(String name) {
    if (name.isEmpty) throw const NativeServerException('session_name');
    return _request(<Object?>[0, name]);
  }

  Future<NativeServerMutation> closeSession(int sessionId) {
    if (sessionId <= 0) throw const NativeServerException('session_id');
    return _request(<Object?>[1, sessionId]);
  }

  Future<NativeServerMutation> _request(List<Object?> action) {
    if (_closed) throw const NativeServerException('server_control_closed');
    final id = _nextId++;
    final completer = Completer<NativeServerMutation>();
    _pending[id] = completer;
    _commands.send(<Object?>[action[0], id, ...action.skip(1)]);
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final done = Completer<void>();
    final receive = ReceivePort();
    receive.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    _commands.send(<Object?>[2, receive.sendPort]);
    try {
      await done.future;
    } finally {
      receive.close();
      _responses.close();
      _isolate.kill(priority: Isolate.beforeNextEvent);
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(
            const NativeServerException('server_control_closed'),
          );
        }
      }
      _pending.clear();
    }
  }

  void _onResponse(Object? message) {
    if (message is! List<Object?> || message.length < 2) return;
    final id = message[0];
    final code = message[1];
    if (id is! int || code is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (code != 0) {
      completer.completeError(NativeServerException(_managerFailureCode(code)));
      return;
    }
    if (message.length != 4 || message[2] is! int || message[3] is! int) {
      completer.completeError(
        const NativeServerException('server_control_response'),
      );
      return;
    }
    completer.complete(
      NativeServerMutation(
        sessionId: message[2]! as int,
        rosterRevision: message[3]! as int,
      ),
    );
  }
}

typedef _ManagerOutputMaximumNative = ffi.Size Function();
typedef _ManagerOutputMaximumDart = int Function();
typedef _ManagerCreateNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ManagerCreateDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
typedef _ManagerDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ManagerDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _ManagerCancellationCreateNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void>,
);
typedef _ManagerCancellationCreateDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void>,
);
typedef _ManagerObserveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ManagerObserveDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
typedef _ManagerCreateSessionNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ManagerCreateSessionDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ManagerCloseSessionNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ManagerCloseSessionDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CancellationCancelNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _CancellationCancelDart = int Function(ffi.Pointer<ffi.Void>);
typedef _CancellationDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CancellationDestroyDart = void Function(ffi.Pointer<ffi.Void>);

ffi.DynamicLibrary _serverLibrary() => Platform.isIOS
    ? ffi.DynamicLibrary.process()
    : ffi.DynamicLibrary.open('libhowl_native_host.so');

Future<Object?> _awaitServerWorkerStartup({
  required ReceivePort ready,
  required ReceivePort errors,
  required ReceivePort exits,
  required String errorCode,
  required String exitCode,
}) async {
  final result = Completer<Object?>();
  void complete(Object? value) {
    if (!result.isCompleted) result.complete(value);
  }

  final readySubscription = ready.listen(complete);
  final errorSubscription = errors.listen((_) => complete(errorCode));
  final exitSubscription = exits.listen((_) => complete(exitCode));
  try {
    return await result.future;
  } finally {
    await readySubscription.cancel();
    await errorSubscription.cancel();
    await exitSubscription.cancel();
    ready.close();
    errors.close();
    exits.close();
  }
}

ffi.Pointer<ffi.Uint8> _copyUtf8(String value) {
  final bytes = utf8.encode(value);
  final pointer = calloc<ffi.Uint8>(bytes.length);
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

String _diagnosticText(ffi.Pointer<ffi.Uint8> bytes, int length) {
  if (length <= 0 || length > _diagnosticBytes) return '';
  return utf8
      .decode(bytes.asTypedList(length), allowMalformed: true)
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();
}

String _managerFailureCode(int code) => switch (code) {
  1 => 'buffer_small',
  2 => 'invalid_handle',
  3 => 'transport',
  4 => 'invalid_arguments',
  102 => 'malformed',
  103 => 'unsupported',
  104 => 'not_found',
  105 => 'name_exists',
  106 => 'capacity',
  107 => 'create_failed',
  108 => 'stale_identity',
  109 => 'stopping',
  110 => 'internal',
  111 => 'unavailable',
  _ => 'native_$code',
};

Future<void> _serverRosterWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final commands = ReceivePort();
  final library = _serverLibrary();
  final maximumOutput = library
      .lookupFunction<_ManagerOutputMaximumNative, _ManagerOutputMaximumDart>(
        'howl_native_manager_output_maximum_bytes',
      )();
  if (maximumOutput <= 0 || maximumOutput > _maximumManagerOutputBytes) {
    ready.send('manager_output_bound');
    commands.close();
    return;
  }
  final create = library
      .lookupFunction<_ManagerCreateNative, _ManagerCreateDart>(
        'howl_native_manager_create',
      );
  final destroy = library
      .lookupFunction<_ManagerDestroyNative, _ManagerDestroyDart>(
        'howl_native_manager_destroy',
      );
  final cancellationCreate = library
      .lookupFunction<
        _ManagerCancellationCreateNative,
        _ManagerCancellationCreateDart
      >('howl_native_manager_cancellation_create');
  final observe = library
      .lookupFunction<_ManagerObserveNative, _ManagerObserveDart>(
        'howl_native_manager_observe',
      );

  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = _copyUtf8(endpoint);
  final diagnosticPointer = calloc<ffi.Uint8>(_diagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  final manager = create(
    endpointPointer,
    endpointBytes.length,
    diagnosticPointer,
    _diagnosticBytes,
    diagnosticLength,
  );
  calloc.free(endpointPointer);
  if (manager == ffi.nullptr) {
    final diagnostic = _diagnosticText(
      diagnosticPointer,
      diagnosticLength.value,
    );
    calloc.free(diagnosticPointer);
    calloc.free(diagnosticLength);
    ready.send(
      diagnostic.isEmpty ? 'manager_create' : 'manager_create:$diagnostic',
    );
    commands.close();
    return;
  }
  calloc.free(diagnosticPointer);
  calloc.free(diagnosticLength);
  final cancellation = cancellationCreate(manager);
  if (cancellation == ffi.nullptr) {
    destroy(manager);
    ready.send('manager_cancellation_create');
    commands.close();
    return;
  }
  final output = calloc<ffi.Uint8>(maximumOutput);
  final outputLength = calloc<ffi.Size>();
  ready.send(<Object?>[commands.sendPort, cancellation.address]);

  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.length < 2) continue;
      final kind = message[0];
      if (kind == 1 && message[1] is int) {
        responses.send(<Object?>[message[1], -1]);
        break;
      }
      if (kind != 0 || message.length != 3) continue;
      final id = message[1];
      final afterRevision = message[2];
      if (id is! int || afterRevision is! int) continue;
      outputLength.value = 0;
      final code = observe(
        manager,
        afterRevision,
        output,
        maximumOutput,
        outputLength,
      );
      if (code != 0) {
        responses.send(<Object?>[id, code]);
        continue;
      }
      final length = outputLength.value;
      if (length <= 0 || length > maximumOutput) {
        responses.send(<Object?>[id, 4]);
        continue;
      }
      final jsonText = utf8.decode(
        output.asTypedList(length),
        allowMalformed: false,
      );
      responses.send(<Object?>[id, 0, jsonText]);
    }
  } finally {
    destroy(manager);
    calloc.free(output);
    calloc.free(outputLength);
    commands.close();
  }
}

Future<void> _serverControlWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final commands = ReceivePort();
  final library = _serverLibrary();
  final create = library
      .lookupFunction<_ManagerCreateNative, _ManagerCreateDart>(
        'howl_native_manager_create',
      );
  final destroy = library
      .lookupFunction<_ManagerDestroyNative, _ManagerDestroyDart>(
        'howl_native_manager_destroy',
      );
  final createSession = library
      .lookupFunction<_ManagerCreateSessionNative, _ManagerCreateSessionDart>(
        'howl_native_manager_create_session',
      );
  final closeSession = library
      .lookupFunction<_ManagerCloseSessionNative, _ManagerCloseSessionDart>(
        'howl_native_manager_close_session',
      );

  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = _copyUtf8(endpoint);
  final diagnosticPointer = calloc<ffi.Uint8>(_diagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  final manager = create(
    endpointPointer,
    endpointBytes.length,
    diagnosticPointer,
    _diagnosticBytes,
    diagnosticLength,
  );
  calloc.free(endpointPointer);
  if (manager == ffi.nullptr) {
    final diagnostic = _diagnosticText(
      diagnosticPointer,
      diagnosticLength.value,
    );
    calloc.free(diagnosticPointer);
    calloc.free(diagnosticLength);
    ready.send(
      diagnostic.isEmpty ? 'manager_create' : 'manager_create:$diagnostic',
    );
    commands.close();
    return;
  }
  calloc.free(diagnosticPointer);
  calloc.free(diagnosticLength);
  final sessionId = calloc<ffi.Uint64>();
  final rosterRevision = calloc<ffi.Uint64>();
  ready.send(commands.sendPort);

  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.isEmpty) continue;
      final kind = message[0];
      if (kind == 2 && message.length == 2 && message[1] is SendPort) {
        (message[1]! as SendPort).send(null);
        break;
      }
      if (message.length != 3 || message[1] is! int) continue;
      final id = message[1]! as int;
      if (kind == 0 && message[2] is String) {
        final name = message[2]! as String;
        final bytes = utf8.encode(name);
        final pointer = _copyUtf8(name);
        sessionId.value = 0;
        rosterRevision.value = 0;
        final code = createSession(
          manager,
          pointer,
          bytes.length,
          sessionId,
          rosterRevision,
        );
        calloc.free(pointer);
        responses.send(<Object?>[
          id,
          code,
          sessionId.value,
          rosterRevision.value,
        ]);
      } else if (kind == 1 && message[2] is int) {
        rosterRevision.value = 0;
        final target = message[2]! as int;
        final code = closeSession(manager, target, rosterRevision);
        responses.send(<Object?>[id, code, target, rosterRevision.value]);
      }
    }
  } finally {
    destroy(manager);
    calloc.free(sessionId);
    calloc.free(rosterRevision);
    commands.close();
  }
}
