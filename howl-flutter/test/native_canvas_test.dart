import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/native_canvas.dart';
import 'package:howl_flutter/native_canvas_surface.dart';
import 'package:howl_flutter/native_host.dart';
import 'package:howl_flutter/terminal_presentation.dart';

Uint8List _oneFrameCanvas({int surfaceWidth = 10, int surfaceHeight = 20}) {
  const global = NativeCanvasFrame.globalHeaderBytes;
  const frame = NativeCanvasFrame.frameHeaderBytes;
  const resource = NativeCanvasFrame.resourceRecordBytes;
  const commands = 3 * NativeCanvasFrame.commandRecordBytes;
  const pixels = 1;
  final recordBytes = frame + resource + commands + pixels;
  final bytes = Uint8List(global + recordBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x43, 0x52, 0x31]);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, global, Endian.little);
  data.setUint32(8, 1, Endian.little);
  data.setUint32(12, 1, Endian.little);
  data.setUint16(16, surfaceWidth, Endian.little);
  data.setUint16(18, surfaceHeight, Endian.little);

  var at = global;
  data.setUint32(at, recordBytes, Endian.little);
  data.setUint32(at + 4, 1, Endian.little);
  data.setUint64(at + 8, 2, Endian.little);
  data.setUint32(at + 16, 1, Endian.little);
  data.setUint32(at + 20, 0, Endian.little);
  data.setUint32(at + 24, 3, Endian.little);
  data.setUint32(at + 28, pixels, Endian.little);
  data.setUint32(at + 32, resource, Endian.little);
  data.setUint32(at + 36, 0, Endian.little);
  data.setUint32(at + 40, commands, Endian.little);
  at += frame;

  data.setUint64(at, 1, Endian.little);
  data.setUint64(at + 8, 1, Endian.little);
  data.setUint64(at + 16, 1, Endian.little);
  data.setUint8(at + 24, 0);
  data.setUint16(at + 26, 1, Endian.little);
  data.setUint16(at + 28, 1, Endian.little);
  data.setUint32(at + 32, 1, Endian.little);
  data.setUint32(at + 36, 0, Endian.little);
  data.setUint32(at + 40, 1, Endian.little);
  at += resource;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  data.setUint8(at, 0);
  data.setUint8(at + 1, 0xff);
  data.setUint32(at + 4, 0xff090b0e, Endian.little);
  rect(at + 8, 0, 0, surfaceWidth, surfaceHeight);
  rect(at + 20, 0, 0, surfaceWidth, surfaceHeight);
  at += NativeCanvasFrame.commandRecordBytes;

  data.setUint8(at, 1);
  data.setUint8(at + 1, 0);
  data.setUint32(at + 4, 0xffffffff, Endian.little);
  rect(at + 8, 2, 3, 1, 1);
  rect(at + 20, 2, 3, 1, 1);
  data.setUint16(at + 32, 0, Endian.little);
  data.setUint16(at + 34, 0, Endian.little);
  data.setUint16(at + 36, 1, Endian.little);
  data.setUint16(at + 38, 1, Endian.little);
  at += NativeCanvasFrame.commandRecordBytes;

  data.setUint8(at, 0);
  data.setUint8(at + 1, 0xff);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 4, 5, 1, 1);
  rect(at + 20, 4, 5, 1, 1);
  at += NativeCanvasFrame.commandRecordBytes;
  bytes[at] = 0xff;
  return bytes;
}

Uint8List _scaledOneFrameCanvas(int scale) {
  final bytes = _oneFrameCanvas(
    surfaceWidth: 10 * scale,
    surfaceHeight: 20 * scale,
  );
  final data = ByteData.sublistView(bytes);
  var at =
      NativeCanvasFrame.globalHeaderBytes +
      NativeCanvasFrame.frameHeaderBytes +
      NativeCanvasFrame.resourceRecordBytes;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  at += NativeCanvasFrame.commandRecordBytes;
  rect(at + 8, 2 * scale, 3 * scale, scale, scale);
  rect(at + 20, 2 * scale, 3 * scale, scale, scale);
  at += NativeCanvasFrame.commandRecordBytes;
  rect(at + 8, 4 * scale, 5 * scale, scale, scale);
  rect(at + 20, 4 * scale, 5 * scale, scale, scale);
  return bytes;
}

Uint8List _batchedAlphaCanvas() {
  final bytes = _oneFrameCanvas();
  final data = ByteData.sublistView(bytes);
  var at =
      NativeCanvasFrame.globalHeaderBytes +
      NativeCanvasFrame.frameHeaderBytes +
      NativeCanvasFrame.resourceRecordBytes;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  for (var index = 0; index < 3; index++) {
    data.setUint8(at, 1);
    data.setUint8(at + 1, 0);
    data.setUint32(at + 4, 0xffffffff, Endian.little);
    rect(at + 8, index, 0, 1, 1);
    rect(at + 20, 0, 0, 10, 20);
    data.setUint16(at + 32, 0, Endian.little);
    data.setUint16(at + 34, 0, Endian.little);
    data.setUint16(at + 36, 1, Endian.little);
    data.setUint16(at + 38, 1, Endian.little);
    at += NativeCanvasFrame.commandRecordBytes;
  }
  return bytes;
}

Uint8List _coalescedSolidCanvas() {
  final bytes = _oneFrameCanvas();
  final data = ByteData.sublistView(bytes);
  var at =
      NativeCanvasFrame.globalHeaderBytes +
      NativeCanvasFrame.frameHeaderBytes +
      NativeCanvasFrame.resourceRecordBytes;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  at += NativeCanvasFrame.commandRecordBytes;
  data.setUint8(at, 0);
  data.setUint8(at + 1, 0xff);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 0, 0, 1, 1);
  at += NativeCanvasFrame.commandRecordBytes;
  data.setUint8(at, 0);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 1, 0, 1, 1);
  return bytes;
}

Uint8List _hostPacket({
  bool semanticTruncated = false,
  TerminalPresentation presentation = const TerminalPresentation(
    fontPixels: 16,
    cellWidth: 10,
    lineHeight: 20,
  ),
}) {
  final canvas = _oneFrameCanvas(
    surfaceWidth: presentation.cellWidth,
    surfaceHeight: presentation.lineHeight,
  );
  final semantics = Uint8List.fromList('visible terminal'.codeUnits);
  const selectionRows = <int>[1];
  final bytes = Uint8List(
    64 + canvas.length + selectionRows.length * 2 + semantics.length,
  );
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x4e, 0x48, 0x31]);
  data.setUint16(4, 3, Endian.little);
  data.setUint16(6, 64, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, 64, Endian.little);
  data.setUint32(16, canvas.length, Endian.little);
  data.setUint32(
    20,
    (1 << 5) | (semanticTruncated ? 1 << 6 : 0),
    Endian.little,
  );
  data.setUint64(24, 7, Endian.little);
  data.setUint64(32, 11, Endian.little);
  data.setUint32(40, 0, Endian.little);
  data.setUint32(44, 23, Endian.little);
  data.setUint32(48, 3, Endian.little);
  data.setUint16(52, 1, Endian.little);
  data.setUint16(54, 1, Endian.little);
  data.setUint16(56, 0, Endian.little);
  data.setUint16(58, 0, Endian.little);
  data.setUint32(60, semantics.length, Endian.little);
  bytes.setAll(64, canvas);
  var at = 64 + canvas.length;
  for (final row in selectionRows) {
    data.setUint16(at, row, Endian.little);
    at += 2;
  }
  bytes.setAll(at, semantics);
  return bytes;
}

Uint8List _imageRefillPacket() {
  const header = 64;
  const pixels = <int>[
    255,
    0,
    0,
    255,
    0,
    255,
    0,
    255,
    0,
    0,
    255,
    255,
    255,
    255,
    255,
    255,
  ];
  final bytes = Uint8List(header + pixels.length);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x49, 0x52, 0x31]);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, header, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, pixels.length, Endian.little);
  data.setUint64(16, 3, Endian.little);
  data.setUint64(24, 7, Endian.little);
  data.setUint64(32, 11, Endian.little);
  data.setUint32(40, 17, Endian.little);
  data.setUint8(44, 1);
  data.setUint16(46, 2, Endian.little);
  data.setUint16(48, 2, Endian.little);
  data.setUint32(52, 8, Endian.little);
  data.setUint64(56, 23, Endian.little);
  bytes.setAll(header, pixels);
  return bytes;
}

Uint8List _externalRgbaCanvas() {
  const global = NativeCanvasFrame.globalHeaderBytes;
  const frame = NativeCanvasFrame.frameHeaderBytes;
  const resource = NativeCanvasFrame.resourceRecordBytes;
  const command = NativeCanvasFrame.commandRecordBytes;
  const recordBytes = frame + resource + command;
  final bytes = Uint8List(global + recordBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x43, 0x52, 0x31]);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, global, Endian.little);
  data.setUint32(8, 1, Endian.little);
  data.setUint32(12, 1, Endian.little);
  data.setUint16(16, 20, Endian.little);
  data.setUint16(18, 20, Endian.little);

  var at = global;
  data.setUint32(at, recordBytes, Endian.little);
  data.setUint32(at + 4, 1, Endian.little);
  data.setUint64(at + 8, 5, Endian.little);
  data.setUint32(at + 16, 1, Endian.little);
  data.setUint32(at + 20, 0, Endian.little);
  data.setUint32(at + 24, 1, Endian.little);
  data.setUint32(at + 28, 0, Endian.little);
  data.setUint32(at + 32, resource, Endian.little);
  data.setUint32(at + 36, 0, Endian.little);
  data.setUint32(at + 40, command, Endian.little);
  at += frame;

  data.setUint64(at, 3, Endian.little);
  data.setUint64(at + 8, 7, Endian.little);
  data.setUint64(at + 16, 11, Endian.little);
  data.setUint8(at + 24, 1);
  data.setUint16(at + 26, 2, Endian.little);
  data.setUint16(at + 28, 2, Endian.little);
  at += resource;

  data.setUint8(at, 2);
  data.setUint8(at + 1, 0);
  data.setInt32(at + 8, 0, Endian.little);
  data.setInt32(at + 12, 0, Endian.little);
  data.setUint16(at + 16, 20, Endian.little);
  data.setUint16(at + 18, 20, Endian.little);
  data.setInt32(at + 20, 0, Endian.little);
  data.setInt32(at + 24, 0, Endian.little);
  data.setUint16(at + 28, 20, Endian.little);
  data.setUint16(at + 30, 20, Endian.little);
  data.setUint16(at + 32, 0, Endian.little);
  data.setUint16(at + 34, 0, Endian.little);
  data.setUint16(at + 36, 2, Endian.little);
  data.setUint16(at + 38, 2, Endian.little);
  return bytes;
}

void main() {
  test('interaction state parser exposes canonical mouse routing modes', () {
    final bytes = Uint8List.fromList(<int>[
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x00,
      0x00,
      0x1f,
      0xfd,
      0x04,
      0x03,
      0xff,
      0x7f,
      0x12,
      0x34,
      0x03,
      0x00,
    ]);
    final state = parseNativeInteractionState(bytes);
    expect(state.terminalRevision, 0x0102030405060708);
    expect(state.alternateScroll, isTrue);
    expect(state.mouseTracking, 4);
    expect(state.mouseTrackingEnabled, isTrue);
    expect(state.mouseProtocol, 3);
    expect(state.pointerMode, 3);

    final bad = Uint8List.fromList(bytes)..[19] = 1;
    expect(
      () => parseNativeInteractionState(bad),
      throwsA(isA<NativeHostException>()),
    );
  });

  test('alpha atlas applies the per-glyph foreground color', () async {
    final bytes = _oneFrameCanvas();
    final data = ByteData.sublistView(bytes);
    final alphaCommand =
        NativeCanvasFrame.globalHeaderBytes +
        NativeCanvasFrame.frameHeaderBytes +
        NativeCanvasFrame.resourceRecordBytes +
        NativeCanvasFrame.commandRecordBytes;
    // Canvas wire colors are little-endian RGBA bytes. Opaque red therefore
    // appears as 0xff0000ff when read as one u32.
    data.setUint32(alphaCommand + 4, 0xff0000ff, Endian.little);

    final update = await prepareNativeCanvasFrame(
      null,
      NativeCanvasFrame.parse(bytes),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    update.lease.plan.paint(canvas, update.lease.images);
    final image = await recorder.endRecording().toImage(10, 20);
    try {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(raw, isNotNull);
      final offset = (3 * 10 + 2) * 4;
      expect(raw!.buffer.asUint8List(raw.offsetInBytes + offset, 4), <int>[
        255,
        0,
        0,
        255,
      ]);
    } finally {
      image.dispose();
      disposeNativeCanvasLease(update.lease);
      for (final retired in update.retired) {
        retired.dispose();
      }
    }
  });

  test(
    'HiDPI Canvas maps dense native raster back to logical terminal cells',
    () async {
      final bytes = _scaledOneFrameCanvas(2);
      final data = ByteData.sublistView(bytes);
      final alphaCommand =
          NativeCanvasFrame.globalHeaderBytes +
          NativeCanvasFrame.frameHeaderBytes +
          NativeCanvasFrame.resourceRecordBytes +
          NativeCanvasFrame.commandRecordBytes;
      data.setUint32(alphaCommand + 4, 0xff0000ff, Endian.little);

      final update = await prepareNativeCanvasFrame(
        null,
        NativeCanvasFrame.parse(bytes),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      NativeCanvasPainter(
        lease: update.lease,
        logicalWidth: 10,
        logicalHeight: 20,
      ).paint(canvas, const ui.Size(10, 20));
      final image = await recorder.endRecording().toImage(10, 20);
      try {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(raw, isNotNull);
        final offset = (3 * 10 + 2) * 4;
        expect(raw!.buffer.asUint8List(raw.offsetInBytes + offset, 4), <int>[
          255,
          0,
          0,
          255,
        ]);
      } finally {
        image.dispose();
        disposeNativeCanvasLease(update.lease);
        for (final retired in update.retired) {
          retired.dispose();
        }
      }
    },
  );

  test('one-frame Canvas packet preserves resource and batch order', () {
    final frame = NativeCanvasFrame.parse(_oneFrameCanvas());
    expect(frame.surfaceWidth, 10);
    expect(frame.surfaceHeight, 20);
    expect(frame.commandCount, 3);
    expect(frame.resource(0).uploadLength, 1);
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 3);
  });

  test('consecutive alpha commands become one typed atlas batch', () {
    final frame = NativeCanvasFrame.parse(_batchedAlphaCanvas());
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 1);
  });

  test('adjacent same-color solids coalesce horizontally', () {
    final frame = NativeCanvasFrame.parse(_coalescedSolidCanvas());
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 2);
  });

  test('native host metadata wraps exactly one final Canvas frame', () {
    final packet = parseNativeHostPacket(
      _hostPacket(),
      TerminalZoomPreset.normal.presentation,
    );
    expect(packet.metadata.revision, 7);
    expect(packet.metadata.terminalRevision, 11);
    expect(packet.metadata.historyCount, 23);
    expect(packet.metadata.historyRowBase, 3);
    expect(packet.metadata.rows, 1);
    expect(packet.metadata.columns, 1);
    expect(packet.metadata.cursorVisible, isTrue);
    expect(packet.metadata.selectionRows, hasLength(1));
    expect(packet.metadata.selectionRows.single.contentEndExclusive, 1);
    expect(packet.metadata.selectionRows.single.wrapped, isFalse);
    expect(packet.canvas.commandCount, 3);
    expect(packet.semanticText, 'visible terminal');
    expect(packet.semanticTruncated, isFalse);
  });

  test('native host external refill becomes exact Canvas residency', () async {
    final upload = parseNativeHostImageRefill(_imageRefillPacket());
    expect(upload.resource.key, const NativeCanvasResourceKey(3, 7, 11));
    expect(upload.resource.format, 1);
    expect(upload.resource.width, 2);
    expect(upload.resource.height, 2);
    expect(upload.resource.stride, 8);
    expect(upload.pixels.length, 16);

    final preload = await prepareNativeCanvasExternalUpload(upload);
    final beforeFrame = encodeNativeHostResidency(
      null,
      preloaded: <NativeCanvasPreloadedResource>[preload],
    );
    final residency = ByteData.sublistView(beforeFrame);
    expect(beforeFrame.length, 32);
    expect(residency.getUint64(0, Endian.little), 3);
    expect(residency.getUint64(8, Endian.little), 7);
    expect(residency.getUint64(16, Endian.little), 11);
    expect(residency.getUint8(24), 1);
    expect(residency.getUint16(26, Endian.little), 2);
    expect(residency.getUint16(28, Endian.little), 2);

    final frame = NativeCanvasFrame.parse(_externalRgbaCanvas());
    final prepared = await prepareNativeCanvasFrame(
      null,
      frame,
      preloaded: <NativeCanvasPreloadedResource>[preload],
    );
    try {
      expect(prepared.lease.images.containsKey(upload.resource.key), isTrue);
      expect(prepared.lease.plan.segmentCountForTesting, 1);
      final afterFrame = encodeNativeHostResidency(prepared.lease);
      expect(afterFrame, beforeFrame);
    } finally {
      disposeNativeCanvasLease(prepared.lease);
      for (final image in prepared.retired) {
        image.dispose();
      }
    }
  });

  test(
    'candidate residency replaces an older logical Canvas generation',
    () async {
      final previousUpload = parseNativeHostImageRefill(_imageRefillPacket());
      final previousPreload = await prepareNativeCanvasExternalUpload(
        previousUpload,
      );
      final previous = await prepareNativeCanvasFrame(
        null,
        NativeCanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <NativeCanvasPreloadedResource>[previousPreload],
      );

      final newerPacket = _imageRefillPacket();
      final newerData = ByteData.sublistView(newerPacket);
      newerData.setUint64(32, 12, Endian.little);
      newerData.setUint64(56, 24, Endian.little);
      final newer = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(newerPacket),
      );
      try {
        final encoded = encodeNativeHostResidency(
          previous.lease,
          preloaded: <NativeCanvasPreloadedResource>[newer],
        );
        expect(encoded.length, 32);
        final data = ByteData.sublistView(encoded);
        expect(data.getUint64(0, Endian.little), 3);
        expect(data.getUint64(8, Endian.little), 7);
        expect(data.getUint64(16, Endian.little), 12);
      } finally {
        disposeNativeCanvasPreloadedResources(<NativeCanvasPreloadedResource>[
          newer,
        ]);
        disposeNativeCanvasLease(previous.lease);
        for (final image in previous.retired) {
          image.dispose();
        }
      }
    },
  );

  test(
    'abandoned Canvas candidate preserves previous lease ownership',
    () async {
      final previous = await prepareNativeCanvasFrame(
        null,
        NativeCanvasFrame.parse(_oneFrameCanvas()),
      );
      final previousImage = previous.lease.images.values.single;
      final preload = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(_imageRefillPacket()),
      );
      final candidate = await prepareNativeCanvasFrame(
        previous.lease,
        NativeCanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <NativeCanvasPreloadedResource>[preload],
      );
      try {
        expect(candidate.retired, contains(same(previousImage)));
        disposeNativeCanvasLeaseCandidate(candidate);
        expect(previousImage.width, 1);
        expect(previousImage.height, 1);
      } finally {
        disposeNativeCanvasLease(previous.lease);
      }
    },
  );

  test(
    'presentation restart retains previous external residency until unwind',
    () async {
      final preload = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(_imageRefillPacket()),
      );
      final previous = await prepareNativeCanvasFrame(
        null,
        NativeCanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <NativeCanvasPreloadedResource>[preload],
      );
      try {
        await expectLater(
          prepareNativeCanvasFrame(
            null,
            NativeCanvasFrame.parse(_externalRgbaCanvas()),
          ),
          throwsA(isA<StateError>()),
        );
        final inFlight = await prepareNativeCanvasFrame(
          previous.lease,
          NativeCanvasFrame.parse(_externalRgbaCanvas()),
        );
        expect(
          inFlight.lease.images.values.single,
          same(previous.lease.images.values.single),
        );
        disposeNativeCanvasLeaseCandidate(inFlight);
      } finally {
        disposeNativeCanvasLease(previous.lease);
        for (final image in previous.retired) {
          image.dispose();
        }
      }
    },
  );

  test('native host external refill rejects stale packet layout', () {
    final badStride = _imageRefillPacket();
    ByteData.sublistView(badStride).setUint32(52, 4, Endian.little);
    expect(
      () => parseNativeHostImageRefill(badStride),
      throwsA(isA<NativeHostException>()),
    );
    final badGeneration = _imageRefillPacket();
    ByteData.sublistView(badGeneration).setUint64(32, 0, Endian.little);
    expect(
      () => parseNativeHostImageRefill(badGeneration),
      throwsA(isA<NativeHostException>()),
    );
  });

  test(
    'native host exposes bounded semantic truncation without changing text',
    () {
      final packet = parseNativeHostPacket(
        _hostPacket(semanticTruncated: true),
        TerminalZoomPreset.normal.presentation,
      );
      expect(packet.semanticText, 'visible terminal');
      expect(packet.semanticTruncated, isTrue);
    },
  );

  test('sprite clipping maps destination clipping back into source space', () {
    final clipped = clipNativeCanvasSprite(
      const ui.Rect.fromLTWH(10, 10, 10, 10),
      const ui.Rect.fromLTWH(15, 12, 10, 5),
      const ui.Rect.fromLTWH(20, 30, 10, 10),
    );
    expect(clipped, isNotNull);
    expect(clipped!.destination, const ui.Rect.fromLTWH(15, 12, 5, 5));
    expect(clipped.source, const ui.Rect.fromLTWH(25, 32, 5, 5));
    final scaled = clipNativeCanvasSprite(
      const ui.Rect.fromLTWH(0, 0, 20, 10),
      const ui.Rect.fromLTWH(5, 2, 10, 5),
      const ui.Rect.fromLTWH(0, 0, 10, 10),
    );
    expect(scaled, isNotNull);
    expect(scaled!.destination, const ui.Rect.fromLTWH(5, 2, 10, 5));
    expect(scaled.source, const ui.Rect.fromLTWH(2.5, 2, 5, 5));
  });

  test('Canvas and native-host parsers reject corrupt identity/layout', () {
    final badCanvas = _oneFrameCanvas()..[0] = 0;
    expect(
      () => NativeCanvasFrame.parse(badCanvas),
      throwsA(isA<NativeCanvasException>()),
    );
    final badHost = _hostPacket()..[0] = 0;
    expect(
      () => parseNativeHostPacket(
        badHost,
        TerminalZoomPreset.normal.presentation,
      ),
      throwsA(isA<NativeHostException>()),
    );
    final badSemanticLayout = _hostPacket();
    ByteData.sublistView(badSemanticLayout).setUint32(60, 999, Endian.little);
    expect(
      () => parseNativeHostPacket(
        badSemanticLayout,
        TerminalZoomPreset.normal.presentation,
      ),
      throwsA(isA<NativeHostException>()),
    );
    final badUtf8 = _hostPacket()..[badHost.length - 1] = 0xff;
    expect(
      () => parseNativeHostPacket(
        badUtf8,
        TerminalZoomPreset.normal.presentation,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('native host validates the selected presentation lattice', () {
    final small = TerminalZoomPreset.small.presentation;
    final packet = parseNativeHostPacket(
      _hostPacket(presentation: small),
      small,
    );
    expect(packet.canvas.surfaceWidth, small.cellWidth);
    expect(packet.canvas.surfaceHeight, small.lineHeight);
    expect(
      () => parseNativeHostPacket(
        _hostPacket(presentation: small),
        TerminalZoomPreset.normal.presentation,
      ),
      throwsA(isA<NativeHostException>()),
    );
  });
}
