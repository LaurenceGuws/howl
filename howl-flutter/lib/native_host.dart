import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'native_canvas_replay.dart';
import 'native_canvas_surface.dart';

const int nativeHostOutputBytes = 256 * 1024;
const int _hostHeaderBytes = 64;
const int _residencyRecordBytes = 32;

final class NativeHostException implements Exception {
  const NativeHostException(this.code);
  final String code;

  @override
  String toString() => 'NativeHostException($code)';
}

final class NativeHostMetadata {
  const NativeHostMetadata({
    required this.revision,
    required this.terminalRevision,
    required this.historyOffset,
    required this.historyCount,
    required this.historyRowBase,
    required this.rows,
    required this.columns,
    required this.cursorRow,
    required this.cursorColumn,
    required this.alternateScreen,
    required this.streamClosed,
    required this.childExited,
    required this.leaderPresent,
    required this.youAreLeader,
    required this.cursorVisible,
    required this.measureBegin,
    required this.measureEnd,
  });

  final int revision;
  final int terminalRevision;
  final int historyOffset;
  final int historyCount;
  final int historyRowBase;
  final int rows;
  final int columns;
  final int cursorRow;
  final int cursorColumn;
  final bool alternateScreen;
  final bool streamClosed;
  final bool childExited;
  final bool leaderPresent;
  final bool youAreLeader;
  final bool cursorVisible;
  final bool measureBegin;
  final bool measureEnd;
}

final class NativeHostFrame {
  const NativeHostFrame({required this.metadata, required this.canvas});

  final NativeHostMetadata metadata;
  final CanvasReplayFrame canvas;
}

NativeHostFrame parseNativeHostPacket(Uint8List bytes) {
  if (bytes.length < _hostHeaderBytes + CanvasReplayCorpus.globalHeaderBytes) {
    throw const NativeHostException('packet_truncated');
  }
  if (bytes[0] != 0x48 ||
      bytes[1] != 0x4e ||
      bytes[2] != 0x48 ||
      bytes[3] != 0x31) {
    throw const NativeHostException('packet_magic');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(4, Endian.little) != 1 ||
      data.getUint16(6, Endian.little) != _hostHeaderBytes) {
    throw const NativeHostException('packet_version');
  }
  final total = data.getUint32(8, Endian.little);
  final canvasOffset = data.getUint32(12, Endian.little);
  final canvasLength = data.getUint32(16, Endian.little);
  if (total != bytes.length ||
      canvasOffset != _hostHeaderBytes ||
      canvasLength != bytes.length - canvasOffset) {
    throw const NativeHostException('packet_layout');
  }
  final flags = data.getUint32(20, Endian.little);
  final metadata = NativeHostMetadata(
    revision: data.getUint64(24, Endian.little),
    terminalRevision: data.getUint64(32, Endian.little),
    historyOffset: data.getUint32(40, Endian.little),
    historyCount: data.getUint32(44, Endian.little),
    historyRowBase: data.getUint32(48, Endian.little),
    rows: data.getUint16(52, Endian.little),
    columns: data.getUint16(54, Endian.little),
    cursorRow: data.getUint16(56, Endian.little),
    cursorColumn: data.getUint16(58, Endian.little),
    alternateScreen: flags & (1 << 0) != 0,
    streamClosed: flags & (1 << 1) != 0,
    childExited: flags & (1 << 2) != 0,
    leaderPresent: flags & (1 << 3) != 0,
    youAreLeader: flags & (1 << 4) != 0,
    cursorVisible: flags & (1 << 5) != 0,
    measureBegin: flags & (1 << 6) != 0,
    measureEnd: flags & (1 << 7) != 0,
  );
  if (metadata.revision == 0 || metadata.rows == 0 || metadata.columns == 0) {
    throw const NativeHostException('packet_metadata');
  }
  final canvasBytes = Uint8List.sublistView(
    bytes,
    canvasOffset,
    canvasOffset + canvasLength,
  );
  final corpus = CanvasReplayCorpus.parse(canvasBytes);
  if (corpus.frameCount != 1 ||
      corpus.surfaceWidth != metadata.columns * 10 ||
      corpus.surfaceHeight != metadata.rows * 20) {
    throw const NativeHostException('packet_canvas');
  }
  return NativeHostFrame(metadata: metadata, canvas: corpus.frame(0));
}

Uint8List encodeNativeHostResidency(CanvasReplayFrameLease? lease) {
  if (lease == null || lease.images.isEmpty) return Uint8List(0);
  final resources = <CanvasReplayResource>[];
  for (var index = 0; index < lease.frame.resourceCount; index++) {
    final resource = lease.frame.resource(index);
    if (lease.images.containsKey(resource.key)) resources.add(resource);
  }
  final bytes = Uint8List(resources.length * _residencyRecordBytes);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < resources.length; index++) {
    final resource = resources[index];
    final offset = index * _residencyRecordBytes;
    data.setUint64(offset, resource.key.source, Endian.little);
    data.setUint64(offset + 8, resource.key.resource, Endian.little);
    data.setUint64(offset + 16, resource.key.generation, Endian.little);
    data.setUint8(offset + 24, resource.format);
    data.setUint16(offset + 26, resource.width, Endian.little);
    data.setUint16(offset + 28, resource.height, Endian.little);
  }
  return bytes;
}

final class NativeHostObservation {
  const NativeHostObservation({
    required this.bytes,
    required this.workerMicroseconds,
  });

  final Uint8List bytes;
  final int workerMicroseconds;
}

final class NativeHostObserver {
  NativeHostObserver._(this._commands, this._responses, this._isolate) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  final Map<int, Completer<NativeHostObservation>> _pending =
      <int, Completer<NativeHostObservation>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeHostObserver> createAndroid({
    required String endpoint,
  }) async {
    const channel = MethodChannel('howl.flutter/android_host');
    final filesPath = await channel.invokeMethod<String>('filesPath');
    if (filesPath == null || filesPath.isEmpty) {
      throw const NativeHostException('android_files_path');
    }
    return create(
      endpoint: endpoint,
      primaryFontPath: '$filesPath/IosevkaTermNerdFont-Regular.ttf',
      fallbackFontPath: '/system/fonts/NotoNaskhArabic-Regular.ttf',
    );
  }

  static Future<NativeHostObserver> create({
    required String endpoint,
    required String primaryFontPath,
    required String fallbackFontPath,
  }) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeHostWorker,
      <Object?>[
        ready.sendPort,
        responses.sendPort,
        endpoint,
        primaryFontPath,
        fallbackFontPath,
      ],
      debugName: 'Howl native observer',
    );
    final first = await ready.first;
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeHostException(first is String ? first : 'worker_start');
    }
    ready.close();
    return NativeHostObserver._(first, responses, isolate);
  }

  Future<NativeHostObservation> observe({
    required int afterRevision,
    required int historyOffset,
    required Uint8List residency,
  }) {
    if (_closed) throw const NativeHostException('worker_closed');
    final id = _nextId++;
    final completer = Completer<NativeHostObservation>();
    _pending[id] = completer;
    _commands.send(<Object?>[
      0,
      id,
      afterRevision,
      historyOffset,
      TransferableTypedData.fromList(<Uint8List>[residency]),
    ]);
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final id = _nextId++;
    final completer = Completer<NativeHostObservation>();
    _pending[id] = completer;
    _commands.send(<Object?>[1, id]);
    try {
      await completer.future;
    } finally {
      _responses.close();
      _isolate.kill(priority: Isolate.beforeNextEvent);
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(const NativeHostException('worker_closed'));
        }
      }
      _pending.clear();
    }
  }

  void _onResponse(Object? message) {
    if (message is! List<Object?> || message.length < 3) return;
    final id = message[0];
    final code = message[1];
    if (id is! int || code is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (code != 0) {
      completer.completeError(NativeHostException('observe_$code'));
      return;
    }
    final transfer = message[2];
    final workerMicroseconds = message.length > 3 ? message[3] : 0;
    if (transfer is! TransferableTypedData || workerMicroseconds is! int) {
      completer.completeError(const NativeHostException('worker_response'));
      return;
    }
    completer.complete(
      NativeHostObservation(
        bytes: transfer.materialize().asUint8List(),
        workerMicroseconds: workerMicroseconds,
      ),
    );
  }
}

typedef _CreateNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef _CreateDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _DestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _ObserveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint32,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ObserveDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);

Future<void> _nativeHostWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final primary = init[3]! as String;
  final fallback = init[4]! as String;
  final commands = ReceivePort();

  final dylib = ffi.DynamicLibrary.open('libhowl_native_host.so');
  final create = dylib.lookupFunction<_CreateNative, _CreateDart>(
    'howl_native_host_create',
  );
  final destroy = dylib.lookupFunction<_DestroyNative, _DestroyDart>(
    'howl_native_host_destroy',
  );
  final observe = dylib.lookupFunction<_ObserveNative, _ObserveDart>(
    'howl_native_host_observe',
  );

  ffi.Pointer<ffi.Uint8> copyString(String value) {
    final encoded = utf8.encode(value);
    final result = calloc<ffi.Uint8>(encoded.length);
    result.asTypedList(encoded.length).setAll(0, encoded);
    return result;
  }

  final endpointBytes = utf8.encode(endpoint);
  final primaryBytes = utf8.encode(primary);
  final fallbackBytes = utf8.encode(fallback);
  final endpointPointer = copyString(endpoint);
  final primaryPointer = copyString(primary);
  final fallbackPointer = copyString(fallback);
  final host = create(
    endpointPointer,
    endpointBytes.length,
    primaryPointer,
    primaryBytes.length,
    fallbackPointer,
    fallbackBytes.length,
  );
  calloc.free(endpointPointer);
  calloc.free(primaryPointer);
  calloc.free(fallbackPointer);
  if (host == ffi.nullptr) {
    ready.send('worker_host_create');
    commands.close();
    return;
  }

  final output = calloc<ffi.Uint8>(nativeHostOutputBytes);
  final outputLength = calloc<ffi.Size>();
  final residency = calloc<ffi.Uint8>(8 * _residencyRecordBytes);
  ready.send(commands.sendPort);

  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.isEmpty) continue;
      final kind = message[0];
      if (kind == 1) {
        if (message.length > 1 && message[1] is int) {
          responses.send(<Object?>[
            message[1],
            0,
            TransferableTypedData.fromList(<Uint8List>[Uint8List(0)]),
            0,
          ]);
        }
        break;
      }
      if (kind != 0 || message.length != 5) continue;
      final id = message[1]! as int;
      final afterRevision = message[2]! as int;
      final historyOffset = message[3]! as int;
      final transfer = message[4]! as TransferableTypedData;
      final residencyBytes = transfer.materialize().asUint8List();
      if (residencyBytes.length > 8 * _residencyRecordBytes) {
        responses.send(<Object?>[id, 3, null, 0]);
        continue;
      }
      residency
          .asTypedList(8 * _residencyRecordBytes)
          .fillRange(0, 8 * _residencyRecordBytes, 0);
      residency.asTypedList(residencyBytes.length).setAll(0, residencyBytes);
      outputLength.value = 0;
      final watch = Stopwatch()..start();
      final code = observe(
        host,
        afterRevision,
        historyOffset,
        residencyBytes.isEmpty ? ffi.nullptr : residency,
        residencyBytes.length,
        output,
        nativeHostOutputBytes,
        outputLength,
      );
      if (code != 0 || outputLength.value > nativeHostOutputBytes) {
        watch.stop();
        responses.send(<Object?>[
          id,
          code == 0 ? 5 : code,
          null,
          watch.elapsedMicroseconds,
        ]);
        continue;
      }
      final bytes = Uint8List.fromList(output.asTypedList(outputLength.value));
      watch.stop();
      responses.send(<Object?>[
        id,
        0,
        TransferableTypedData.fromList(<Uint8List>[bytes]),
        watch.elapsedMicroseconds,
      ]);
    }
  } finally {
    destroy(host);
    calloc.free(output);
    calloc.free(outputLength);
    calloc.free(residency);
    commands.close();
  }
}

final class NativeHostControl {
  NativeHostControl._(this._commands, this._responses, this._isolate) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _isolate;
  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeHostControl> create({required String endpoint}) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeControlWorker,
      <Object?>[ready.sendPort, responses.sendPort, endpoint],
      debugName: 'Howl native control',
    );
    final first = await ready.first;
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeHostException(
        first is String ? first : 'control_worker_start',
      );
    }
    ready.close();
    return NativeHostControl._(first, responses, isolate);
  }

  Future<void> committedText(String text) => _request(<Object?>[0, text]);

  Future<void> paste(String text) => _request(<Object?>[1, text]);

  Future<void> namedKey({
    required int keyName,
    required int action,
    int modifiers = 0,
  }) => _request(<Object?>[2, keyName, action, modifiers]);

  Future<void> unicodeKey({
    required int scalar,
    required int action,
    int modifiers = 0,
  }) => _request(<Object?>[3, scalar, action, modifiers]);

  Future<void> focus(bool focused) => _request(<Object?>[4, focused ? 1 : 2]);

  Future<void> resize(int rows, int columns) =>
      _request(<Object?>[5, rows, columns]);

  Future<void> signal(int value) => _request(<Object?>[6, value]);

  Future<void> mouse({
    required int kind,
    required int button,
    required int modifiers,
    required int buttonsDown,
    required int row,
    required int column,
    int? pixelX,
    int? pixelY,
  }) => _request(<Object?>[
    7,
    kind,
    button,
    modifiers,
    buttonsDown,
    row,
    column,
    pixelX,
    pixelY,
  ]);

  Future<void> _request(List<Object?> action) {
    if (_closed) throw const NativeHostException('control_worker_closed');
    final id = _nextId++;
    final completer = Completer<void>();
    _pending[id] = completer;
    _commands.send(<Object?>[action[0], id, ...action.skip(1)]);
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final id = _nextId++;
    final completer = Completer<void>();
    _pending[id] = completer;
    _commands.send(<Object?>[8, id]);
    try {
      await completer.future;
    } finally {
      _responses.close();
      _isolate.kill(priority: Isolate.beforeNextEvent);
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(
            const NativeHostException('control_worker_closed'),
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
    if (code == 0) {
      completer.complete();
    } else {
      completer.completeError(NativeHostException('control_$code'));
    }
  }
}

typedef _ControlCreateNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef _ControlCreateDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _ControlDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ControlDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _ControlTextNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef _ControlTextDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _ControlNamedNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint8,
  ffi.Uint8,
  ffi.Uint8,
);
typedef _ControlNamedDart = int Function(ffi.Pointer<ffi.Void>, int, int, int);
typedef _ControlUnicodeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint32,
  ffi.Uint8,
  ffi.Uint8,
);
typedef _ControlUnicodeDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
);
typedef _ControlFocusNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint8,
);
typedef _ControlFocusDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _ControlResizeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint16,
  ffi.Uint16,
);
typedef _ControlResizeDart = int Function(ffi.Pointer<ffi.Void>, int, int);
typedef _ControlSignalNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint8,
);
typedef _ControlSignalDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _ControlMouseNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint8,
  ffi.Uint8,
  ffi.Uint8,
  ffi.Uint8,
  ffi.Int32,
  ffi.Uint16,
  ffi.Uint8,
  ffi.Uint32,
  ffi.Uint32,
);
typedef _ControlMouseDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
);

Future<void> _nativeControlWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final commands = ReceivePort();
  final dylib = ffi.DynamicLibrary.open('libhowl_native_host.so');
  final create = dylib.lookupFunction<_ControlCreateNative, _ControlCreateDart>(
    'howl_native_control_create',
  );
  final destroy = dylib
      .lookupFunction<_ControlDestroyNative, _ControlDestroyDart>(
        'howl_native_control_destroy',
      );
  final committed = dylib.lookupFunction<_ControlTextNative, _ControlTextDart>(
    'howl_native_control_committed_text',
  );
  final paste = dylib.lookupFunction<_ControlTextNative, _ControlTextDart>(
    'howl_native_control_paste',
  );
  final named = dylib.lookupFunction<_ControlNamedNative, _ControlNamedDart>(
    'howl_native_control_named_key',
  );
  final unicode = dylib
      .lookupFunction<_ControlUnicodeNative, _ControlUnicodeDart>(
        'howl_native_control_unicode_key',
      );
  final focus = dylib.lookupFunction<_ControlFocusNative, _ControlFocusDart>(
    'howl_native_control_focus',
  );
  final resize = dylib.lookupFunction<_ControlResizeNative, _ControlResizeDart>(
    'howl_native_control_resize',
  );
  final signal = dylib.lookupFunction<_ControlSignalNative, _ControlSignalDart>(
    'howl_native_control_signal',
  );
  final mouse = dylib.lookupFunction<_ControlMouseNative, _ControlMouseDart>(
    'howl_native_control_mouse',
  );

  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = calloc<ffi.Uint8>(endpointBytes.length);
  endpointPointer.asTypedList(endpointBytes.length).setAll(0, endpointBytes);
  final control = create(endpointPointer, endpointBytes.length);
  calloc.free(endpointPointer);
  if (control == ffi.nullptr) {
    ready.send('control_host_create');
    commands.close();
    return;
  }
  ready.send(commands.sendPort);

  int textAction(_ControlTextDart function, String value) {
    final bytes = utf8.encode(value);
    if (bytes.isEmpty) return 3;
    final pointer = calloc<ffi.Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    try {
      return function(control, pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.length < 2) continue;
      final kind = message[0];
      final id = message[1];
      if (kind is! int || id is! int) continue;
      if (kind == 8) {
        responses.send(<Object?>[id, 0]);
        break;
      }
      int code;
      switch (kind) {
        case 0:
          code = textAction(committed, message[2]! as String);
        case 1:
          code = textAction(paste, message[2]! as String);
        case 2:
          code = named(
            control,
            message[2]! as int,
            message[3]! as int,
            message[4]! as int,
          );
        case 3:
          code = unicode(
            control,
            message[2]! as int,
            message[3]! as int,
            message[4]! as int,
          );
        case 4:
          code = focus(control, message[2]! as int);
        case 5:
          code = resize(control, message[2]! as int, message[3]! as int);
        case 6:
          code = signal(control, message[2]! as int);
        case 7:
          final pixelX = message[8] as int?;
          final pixelY = message[9] as int?;
          if ((pixelX == null) != (pixelY == null)) {
            code = 3;
          } else {
            code = mouse(
              control,
              message[2]! as int,
              message[3]! as int,
              message[4]! as int,
              message[5]! as int,
              message[6]! as int,
              message[7]! as int,
              pixelX == null ? 0 : 1,
              pixelX ?? 0,
              pixelY ?? 0,
            );
          }
        default:
          code = 3;
      }
      responses.send(<Object?>[id, code]);
    }
  } finally {
    destroy(control);
    commands.close();
  }
}
