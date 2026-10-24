import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'endpoint.dart';
import 'identity.dart';
import '../delete/native_host.dart';

const int _serverTreeOutputBytes = 64 * 1024;
const int _serverTreeDiagnosticBytes = 256;

final class ServerTreeException implements Exception {
  const ServerTreeException(
    this.code, {
    this.kind = NativeFailureKind.permanent,
  });
  final String code;
  final NativeFailureKind kind;

  @override
  String toString() => 'ServerTreeException(${kind.name}:$code)';
}

enum ServerInstanceState { running, exited }

final class ServerInstance {
  const ServerInstance({required this.id, required this.state});
  final String id;
  final ServerInstanceState state;
}

final class ServerSession {
  const ServerSession({
    required this.id,
    required this.name,
    required this.instances,
  });
  final String id;
  final String name;
  final List<ServerInstance> instances;
}

final class ServerTree {
  const ServerTree({
    required this.serverId,
    required this.treeRevision,
    required this.sessions,
  });

  final String serverId;
  final String treeRevision;
  final List<ServerSession> sessions;

  static ServerTree parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const ServerTreeException('json');
    }
    if (decoded is! Map<String, Object?> ||
        decoded['schema'] != 'howl.server.tree/v1') {
      throw const ServerTreeException('schema');
    }
    final serverId = _opaqueIdentity(decoded['server_id'], 'server_id');
    final revision = _opaqueIdentity(decoded['tree_revision'], 'tree_revision');
    final rawSessions = decoded['sessions'];
    if (rawSessions is! List<Object?>) {
      throw const ServerTreeException('sessions');
    }
    final sessions = <ServerSession>[];
    var previousSessionId = BigInt.zero;
    for (final rawSession in rawSessions) {
      if (rawSession is! Map<String, Object?>) {
        throw const ServerTreeException('session');
      }
      final id = _opaqueIdentity(rawSession['session_id'], 'session_id');
      if (BigInt.parse(id) <= previousSessionId) {
        throw const ServerTreeException('session_order');
      }
      previousSessionId = BigInt.parse(id);
      final name = rawSession['name'];
      final rawInstances = rawSession['instances'];
      if (name is! String || name.isEmpty || rawInstances is! List<Object?>) {
        throw const ServerTreeException('session_shape');
      }
      final instances = <ServerInstance>[];
      var previousInstanceId = BigInt.zero;
      for (final rawInstance in rawInstances) {
        if (rawInstance is! Map<String, Object?>) {
          throw const ServerTreeException('instance');
        }
        final instanceId = _opaqueIdentity(
          rawInstance['instance_id'],
          'instance_id',
        );
        if (BigInt.parse(instanceId) <= previousInstanceId) {
          throw const ServerTreeException('instance_order');
        }
        previousInstanceId = BigInt.parse(instanceId);
        final state = switch (rawInstance['state']) {
          'running' => ServerInstanceState.running,
          'exited' => ServerInstanceState.exited,
          _ => throw const ServerTreeException('instance_state'),
        };
        instances.add(ServerInstance(id: instanceId, state: state));
      }
      sessions.add(
        ServerSession(
          id: id,
          name: name,
          instances: List.unmodifiable(instances),
        ),
      );
    }
    return ServerTree(
      serverId: serverId,
      treeRevision: revision,
      sessions: List.unmodifiable(sessions),
    );
  }
}

String _opaqueIdentity(Object? value, String field) {
  if (value is! String) throw ServerTreeException(field);
  try {
    return exactIdentity(value);
  } on FormatException {
    throw ServerTreeException(field);
  }
}

typedef _ServerTreeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ServerTreeDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);

final class ServerTreeRequest {
  ServerTreeRequest(this.future, {this.onCancel});

  final Future<ServerTree> future;
  final void Function()? onCancel;
  bool _canceled = false;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    onCancel?.call();
  }

  static ServerTreeRequest fromFuture(Future<ServerTree> future) =>
      ServerTreeRequest(future);
}

final class NativeServerTree {
  const NativeServerTree._();

  static const Duration responseTimeout = Duration(seconds: 15);

  static ServerTreeRequest request(
    Endpoint endpoint, {
    Duration timeout = responseTimeout,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    final interrupt = NativeInterruptScope.create();
    final address = interrupt.address;
    var deadlineExpired = false;
    final worker = Isolate.run(() => _fetchJson(endpoint.toString(), address));
    late final Timer deadline;
    deadline = Timer(timeout, () {
      deadlineExpired = true;
      interrupt.cancel();
    });
    final future = worker
        .then(ServerTree.parse)
        .catchError((Object error, StackTrace stackTrace) {
          if (deadlineExpired &&
              error is ServerTreeException &&
              error.kind == NativeFailureKind.canceled) {
            throw const ServerTreeException(
              'server_tree_timeout',
              kind: NativeFailureKind.transport,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        })
        .whenComplete(() {
          deadline.cancel();
          interrupt.destroy();
        });
    return ServerTreeRequest(
      future,
      onCancel: () {
        // Explicit owner cancellation wins if the response deadline has not
        // fired yet. Cancel the timer first so it cannot later relabel this
        // same native cancellation as a transport timeout.
        deadline.cancel();
        interrupt.cancel();
      },
    );
  }
}

String _fetchJson(String endpoint, int interruptAddress) {
  final library = Platform.isIOS
      ? ffi.DynamicLibrary.process()
      : ffi.DynamicLibrary.open('libhowl_native_host.so');
  final fetch = library.lookupFunction<_ServerTreeNative, _ServerTreeDart>(
    'howl_native_server_tree',
  );
  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = calloc<ffi.Uint8>(endpointBytes.length);
  endpointPointer.asTypedList(endpointBytes.length).setAll(0, endpointBytes);
  final output = calloc<ffi.Uint8>(_serverTreeOutputBytes);
  final outputLength = calloc<ffi.Size>();
  final diagnostic = calloc<ffi.Uint8>(_serverTreeDiagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  try {
    final code = fetch(
      endpointPointer,
      endpointBytes.length,
      ffi.Pointer<ffi.Void>.fromAddress(interruptAddress),
      output,
      _serverTreeOutputBytes,
      outputLength,
      diagnostic,
      _serverTreeDiagnosticBytes,
      diagnosticLength,
    );
    if (code != 0 || outputLength.value > _serverTreeOutputBytes) {
      final raw = diagnostic.asTypedList(diagnosticLength.value);
      final kind = raw.isEmpty
          ? NativeFailureKind.permanent
          : switch (raw[0]) {
              2 => NativeFailureKind.transport,
              3 => NativeFailureKind.canceled,
              4 => NativeFailureKind.stale,
              _ => NativeFailureKind.permanent,
            };
      final message = raw.length <= 1
          ? ''
          : utf8
                .decode(raw.sublist(1), allowMalformed: true)
                .replaceAll(RegExp(r'[\r\n]+'), ' ')
                .trim();
      throw ServerTreeException(
        message.isEmpty ? 'native_$code' : 'native_$code:$message',
        kind: kind,
      );
    }
    return utf8.decode(output.asTypedList(outputLength.value));
  } finally {
    calloc.free(diagnosticLength);
    calloc.free(diagnostic);
    calloc.free(outputLength);
    calloc.free(output);
    calloc.free(endpointPointer);
  }
}
