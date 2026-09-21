import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'instance_target.dart';
import 'native_canvas.dart';
import 'native_canvas_surface.dart';
import 'terminal_presentation.dart';
import 'terminal_selection.dart';

const int nativeSelectionOutputBytes = 1024 * 1024;
const int nativeInteractionStateBytes = 20;
const int _nativeHostMaximumOutputBytes = 8 * 1024 * 1024;
const int _nativeHostImageRefillHeaderBytes = 56;
const int _nativeHostMaximumImageBytes = 16 * 1024 * 1024;
const int _nativeHostMaximumImageRefillBytes =
    _nativeHostImageRefillHeaderBytes + _nativeHostMaximumImageBytes;
const int _hostHeaderBytes = 64;
const int _residencyRecordBytes = 24;
const int _nativeCreateDiagnosticBytes = 256;

enum NativeFailureKind { permanent, transport, canceled, stale }

final class NativeHostException implements Exception {
  const NativeHostException(
    this.code, {
    this.kind = NativeFailureKind.permanent,
  });

  final String code;
  final NativeFailureKind kind;

  @override
  String toString() => 'NativeHostException(${kind.name}:$code)';
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
    required this.selectionRows,
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
  final List<TerminalSelectionRowShape> selectionRows;
}

final class NativeInteractionState {
  const NativeInteractionState({
    required this.terminalRevision,
    required this.alternateScroll,
    required this.mouseTracking,
    required this.mouseProtocol,
    required this.pointerMode,
  });

  final int terminalRevision;
  final bool alternateScroll;
  final int mouseTracking;
  final int mouseProtocol;
  final int pointerMode;

  bool get mouseTrackingEnabled => mouseTracking != 0;
}

NativeInteractionState parseNativeInteractionState(Uint8List bytes) {
  if (bytes.length != nativeInteractionStateBytes) {
    throw const NativeHostException('interaction_state_size');
  }
  final data = ByteData.sublistView(bytes);
  final flags = data.getUint32(8, Endian.big);
  final mouseTracking = data.getUint8(12);
  final mouseProtocol = data.getUint8(13);
  final pointerMode = data.getUint8(18);
  if ((flags & ~0x1fff) != 0 ||
      mouseTracking > 4 ||
      mouseProtocol > 4 ||
      pointerMode > 3 ||
      data.getUint8(19) != 0) {
    throw const NativeHostException('interaction_state_layout');
  }
  return NativeInteractionState(
    terminalRevision: data.getUint64(0, Endian.big),
    alternateScroll: (flags & (1 << 10)) != 0,
    mouseTracking: mouseTracking,
    mouseProtocol: mouseProtocol,
    pointerMode: pointerMode,
  );
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
  if (data.getUint16(4, Endian.little) != 3 ||
      data.getUint16(6, Endian.little) != _hostHeaderBytes) {
    throw const NativeHostException('packet_version');
  }
  final total = data.getUint32(8, Endian.little);
  final canvasOffset = data.getUint32(12, Endian.little);
  final canvasLength = data.getUint32(16, Endian.little);
  final semanticLength = data.getUint32(60, Endian.little);
  final rows = data.getUint16(52, Endian.little);
  final selectionRowsOffset = canvasOffset + canvasLength;
  final selectionRowsLength = rows * 2;
  final semanticOffset = selectionRowsOffset + selectionRowsLength;
  if (total != bytes.length ||
      canvasOffset != _hostHeaderBytes ||
      semanticOffset > bytes.length ||
      semanticLength != bytes.length - semanticOffset) {
    throw const NativeHostException('packet_layout');
  }
  final flags = data.getUint32(20, Endian.little);
  final columns = data.getUint16(54, Endian.little);
  final selectionRows = List<TerminalSelectionRowShape>.generate(rows, (row) {
    final encoded = data.getUint16(
      selectionRowsOffset + row * 2,
      Endian.little,
    );
    final contentEndExclusive = encoded & 0x7fff;
    if (contentEndExclusive > columns) {
      throw const NativeHostException('packet_selection_rows');
    }
    return TerminalSelectionRowShape(
      contentEndExclusive: contentEndExclusive,
      wrapped: encoded & 0x8000 != 0,
    );
  }, growable: false);
  final metadata = NativeHostMetadata(
    revision: data.getUint64(24, Endian.little),
    terminalRevision: data.getUint64(32, Endian.little),
    historyOffset: data.getUint32(40, Endian.little),
    historyCount: data.getUint32(44, Endian.little),
    historyRowBase: data.getUint32(48, Endian.little),
    rows: rows,
    columns: columns,
    cursorRow: data.getUint16(56, Endian.little),
    cursorColumn: data.getUint16(58, Endian.little),
    alternateScreen: flags & (1 << 0) != 0,
    streamClosed: flags & (1 << 1) != 0,
    childExited: flags & (1 << 2) != 0,
    leaderPresent: flags & (1 << 3) != 0,
    youAreLeader: flags & (1 << 4) != 0,
    cursorVisible: flags & (1 << 5) != 0,
    selectionRows: selectionRows,
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
  if (data.getUint16(4, Endian.little) != 2 ||
      data.getUint16(6, Endian.little) != _nativeHostImageRefillHeaderBytes) {
    throw const NativeHostException('image_refill_version');
  }
  final total = data.getUint32(8, Endian.little);
  final pixelLength = data.getUint32(12, Endian.little);
  final resource = data.getUint64(16, Endian.little);
  final generation = data.getUint64(24, Endian.little);
  final imageId = data.getUint32(32, Endian.little);
  final format = data.getUint8(36);
  final width = data.getUint16(38, Endian.little);
  final height = data.getUint16(40, Endian.little);
  final stride = data.getUint32(44, Endian.little);
  final imageGeneration = data.getUint64(48, Endian.little);
  final expectedPixels = stride * height;
  if (total != bytes.length ||
      pixelLength != bytes.length - _nativeHostImageRefillHeaderBytes ||
      pixelLength == 0 ||
      pixelLength > _nativeHostMaximumImageBytes ||
      resource == 0 ||
      generation == 0 ||
      imageId == 0 ||
      imageGeneration == 0 ||
      format != 1 ||
      width == 0 ||
      height == 0 ||
      stride != width * 4 ||
      expectedPixels != pixelLength ||
      data.getUint8(37) != 0 ||
      data.getUint16(42, Endian.little) != 0) {
    throw const NativeHostException('image_refill_layout');
  }
  return NativeCanvasExternalUpload(
    resource: NativeCanvasResource(
      key: NativeCanvasResourceKey(resource, generation),
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
  final resources = <int, NativeCanvasResource>{};
  for (final value in preloaded) {
    final logical = value.resource.key.resource;
    final prior = resources[logical];
    if (prior == null || value.resource.key.generation > prior.key.generation) {
      resources[logical] = value.resource;
    }
  }
  if (lease != null) {
    for (var index = 0; index < lease.frame.resourceCount; index++) {
      final resource = lease.frame.resource(index);
      final logical = resource.key.resource;
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
    data.setUint64(offset, resource.key.resource, Endian.little);
    data.setUint64(offset + 8, resource.key.generation, Endian.little);
    data.setUint8(offset + 16, resource.format);
    data.setUint16(offset + 18, resource.width, Endian.little);
    data.setUint16(offset + 20, resource.height, Endian.little);
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
    this._interrupt,
    this.maximumRows,
    this.maximumColumns,
  ) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final NativeInterruptScope _interrupt;
  final int maximumRows;
  final int maximumColumns;
  final Map<int, Completer<NativeHostObservation>> _pending =
      <int, Completer<NativeHostObservation>>{};
  int _nextId = 1;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Selects the native delta/raw-cache policy for live observations, including
  /// one prearmed delta request. False uses compressed complete snapshots.
  /// Dart's display overlap is independent of this native policy.
  static Future<NativeHostObserver> createPlatform({
    required HowlInstanceTarget target,
    required TerminalPresentation presentation,
    required NativeInterruptScope interrupt,
    bool useLiveDeltas = false,
  }) async {
    if (interrupt.canceled) {
      throw const NativeHostException(
        'worker_canceled_before_fonts',
        kind: NativeFailureKind.canceled,
      );
    }
    final fonts = await _nativeHostFonts();
    if (interrupt.canceled) {
      throw const NativeHostException(
        'worker_canceled_after_fonts',
        kind: NativeFailureKind.canceled,
      );
    }
    return create(
      target: target,
      primaryFontPath: fonts.primary,
      fallbackFontPath: fonts.fallback,
      secondaryFallbackFontPath: fonts.secondaryFallback,
      presentation: presentation,
      interrupt: interrupt,
      useLiveDeltas: useLiveDeltas,
    );
  }

  static Future<NativeHostObserver> create({
    required HowlInstanceTarget target,
    required String primaryFontPath,
    required String fallbackFontPath,
    required String secondaryFallbackFontPath,
    required TerminalPresentation presentation,
    required NativeInterruptScope interrupt,
    bool useLiveDeltas = false,
  }) async {
    if (interrupt.canceled) {
      throw const NativeHostException(
        'worker_canceled_before_spawn',
        kind: NativeFailureKind.canceled,
      );
    }
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeHostWorker,
      <Object?>[
        ready.sendPort,
        responses.sendPort,
        target.endpointText,
        target.nativeServerId,
        target.sessionId,
        target.instanceId,
        primaryFontPath,
        fallbackFontPath,
        secondaryFallbackFontPath,
        useLiveDeltas,
        presentation.fontPixels,
        presentation.cellWidth,
        presentation.lineHeight,
        interrupt.address,
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
        first.length != 3 ||
        first[0] is! SendPort ||
        first[1] is! int ||
        first[2] is! int ||
        (first[1]! as int) <= 0 ||
        (first[2]! as int) <= 0) {
      isolate.kill(priority: Isolate.immediate);
      responses.close();
      throw _workerStartupFailure(first, 'worker_start');
    }
    return NativeHostObserver._(
      first[0]! as SendPort,
      responses,
      interrupt,
      first[1]! as int,
      first[2]! as int,
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

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _interrupt.cancel();
    final id = _nextId++;
    final completer = Completer<NativeHostObservation>();
    _pending[id] = completer;
    _commands.send(<Object?>[1, id]);
    try {
      // The worker acknowledges only after native Host destruction and all
      // worker-owned allocations are released. Completion therefore means the
      // borrowed Interrupt is no longer reachable by this worker.
      await completer.future;
    } finally {
      _responses.close();
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
      final kind = switch (code) {
        7 => NativeFailureKind.transport,
        9 => NativeFailureKind.canceled,
        10 => NativeFailureKind.stale,
        _ => NativeFailureKind.permanent,
      };
      completer.completeError(NativeHostException('observe_$code', kind: kind));
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

typedef _CreateNative = ffi.Pointer<ffi.Void> Function(
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
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _CreateDart = ffi.Pointer<ffi.Void> Function(
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
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
typedef _CreateManagedNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint16,
  ffi.Uint16,
  ffi.Uint16,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _CreateManagedDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
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
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
typedef _DestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _HostVersionNative = ffi.Uint32 Function();
typedef _HostVersionDart = int Function();
typedef _InterruptCreateNative = ffi.Pointer<ffi.Void> Function();
typedef _InterruptCreateDart = ffi.Pointer<ffi.Void> Function();
typedef _InterruptCancelNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _InterruptCancelDart = int Function(ffi.Pointer<ffi.Void>);
typedef _InterruptDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _InterruptDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _OutputMinimumBytesNative = ffi.Size Function();
typedef _OutputMinimumBytesDart = int Function();
typedef _ImageRefillSizeNative = ffi.Size Function(ffi.Pointer<ffi.Void>);
typedef _ImageRefillSizeDart = int Function(ffi.Pointer<ffi.Void>);
typedef _FetchImageRefillNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _FetchImageRefillDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
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
typedef _SetLiveObservePipelineNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint8,
);
typedef _SetLiveObservePipelineDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _PresentationBoundNative = ffi.Uint32 Function();
typedef _PresentationBoundDart = int Function();

ffi.DynamicLibrary _nativeHostLibrary() {
  final library = Platform.isIOS
      ? ffi.DynamicLibrary.process()
      : ffi.DynamicLibrary.open('libhowl_native_host.so');
  final version = library.lookupFunction<_HostVersionNative, _HostVersionDart>(
    'howl_native_host_version',
  )();
  if (version != 5) {
    throw NativeHostException('native_host_version_$version');
  }
  return library;
}

final class NativeInterruptScope {
  NativeInterruptScope._(this._raw, this._cancelNative, this._destroyNative);

  factory NativeInterruptScope.create() {
    final dylib = _nativeHostLibrary();
    final create = dylib
        .lookupFunction<_InterruptCreateNative, _InterruptCreateDart>(
          'howl_native_interrupt_create',
        );
    final cancel = dylib
        .lookupFunction<_InterruptCancelNative, _InterruptCancelDart>(
          'howl_native_interrupt_cancel',
        );
    final destroy = dylib
        .lookupFunction<_InterruptDestroyNative, _InterruptDestroyDart>(
          'howl_native_interrupt_destroy',
        );
    final raw = create();
    if (raw == ffi.nullptr) {
      throw const NativeHostException('interrupt_create');
    }
    return NativeInterruptScope._(raw, cancel, destroy);
  }

  final ffi.Pointer<ffi.Void> _raw;
  final _InterruptCancelDart _cancelNative;
  final _InterruptDestroyDart _destroyNative;
  bool _canceled = false;
  bool _destroyed = false;

  int get address {
    if (_destroyed) throw const NativeHostException('interrupt_destroyed');
    return _raw.address;
  }

  bool get canceled => _canceled;

  void cancel() {
    if (_destroyed || _canceled) return;
    final code = _cancelNative(_raw);
    if (code != 0) {
      throw NativeHostException('interrupt_cancel_$code');
    }
    _canceled = true;
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _destroyNative(_raw);
  }
}

({NativeFailureKind kind, String message}) _nativeCreateFailure(
  ffi.Pointer<ffi.Uint8> bytes,
  int length,
) {
  if (length <= 0 || length > _nativeCreateDiagnosticBytes) {
    return (kind: NativeFailureKind.permanent, message: '');
  }
  final raw = bytes.asTypedList(length);
  final kind = switch (raw[0]) {
    2 => NativeFailureKind.transport,
    3 => NativeFailureKind.canceled,
    4 => NativeFailureKind.stale,
    _ => NativeFailureKind.permanent,
  };
  final message = length == 1
      ? ''
      : utf8
            .decode(raw.sublist(1), allowMalformed: true)
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
  return (kind: kind, message: message);
}

NativeHostException _workerStartupFailure(Object? value, String fallback) {
  if (value is List<Object?> &&
      value.length == 2 &&
      value[0] is String &&
      value[1] is int) {
    final index = value[1]! as int;
    final kind = index >= 0 && index < NativeFailureKind.values.length
        ? NativeFailureKind.values[index]
        : NativeFailureKind.permanent;
    return NativeHostException(value[0]! as String, kind: kind);
  }
  return NativeHostException(value is String ? value : fallback);
}

Future<void> _nativeHostWorker(List<Object?> init) async {
  final ready = init[0]! as SendPort;
  final responses = init[1]! as SendPort;
  final endpoint = init[2]! as String;
  final serverId = init[3]! as int;
  final sessionId = BigInt.parse(init[4]! as String).toSigned(64).toInt();
  final instanceId = BigInt.parse(init[5]! as String).toSigned(64).toInt();
  final primary = init[6]! as String;
  final fallback = init[7]! as String;
  final secondaryFallback = init[8]! as String;
  final useLiveDeltas = init[9]! as bool;
  final fontPixels = init[10]! as int;
  final cellWidth = init[11]! as int;
  final lineHeight = init[12]! as int;
  final interrupt = ffi.Pointer<ffi.Void>.fromAddress(init[13]! as int);
  final commands = ReceivePort();

  final dylib = _nativeHostLibrary();
  final create = dylib.lookupFunction<_CreateNative, _CreateDart>(
    'howl_native_host_create',
  );
  final createManaged = dylib
      .lookupFunction<_CreateManagedNative, _CreateManagedDart>(
        'howl_native_host_create_managed',
      );
  final destroy = dylib.lookupFunction<_DestroyNative, _DestroyDart>(
    'howl_native_host_destroy',
  );
  final maximumRows = dylib
      .lookupFunction<_PresentationBoundNative, _PresentationBoundDart>(
        'howl_native_host_maximum_rows',
      )();
  final maximumColumns = dylib
      .lookupFunction<_PresentationBoundNative, _PresentationBoundDart>(
        'howl_native_host_maximum_columns',
      )();
  if (maximumRows <= 0 ||
      maximumRows > 0xffff ||
      maximumColumns <= 0 ||
      maximumColumns > 0xffff) {
    ready.send('worker_geometry_bound');
    commands.close();
    return;
  }
  final outputMinimumBytes = dylib
      .lookupFunction<_OutputMinimumBytesNative, _OutputMinimumBytesDart>(
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
  final setLiveObservePipeline = dylib
      .lookupFunction<
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
  final secondaryFallbackPointer = secondaryFallbackBytes.isEmpty
      ? ffi.nullptr
      : copyString(secondaryFallback);
  final diagnosticPointer = calloc<ffi.Uint8>(_nativeCreateDiagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  final host = sessionId == 0
      ? create(
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
          interrupt,
          diagnosticPointer,
          _nativeCreateDiagnosticBytes,
          diagnosticLength,
        )
      : createManaged(
          endpointPointer,
          endpointBytes.length,
          serverId,
          sessionId,
          instanceId,
          primaryPointer,
          primaryBytes.length,
          fallbackPointer,
          fallbackBytes.length,
          secondaryFallbackPointer,
          secondaryFallbackBytes.length,
          fontPixels,
          cellWidth,
          lineHeight,
          interrupt,
          diagnosticPointer,
          _nativeCreateDiagnosticBytes,
          diagnosticLength,
        );
  calloc.free(endpointPointer);
  calloc.free(primaryPointer);
  calloc.free(fallbackPointer);
  if (secondaryFallbackPointer != ffi.nullptr) {
    calloc.free(secondaryFallbackPointer);
  }
  if (host == ffi.nullptr) {
    final failure = _nativeCreateFailure(
      diagnosticPointer,
      diagnosticLength.value,
    );
    calloc.free(diagnosticPointer);
    calloc.free(diagnosticLength);
    ready.send(<Object?>[
      failure.message.isEmpty
          ? 'worker_host_create'
          : 'worker_host_create:${failure.message}',
      failure.kind.index,
    ]);
    commands.close();
    return;
  }
  calloc.free(diagnosticPointer);
  calloc.free(diagnosticLength);

  if (useLiveDeltas && setLiveObservePipeline(host, 1) != 0) {
    destroy(host);
    ready.send('worker_live_observe_pipeline');
    commands.close();
    return;
  }

  final output = calloc<ffi.Uint8>(outputMinimumBytes);
  final outputLength = calloc<ffi.Size>();
  final residency = calloc<ffi.Uint8>(8 * _residencyRecordBytes);
  ready.send(<Object?>[commands.sendPort, maximumRows, maximumColumns]);

  int? closeId;
  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.isEmpty) continue;
      final kind = message[0];
      if (kind == 1) {
        if (message.length > 1 && message[1] is int) {
          closeId = message[1]! as int;
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
            final responseCode = switch (refillCode) {
              6 => 7,
              7 => 9,
              8 => 10,
              _ => 4,
            };
            responses.send(<Object?>[id, responseCode, null]);
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
  if (closeId != null) {
    responses.send(<Object?>[
      closeId,
      0,
      TransferableTypedData.fromList(<Uint8List>[Uint8List(0)]),
    ]);
  }
}

final class NativeHostControl {
  NativeHostControl._(this._commands, this._responses, this._interrupt) {
    _responses.listen(_onResponse);
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final NativeInterruptScope _interrupt;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextId = 1;
  bool _closed = false;
  Future<void>? _closeFuture;

  static Future<NativeHostControl> create({
    required HowlInstanceTarget target,
    required NativeInterruptScope interrupt,
  }) async {
    if (interrupt.canceled) {
      throw const NativeHostException(
        'control_canceled_before_spawn',
        kind: NativeFailureKind.canceled,
      );
    }
    final ready = ReceivePort();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      _nativeControlWorker,
      <Object?>[
        ready.sendPort,
        responses.sendPort,
        target.endpointText,
        target.nativeServerId,
        target.sessionId,
        target.instanceId,
        interrupt.address,
      ],
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
      throw _workerStartupFailure(first, 'control_worker_start');
    }
    return NativeHostControl._(first, responses, interrupt);
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

  Future<NativeInteractionState> interactionState() async {
    final response = await _request(<Object?>[
      _NativeControlOperation.interactionState,
    ]);
    if (response is! TransferableTypedData) {
      throw const NativeHostException('control_interaction_state_response');
    }
    return parseNativeInteractionState(response.materialize().asUint8List());
  }

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
    if (_pending.length >= 64) {
      throw const NativeHostException('control_queue_full');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(<Object?>[action[0], id, ...action.skip(1)]);
    return completer.future;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _interrupt.cancel();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(<Object?>[_NativeControlOperation.close, id]);
    try {
      // Close acknowledgement is emitted only after native Control destruction
      // and worker allocation cleanup, so every caller observes the same real
      // lifetime boundary before the shared Interrupt owner can destroy it.
      await completer.future;
    } finally {
      _responses.close();
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
      final kind = switch (code) {
        5 => NativeFailureKind.transport,
        6 => NativeFailureKind.canceled,
        7 => NativeFailureKind.stale,
        _ => NativeFailureKind.permanent,
      };
      completer.completeError(NativeHostException('control_$code', kind: kind));
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
  interactionState,
  textExtract,
  close,
}

typedef _ControlCreateNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ControlCreateDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);
typedef _ControlCreateManagedNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ControlCreateManagedDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
  int,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
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
typedef _ControlInteractionStateNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
typedef _ControlInteractionStateDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);
typedef _ControlTextExtractNative = ffi.Int32 Function(
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
typedef _ControlTextExtractDart = int Function(
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
  final serverId = init[3]! as int;
  final sessionId = BigInt.parse(init[4]! as String).toSigned(64).toInt();
  final instanceId = BigInt.parse(init[5]! as String).toSigned(64).toInt();
  final interrupt = ffi.Pointer<ffi.Void>.fromAddress(init[6]! as int);
  final commands = ReceivePort();
  final dylib = _nativeHostLibrary();
  final create = dylib.lookupFunction<_ControlCreateNative, _ControlCreateDart>(
    'howl_native_control_create',
  );
  final createManaged = dylib
      .lookupFunction<_ControlCreateManagedNative, _ControlCreateManagedDart>(
        'howl_native_control_create_managed',
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
  final interactionState = dylib
      .lookupFunction<
        _ControlInteractionStateNative,
        _ControlInteractionStateDart
      >('howl_native_control_interaction_state');
  final textExtract = dylib
      .lookupFunction<_ControlTextExtractNative, _ControlTextExtractDart>(
        'howl_native_control_text_extract',
      );

  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = calloc<ffi.Uint8>(endpointBytes.length);
  endpointPointer.asTypedList(endpointBytes.length).setAll(0, endpointBytes);
  final diagnosticPointer = calloc<ffi.Uint8>(_nativeCreateDiagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  final control = sessionId == 0
      ? create(
          endpointPointer,
          endpointBytes.length,
          interrupt,
          diagnosticPointer,
          _nativeCreateDiagnosticBytes,
          diagnosticLength,
        )
      : createManaged(
          endpointPointer,
          endpointBytes.length,
          serverId,
          sessionId,
          instanceId,
          interrupt,
          diagnosticPointer,
          _nativeCreateDiagnosticBytes,
          diagnosticLength,
        );
  calloc.free(endpointPointer);
  if (control == ffi.nullptr) {
    final failure = _nativeCreateFailure(
      diagnosticPointer,
      diagnosticLength.value,
    );
    calloc.free(diagnosticPointer);
    calloc.free(diagnosticLength);
    ready.send(<Object?>[
      failure.message.isEmpty
          ? 'control_host_create'
          : 'control_host_create:${failure.message}',
      failure.kind.index,
    ]);
    commands.close();
    return;
  }
  calloc.free(diagnosticPointer);
  calloc.free(diagnosticLength);
  final selectionOutput = calloc<ffi.Uint8>(nativeSelectionOutputBytes);
  final selectionLength = calloc<ffi.Size>();
  final interactionOutput = calloc<ffi.Uint8>(nativeInteractionStateBytes);
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

  int? closeId;
  try {
    await for (final message in commands) {
      if (message is! List<Object?> || message.length < 2) continue;
      final kind = message[0];
      final id = message[1];
      if (kind is! _NativeControlOperation || id is! int) continue;
      if (kind == _NativeControlOperation.close) {
        closeId = id;
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
        case _NativeControlOperation.interactionState:
          code = interactionState(
            control,
            interactionOutput,
            nativeInteractionStateBytes,
          );
          if (code == 0) {
            response = TransferableTypedData.fromList(<Uint8List>[
              Uint8List.fromList(
                interactionOutput.asTypedList(nativeInteractionStateBytes),
              ),
            ]);
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
    calloc.free(interactionOutput);
    commands.close();
  }
  if (closeId != null) responses.send(<Object?>[closeId, 0]);
}
