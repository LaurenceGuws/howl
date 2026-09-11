import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'native_canvas.dart';
import 'native_canvas_surface.dart';
import 'terminal_presentation.dart';

const int nativeSelectionOutputBytes = 1024 * 1024;
const int _nativeHostMaximumOutputBytes = 8 * 1024 * 1024;
const int _nativeHostImageRefillHeaderBytes = 64;
const int _nativeHostMaximumImageBytes = 16 * 1024 * 1024;
const int _nativeHostMaximumImageRefillBytes =
    _nativeHostImageRefillHeaderBytes + _nativeHostMaximumImageBytes;
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
}

final class NativeHostFrame {
  const NativeHostFrame({
    required this.metadata,
    required this.canvas,
    required this.semanticText,
    required this.semanticTruncated,
  });

  final NativeHostMetadata metadata;
  final NativeCanvasFrame canvas;
  final String semanticText;
  final bool semanticTruncated;
}

sealed class NativeHostObservation {
  const NativeHostObservation();
}

final class NativeHostFrameObservation extends NativeHostObservation {
  const NativeHostFrameObservation(this.bytes);
  final Uint8List bytes;
}

final class NativeHostImageRefillObservation extends NativeHostObservation {
  const NativeHostImageRefillObservation(this.upload);
  final NativeCanvasExternalUpload upload;
}

final class NativeHostImageSupersededObservation extends NativeHostObservation {
  const NativeHostImageSupersededObservation();
}

NativeHostFrame parseNativeHostPacket(
  Uint8List bytes,
  TerminalPresentation expectedPresentation,
) {
  if (bytes.length < _hostHeaderBytes + NativeCanvasFrame.globalHeaderBytes) {
    throw const NativeHostException('packet_truncated');
  }
  if (bytes[0] != 0x48 ||
      bytes[1] != 0x4e ||
      bytes[2] != 0x48 ||
      bytes[3] != 0x31) {
    throw const NativeHostException('packet_magic');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(4, Endian.little) != 2 ||
      data.getUint16(6, Endian.little) != _hostHeaderBytes) {
    throw const NativeHostException('packet_version');
  }
  final total = data.getUint32(8, Endian.little);
  final canvasOffset = data.getUint32(12, Endian.little);
  final canvasLength = data.getUint32(16, Endian.little);
  final semanticLength = data.getUint32(60, Endian.little);
  final semanticOffset = canvasOffset + canvasLength;
  if (total != bytes.length ||
      canvasOffset != _hostHeaderBytes ||
      semanticOffset > bytes.length ||
      semanticLength != bytes.length - semanticOffset) {
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
  );
  if (metadata.revision == 0 || metadata.rows == 0 || metadata.columns == 0) {
    throw const NativeHostException('packet_metadata');
  }
  final canvasBytes = Uint8List.sublistView(
    bytes,
    canvasOffset,
    canvasOffset + canvasLength,
  );
  final frame = NativeCanvasFrame.parse(canvasBytes);
  if (frame.surfaceWidth != metadata.columns * expectedPresentation.cellWidth ||
      frame.surfaceHeight != metadata.rows * expectedPresentation.lineHeight) {
    throw const NativeHostException('packet_canvas');
  }
  final semanticBytes = Uint8List.sublistView(bytes, semanticOffset);
  final semanticText = utf8.decode(semanticBytes, allowMalformed: false);
  return NativeHostFrame(
    metadata: metadata,
    canvas: frame,
    semanticText: semanticText,
    semanticTruncated: flags & (1 << 6) != 0,
  );
}

NativeCanvasExternalUpload parseNativeHostImageRefill(Uint8List bytes) {
  if (bytes.length < _nativeHostImageRefillHeaderBytes ||
      bytes.length > _nativeHostMaximumImageRefillBytes) {
    throw const NativeHostException('image_refill_bounds');
  }
  if (bytes[0] != 0x48 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x52 ||
      bytes[3] != 0x31) {
    throw const NativeHostException('image_refill_magic');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(4, Endian.little) != 1 ||
      data.getUint16(6, Endian.little) != _nativeHostImageRefillHeaderBytes) {
    throw const NativeHostException('image_refill_version');
  }
  final total = data.getUint32(8, Endian.little);
  final pixelLength = data.getUint32(12, Endian.little);
  final source = data.getUint64(16, Endian.little);
  final resource = data.getUint64(24, Endian.little);
  final generation = data.getUint64(32, Endian.little);
  final imageId = data.getUint32(40, Endian.little);
  final format = data.getUint8(44);
  final width = data.getUint16(46, Endian.little);
  final height = data.getUint16(48, Endian.little);
  final stride = data.getUint32(52, Endian.little);
  final imageGeneration = data.getUint64(56, Endian.little);
  final expectedPixels = stride * height;
  if (total != bytes.length ||
      pixelLength != bytes.length - _nativeHostImageRefillHeaderBytes ||
      pixelLength == 0 ||
      pixelLength > _nativeHostMaximumImageBytes ||
      source == 0 ||
      resource == 0 ||
      generation == 0 ||
      imageId == 0 ||
      imageGeneration == 0 ||
      format != 1 ||
      width == 0 ||
      height == 0 ||
      stride != width * 4 ||
      expectedPixels != pixelLength ||
      data.getUint8(45) != 0 ||
      data.getUint16(50, Endian.little) != 0) {
    throw const NativeHostException('image_refill_layout');
  }
  return NativeCanvasExternalUpload(
    resource: NativeCanvasResource(
      key: NativeCanvasResourceKey(source, resource, generation),
      format: format,
      width: width,
      height: height,
      stride: stride,
      uploadOffset: 0,
      uploadLength: 0,
    ),
    pixels: Uint8List.sublistView(bytes, _nativeHostImageRefillHeaderBytes),
  );
}

Uint8List encodeNativeHostResidency(
  NativeCanvasLease? lease, {
  Iterable<NativeCanvasPreloadedResource> preloaded = const [],
}) {
  final resources = <(int, int), NativeCanvasResource>{};
  for (final value in preloaded) {
    final logical = (value.resource.key.source, value.resource.key.resource);
    final prior = resources[logical];
    if (prior == null ||
        value.resource.key.generation > prior.key.generation) {
      resources[logical] = value.resource;
    }
  }
  if (lease != null) {
    for (var index = 0; index < lease.frame.resourceCount; index++) {
      final resource = lease.frame.resource(index);
      final logical = (resource.key.source, resource.key.resource);
      if (lease.images.containsKey(resource.key) &&
          !resources.containsKey(logical) &&
          resources.length < 8) {
        resources[logical] = resource;
      }
    }
  }
  if (resources.isEmpty) return Uint8List(0);
  if (resources.length > 8) {
    throw const NativeHostException('residency_limit');
  }
  final ordered = resources.values.toList(growable: false);
  final bytes = Uint8List(ordered.length * _residencyRecordBytes);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < ordered.length; index++) {
    final resource = ordered[index];
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

Future<Object?> _awaitWorkerStartup({
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

final class NativeHostObserver {
  NativeHostObserver._(
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
  final Map<int, Completer<NativeHostObservation>> _pending =
      <int, Completer<NativeHostObservation>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeHostObserver> createPlatform({
    required String endpoint,
    required TerminalPresentation presentation,
    bool armNextLiveObservation = false,
  }) async {
    final fonts = await _nativeHostFonts();
    return create(
      endpoint: endpoint,
      primaryFontPath: fonts.primary,
      fallbackFontPath: fonts.fallback,
      secondaryFallbackFontPath: fonts.secondaryFallback,
      presentation: presentation,
      armNextLiveObservation: armNextLiveObservation,
    );
  }

  static Future<NativeHostObserver> create({
    required String endpoint,
    required String primaryFontPath,
    required String fallbackFontPath,
    required String secondaryFallbackFontPath,
    required TerminalPresentation presentation,
    bool armNextLiveObservation = false,
  }) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final dylib = _nativeHostLibrary();
    final cancelCancellation = dylib.lookupFunction<
      _CancellationCancelNative,
      _CancellationCancelDart
    >('howl_native_host_cancellation_cancel');
    final destroyCancellation = dylib.lookupFunction<
      _CancellationDestroyNative,
      _CancellationDestroyDart
    >('howl_native_host_cancellation_destroy');
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeHostWorker,
      <Object?>[
        ready.sendPort,
        responses.sendPort,
        endpoint,
        primaryFontPath,
        fallbackFontPath,
        secondaryFallbackFontPath,
        armNextLiveObservation,
        presentation.fontPixels,
        presentation.cellWidth,
        presentation.lineHeight,
      ],
      debugName: 'Howl native observer',
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    final first = await _awaitWorkerStartup(
      ready: ready,
      errors: errors,
      exits: exits,
      errorCode: 'worker_isolate_error',
      exitCode: 'worker_isolate_exit',
    );
    if (first is! List<Object?> ||
        first.length != 2 ||
        first[0] is! SendPort ||
        first[1] is! int ||
        (first[1]! as int) == 0) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeHostException(first is String ? first : 'worker_start');
    }
    final cancellation = ffi.Pointer<ffi.Void>.fromAddress(first[1]! as int);
    return NativeHostObserver._(
      first[0]! as SendPort,
      responses,
      isolate,
      cancellation,
      cancelCancellation,
      destroyCancellation,
    );
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
    final cancelCode = _cancelCancellation(_cancellation);
    if (cancelCode != 0) {
      _closed = false;
      throw NativeHostException('worker_cancel_$cancelCode');
    }
    final id = _nextId++;
    final completer = Completer<NativeHostObservation>();
    _pending[id] = completer;
    _commands.send(<Object?>[1, id]);
    try {
      await completer.future;
    } finally {
      _destroyCancellation(_cancellation);
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
    if (code == 8) {
      completer.complete(const NativeHostImageSupersededObservation());
      return;
    }
    if (code != 0 && code != 6) {
      completer.completeError(NativeHostException('observe_$code'));
      return;
    }
    final transfer = message[2];
    if (transfer is! TransferableTypedData) {
      completer.completeError(const NativeHostException('worker_response'));
      return;
    }
    final bytes = transfer.materialize().asUint8List();
    if (code == 6) {
      try {
        completer.complete(
          NativeHostImageRefillObservation(parseNativeHostImageRefill(bytes)),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
      return;
    }
    completer.complete(NativeHostFrameObservation(bytes));
  }
}

final class _NativeHostFonts {
  const _NativeHostFonts(this.primary, this.fallback, this.secondaryFallback);
  final String primary;
  final String fallback;
  final String secondaryFallback;
}

Future<_NativeHostFonts>? _fontPaths;

Future<_NativeHostFonts> _nativeHostFonts() =>
    _fontPaths ??= _resolveNativeHostFonts();

Future<_NativeHostFonts> _resolveNativeHostFonts() async {
  if (Platform.isAndroid) {
    const channel = MethodChannel('howl.flutter/android_host');
    final filesPath = await channel.invokeMethod<String>('filesPath');
    if (filesPath == null || filesPath.isEmpty) {
      throw const NativeHostException('android_files_path');
    }
    final primary = '$filesPath/IosevkaTermNerdFont-Regular.ttf';
    const fallback = '/system/fonts/NotoNaskhArabic-Regular.ttf';
    const secondaryFallback = '/system/fonts/NotoSansCJK-Regular.ttc';
    if (!await File(primary).exists()) {
      throw const NativeHostException('primary_font_missing');
    }
    if (!await File(fallback).exists()) {
      throw const NativeHostException('fallback_font_missing');
    }
    if (!await File(secondaryFallback).exists()) {
      throw const NativeHostException('secondary_fallback_font_missing');
    }
    return _NativeHostFonts(primary, fallback, secondaryFallback);
  }
  if (Platform.isIOS) {
    final bundlePath = File(Platform.resolvedExecutable).parent.path;
    final primary = '$bundlePath/IosevkaTermNerdFont-Regular.ttf';
    final fallback = '$bundlePath/NotoSans-Regular.ttf';
    if (!await File(primary).exists()) {
      throw const NativeHostException('ios_primary_font_missing');
    }
    if (!await File(fallback).exists()) {
      throw const NativeHostException('ios_fallback_font_missing');
    }
    return _NativeHostFonts(primary, fallback, '');
  }
  if (Platform.isLinux) {
    final primary = await _configuredFont('HOWL_FONT', 'IosevkaTerm Nerd Font');
    final fallback = await _configuredFont(
      'HOWL_FALLBACK_FONT',
      'Noto Sans Arabic',
    );
    final secondaryFallback = await _configuredFont(
      'HOWL_SECONDARY_FALLBACK_FONT',
      'Noto Sans CJK JP',
    );
    return _NativeHostFonts(primary, fallback, secondaryFallback);
  }
  throw const NativeHostException('platform_transport_unavailable');
}

Future<String> _configuredFont(String variable, String family) async {
  final configured = Platform.environment[variable];
  if (configured != null && configured.isNotEmpty) {
    if (!await File(configured).exists()) {
      throw const NativeHostException('configured_font_missing');
    }
    return configured;
  }
  return _fontconfigFile(family);
}

Future<String> _fontconfigFile(String family) async {
  final result = await Process.run('fc-match', <String>[
    '-f',
    '%{family}\n%{file}\n',
    family,
  ]);
  if (result.exitCode != 0) {
    throw const NativeHostException('fontconfig_failed');
  }
  final lines = result.stdout.toString().trim().split('\n');
  if (lines.length < 2 ||
      !lines.first.toLowerCase().contains(family.toLowerCase())) {
    throw const NativeHostException('fontconfig_family_missing');
  }
  final path = lines[1];
  if (path.isEmpty || !await File(path).exists()) {
    throw const NativeHostException('fontconfig_missing');
  }
  return path;
}

typedef _CreateNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
    );
typedef _CreateDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
      int,
      int,
    );
typedef _DestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _CancellationCreateNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);
typedef _CancellationCreateDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);
typedef _CancellationCancelNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _CancellationCancelDart = int Function(ffi.Pointer<ffi.Void>);
typedef _CancellationDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CancellationDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _OutputMinimumBytesNative = ffi.Size Function();
typedef _OutputMinimumBytesDart = int Function();
typedef _ImageRefillSizeNative = ffi.Size Function(ffi.Pointer<ffi.Void>);
typedef _ImageRefillSizeDart = int Function(ffi.Pointer<ffi.Void>);
typedef _FetchImageRefillNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Size>,
    );
typedef _FetchImageRefillDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Size>,
    );
typedef _ObserveNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Uint64,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Size>,
    );
typedef _ObserveDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Size>,
    );
typedef _SetLiveObservePipelineNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint8);
typedef _SetLiveObservePipelineDart = int Function(ffi.Pointer<ffi.Void>, int);

ffi.DynamicLibrary _nativeHostLibrary() =>
    Platform.isIOS
        ? ffi.DynamicLibrary.process()
        : ffi.DynamicLibrary.open('libhowl_native_host.so');

Future<void> _nativeHostWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final primary = init[3]! as String;
  final fallback = init[4]! as String;
  final secondaryFallback = init[5]! as String;
  final armNextLiveObservation = init[6]! as bool;
  final fontPixels = init[7]! as int;
  final cellWidth = init[8]! as int;
  final lineHeight = init[9]! as int;
  final commands = ReceivePort();

  final dylib = _nativeHostLibrary();
  final create = dylib.lookupFunction<_CreateNative, _CreateDart>(
    'howl_native_host_create',
  );
  final destroy = dylib.lookupFunction<_DestroyNative, _DestroyDart>(
    'howl_native_host_destroy',
  );
  final createCancellation = dylib.lookupFunction<
    _CancellationCreateNative,
    _CancellationCreateDart
  >('howl_native_host_cancellation_create');
  final outputMinimumBytes =
      dylib.lookupFunction<_OutputMinimumBytesNative, _OutputMinimumBytesDart>(
        'howl_native_host_output_minimum_bytes',
      )();
  if (outputMinimumBytes <
          _hostHeaderBytes + NativeCanvasFrame.globalHeaderBytes ||
      outputMinimumBytes > _nativeHostMaximumOutputBytes) {
    ready.send('worker_output_bound');
    commands.close();
    return;
  }
  final imageRefillSize = dylib
      .lookupFunction<_ImageRefillSizeNative, _ImageRefillSizeDart>(
        'howl_native_host_image_refill_size',
      );
  final fetchImageRefill = dylib
      .lookupFunction<_FetchImageRefillNative, _FetchImageRefillDart>(
        'howl_native_host_fetch_image_refill',
      );
  final observe = dylib.lookupFunction<_ObserveNative, _ObserveDart>(
    'howl_native_host_observe',
  );
  final setLiveObservePipeline = dylib.lookupFunction<
    _SetLiveObservePipelineNative,
    _SetLiveObservePipelineDart
  >('howl_native_host_set_live_observe_pipeline');

  ffi.Pointer<ffi.Uint8> copyString(String value) {
    final encoded = utf8.encode(value);
    final result = calloc<ffi.Uint8>(encoded.length);
    result.asTypedList(encoded.length).setAll(0, encoded);
    return result;
  }

  final endpointBytes = utf8.encode(endpoint);
  final primaryBytes = utf8.encode(primary);
  final fallbackBytes = utf8.encode(fallback);
  final secondaryFallbackBytes = utf8.encode(secondaryFallback);
  final endpointPointer = copyString(endpoint);
  final primaryPointer = copyString(primary);
  final fallbackPointer = copyString(fallback);
  final secondaryFallbackPointer =
      secondaryFallbackBytes.isEmpty
          ? ffi.nullptr
          : copyString(secondaryFallback);
  final host = create(
    endpointPointer,
    endpointBytes.length,
    primaryPointer,
    primaryBytes.length,
    fallbackPointer,
    fallbackBytes.length,
    secondaryFallbackPointer,
    secondaryFallbackBytes.length,
    fontPixels,
    cellWidth,
    lineHeight,
  );
  calloc.free(endpointPointer);
  calloc.free(primaryPointer);
  calloc.free(fallbackPointer);
  if (secondaryFallbackPointer != ffi.nullptr) {
    calloc.free(secondaryFallbackPointer);
  }
  if (host == ffi.nullptr) {
    ready.send('worker_host_create');
    commands.close();
    return;
  }

  if (armNextLiveObservation && setLiveObservePipeline(host, 1) != 0) {
    destroy(host);
    ready.send('worker_live_observe_pipeline');
    commands.close();
    return;
  }

  final output = calloc<ffi.Uint8>(outputMinimumBytes);
  final outputLength = calloc<ffi.Size>();
  final residency = calloc<ffi.Uint8>(8 * _residencyRecordBytes);
  final cancellation = createCancellation(host);
  if (cancellation == ffi.nullptr) {
    destroy(host);
    calloc.free(output);
    calloc.free(outputLength);
    calloc.free(residency);
    ready.send('worker_cancellation_create');
    commands.close();
    return;
  }
  // Ownership of this independently allocated duplicate-socket handle moves to
  // the creating isolate. The worker remains the sole owner of `host` itself.
  ready.send(<Object?>[commands.sendPort, cancellation.address]);

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
        responses.send(<Object?>[id, 3, null]);
        continue;
      }
      residency
          .asTypedList(8 * _residencyRecordBytes)
          .fillRange(0, 8 * _residencyRecordBytes, 0);
      residency.asTypedList(residencyBytes.length).setAll(0, residencyBytes);
      outputLength.value = 0;
      final code = observe(
        host,
        afterRevision,
        historyOffset,
        residencyBytes.isEmpty ? ffi.nullptr : residency,
        residencyBytes.length,
        output,
        outputMinimumBytes,
        outputLength,
      );
      if (code == 5) {
        final refillSize = imageRefillSize(host);
        if (refillSize < _nativeHostImageRefillHeaderBytes ||
            refillSize > _nativeHostMaximumImageRefillBytes) {
          responses.send(<Object?>[id, 7, null]);
          continue;
        }
        final refill = calloc<ffi.Uint8>(refillSize);
        final refillLength = calloc<ffi.Size>();
        try {
          final refillCode = fetchImageRefill(
            host,
            refill,
            refillSize,
            refillLength,
          );
          if (refillCode == 5) {
            responses.send(<Object?>[id, 8, null]);
            continue;
          }
          if (refillCode != 0 || refillLength.value != refillSize) {
            responses.send(<Object?>[id, 7, null]);
            continue;
          }
          responses.send(<Object?>[
            id,
            6,
            TransferableTypedData.fromList(<Uint8List>[
              refill.asTypedList(refillLength.value),
            ]),
          ]);
        } finally {
          calloc.free(refill);
          calloc.free(refillLength);
        }
        continue;
      }
      if (code != 0 || outputLength.value > outputMinimumBytes) {
        responses.send(<Object?>[id, code == 0 ? 5 : code, null]);
        continue;
      }
      responses.send(<Object?>[
        id,
        0,
        TransferableTypedData.fromList(<Uint8List>[
          output.asTypedList(outputLength.value),
        ]),
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
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextId = 1;
  bool _closed = false;

  static Future<NativeHostControl> create({required String endpoint}) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeControlWorker,
      <Object?>[ready.sendPort, responses.sendPort, endpoint],
      debugName: 'Howl native control',
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    final first = await _awaitWorkerStartup(
      ready: ready,
      errors: errors,
      exits: exits,
      errorCode: 'control_worker_isolate_error',
      exitCode: 'control_worker_isolate_exit',
    );
    if (first is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw NativeHostException(
        first is String ? first : 'control_worker_start',
      );
    }
    return NativeHostControl._(first, responses, isolate);
  }

  Future<void> committedText(String text) =>
      _requestVoid(<Object?>[_NativeControlOperation.committedText, text]);

  Future<void> paste(String text) =>
      _requestVoid(<Object?>[_NativeControlOperation.paste, text]);

  Future<void> namedKey({
    required int keyName,
    required int action,
    int modifiers = 0,
  }) => _requestVoid(<Object?>[
    _NativeControlOperation.namedKey,
    keyName,
    action,
    modifiers,
  ]);

  Future<void> unicodeKey({
    required int scalar,
    required int action,
    int modifiers = 0,
  }) => _requestVoid(<Object?>[
    _NativeControlOperation.unicodeKey,
    scalar,
    action,
    modifiers,
  ]);

  Future<void> focus(bool focused) =>
      _requestVoid(<Object?>[_NativeControlOperation.focus, focused ? 1 : 2]);

  Future<void> resize(int rows, int columns) =>
      _requestVoid(<Object?>[_NativeControlOperation.resize, rows, columns]);

  Future<void> signal(int value) =>
      _requestVoid(<Object?>[_NativeControlOperation.signal, value]);

  Future<void> mouse({
    required int kind,
    required int button,
    required int modifiers,
    required int buttonsDown,
    required int row,
    required int column,
    int? pixelX,
    int? pixelY,
  }) => _requestVoid(<Object?>[
    _NativeControlOperation.mouse,
    kind,
    button,
    modifiers,
    buttonsDown,
    row,
    column,
    pixelX,
    pixelY,
  ]);

  Future<String> selectedText({
    required int startRow,
    required int startColumn,
    required int endRow,
    required int endColumn,
    required int columns,
    required bool alternateScreen,
  }) async {
    final response = await _request(<Object?>[
      _NativeControlOperation.textExtract,
      startRow,
      startColumn,
      endRow,
      endColumn,
      columns,
      alternateScreen ? 1 : 0,
    ]);
    if (response is! TransferableTypedData) {
      throw const NativeHostException('control_selection_response');
    }
    return utf8.decode(
      response.materialize().asUint8List(),
      allowMalformed: false,
    );
  }

  Future<void> _requestVoid(List<Object?> action) async {
    await _request(action);
  }

  Future<Object?> _request(List<Object?> action) {
    if (_closed) throw const NativeHostException('control_worker_closed');
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(<Object?>[action[0], id, ...action.skip(1)]);
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(<Object?>[_NativeControlOperation.close, id]);
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
      completer.complete(message.length > 2 ? message[2] : null);
    } else {
      completer.completeError(NativeHostException('control_$code'));
    }
  }
}

/// Private message vocabulary shared by both sides of the control isolate.
///
/// These values are process-local implementation details, not Howl wire
/// protocol. Keep callers and the worker on this single table so adding an
/// operation cannot silently steal the shutdown opcode again.
enum _NativeControlOperation {
  committedText,
  paste,
  namedKey,
  unicodeKey,
  focus,
  resize,
  signal,
  mouse,
  textExtract,
  close,
}

typedef _ControlCreateNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _ControlCreateDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int);
typedef _ControlDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _ControlDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _ControlTextNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _ControlTextDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, int);
typedef _ControlNamedNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint8, ffi.Uint8, ffi.Uint8);
typedef _ControlNamedDart = int Function(ffi.Pointer<ffi.Void>, int, int, int);
typedef _ControlUnicodeNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Uint8, ffi.Uint8);
typedef _ControlUnicodeDart =
    int Function(ffi.Pointer<ffi.Void>, int, int, int);
typedef _ControlFocusNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint8);
typedef _ControlFocusDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _ControlResizeNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint16, ffi.Uint16);
typedef _ControlResizeDart = int Function(ffi.Pointer<ffi.Void>, int, int);
typedef _ControlSignalNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint8);
typedef _ControlSignalDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _ControlMouseNative =
    ffi.Int32 Function(
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
typedef _ControlMouseDart =
    int Function(
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
typedef _ControlTextExtractNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Uint16,
      ffi.Int32,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint8,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<ffi.Size>,
    );
typedef _ControlTextExtractDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Size>,
    );

Future<void> _nativeControlWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final commands = ReceivePort();
  final dylib = _nativeHostLibrary();
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
  final textExtract = dylib
      .lookupFunction<_ControlTextExtractNative, _ControlTextExtractDart>(
        'howl_native_control_text_extract',
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
  final selectionOutput = calloc<ffi.Uint8>(nativeSelectionOutputBytes);
  final selectionLength = calloc<ffi.Size>();
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
      if (kind is! _NativeControlOperation || id is! int) continue;
      if (kind == _NativeControlOperation.close) {
        responses.send(<Object?>[id, 0]);
        break;
      }
      int code;
      Object? response;
      switch (kind) {
        case _NativeControlOperation.committedText:
          code = textAction(committed, message[2]! as String);
        case _NativeControlOperation.paste:
          code = textAction(paste, message[2]! as String);
        case _NativeControlOperation.namedKey:
          code = named(
            control,
            message[2]! as int,
            message[3]! as int,
            message[4]! as int,
          );
        case _NativeControlOperation.unicodeKey:
          code = unicode(
            control,
            message[2]! as int,
            message[3]! as int,
            message[4]! as int,
          );
        case _NativeControlOperation.focus:
          code = focus(control, message[2]! as int);
        case _NativeControlOperation.resize:
          code = resize(control, message[2]! as int, message[3]! as int);
        case _NativeControlOperation.signal:
          code = signal(control, message[2]! as int);
        case _NativeControlOperation.mouse:
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
        case _NativeControlOperation.textExtract:
          selectionLength.value = 0;
          code = textExtract(
            control,
            message[2]! as int,
            message[3]! as int,
            message[4]! as int,
            message[5]! as int,
            message[6]! as int,
            message[7]! as int,
            selectionOutput,
            nativeSelectionOutputBytes,
            selectionLength,
          );
          if (code == 0 &&
              selectionLength.value <= nativeSelectionOutputBytes) {
            response = TransferableTypedData.fromList(<Uint8List>[
              selectionOutput.asTypedList(selectionLength.value),
            ]);
          } else if (code == 0) {
            code = 4;
          }
        default:
          code = 3;
      }
      responses.send(<Object?>[id, code, response]);
    }
  } finally {
    destroy(control);
    calloc.free(selectionOutput);
    calloc.free(selectionLength);
    commands.close();
  }
}
