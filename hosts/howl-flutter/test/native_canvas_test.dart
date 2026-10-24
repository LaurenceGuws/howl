import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/canvas/canvas.dart';
import 'package:howl_flutter/canvas/surface.dart';
import 'package:howl_flutter/delete/native_host.dart';
import 'package:howl_flutter/term/presentation.dart';

Uint8List _oneFrameCanvas({int surfaceWidth = 10, int surfaceHeight = 20}) {
  const global = CanvasFrame.globalHeaderBytes;
  const frame = CanvasFrame.frameHeaderBytes;
  const resource = CanvasFrame.resourceRecordBytes;
  const commands = 3 * CanvasFrame.commandRecordBytes;
  const pixels = 1;
  final recordBytes = frame + resource + commands + pixels;
  final bytes = Uint8List(global + recordBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x43, 0x52, 0x31]);
  data.setUint16(4, 2, Endian.little);
  data.setUint16(6, global, Endian.little);
  data.setUint16(8, surfaceWidth, Endian.little);
  data.setUint16(10, surfaceHeight, Endian.little);

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
  data.setUint8(at + 16, 0);
  data.setUint16(at + 18, 1, Endian.little);
  data.setUint16(at + 20, 1, Endian.little);
  data.setUint32(at + 24, 1, Endian.little);
  data.setUint32(at + 28, 0, Endian.little);
  data.setUint32(at + 32, 1, Endian.little);
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
  at += CanvasFrame.commandRecordBytes;

  data.setUint8(at, 1);
  data.setUint8(at + 1, 0);
  data.setUint32(at + 4, 0xffffffff, Endian.little);
  rect(at + 8, 2, 3, 1, 1);
  rect(at + 20, 2, 3, 1, 1);
  data.setUint16(at + 32, 0, Endian.little);
  data.setUint16(at + 34, 0, Endian.little);
  data.setUint16(at + 36, 1, Endian.little);
  data.setUint16(at + 38, 1, Endian.little);
  at += CanvasFrame.commandRecordBytes;

  data.setUint8(at, 0);
  data.setUint8(at + 1, 0xff);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 4, 5, 1, 1);
  rect(at + 20, 4, 5, 1, 1);
  at += CanvasFrame.commandRecordBytes;
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
      CanvasFrame.globalHeaderBytes +
      CanvasFrame.frameHeaderBytes +
      CanvasFrame.resourceRecordBytes;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  at += CanvasFrame.commandRecordBytes;
  rect(at + 8, 2 * scale, 3 * scale, scale, scale);
  rect(at + 20, 2 * scale, 3 * scale, scale, scale);
  at += CanvasFrame.commandRecordBytes;
  rect(at + 8, 4 * scale, 5 * scale, scale, scale);
  rect(at + 20, 4 * scale, 5 * scale, scale, scale);
  return bytes;
}

Uint8List _batchedAlphaCanvas() {
  final bytes = _oneFrameCanvas();
  final data = ByteData.sublistView(bytes);
  var at =
      CanvasFrame.globalHeaderBytes +
      CanvasFrame.frameHeaderBytes +
      CanvasFrame.resourceRecordBytes;

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
    at += CanvasFrame.commandRecordBytes;
  }
  return bytes;
}

Uint8List _coalescedSolidCanvas() {
  final bytes = _oneFrameCanvas();
  final data = ByteData.sublistView(bytes);
  var at =
      CanvasFrame.globalHeaderBytes +
      CanvasFrame.frameHeaderBytes +
      CanvasFrame.resourceRecordBytes;

  void rect(int offset, int x, int y, int width, int height) {
    data.setInt32(offset, x, Endian.little);
    data.setInt32(offset + 4, y, Endian.little);
    data.setUint16(offset + 8, width, Endian.little);
    data.setUint16(offset + 10, height, Endian.little);
  }

  at += CanvasFrame.commandRecordBytes;
  data.setUint8(at, 0);
  data.setUint8(at + 1, 0xff);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 0, 0, 1, 1);
  at += CanvasFrame.commandRecordBytes;
  data.setUint8(at, 0);
  data.setUint32(at + 4, 0xffff0000, Endian.little);
  rect(at + 8, 1, 0, 1, 1);
  return bytes;
}

Uint8List _hostPacket({
  bool semanticTruncated = false,
  String? title,
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
  final titleBytes = title == null
      ? Uint8List(0)
      : Uint8List.fromList(utf8.encode(title));
  const selectionRows = <int>[1];
  final bytes = Uint8List(
    68 +
        canvas.length +
        selectionRows.length * 2 +
        semantics.length +
        titleBytes.length,
  );
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x4e, 0x48, 0x31]);
  data.setUint16(4, 4, Endian.little);
  data.setUint16(6, 68, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, 68, Endian.little);
  data.setUint32(16, canvas.length, Endian.little);
  data.setUint32(
    20,
    (1 << 5) | (semanticTruncated ? 1 << 6 : 0) | (title != null ? 1 << 7 : 0),
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
  data.setUint32(64, titleBytes.length, Endian.little);
  bytes.setAll(68, canvas);
  var at = 68 + canvas.length;
  for (final row in selectionRows) {
    data.setUint16(at, row, Endian.little);
    at += 2;
  }
  bytes.setAll(at, semantics);
  at += semantics.length;
  bytes.setAll(at, titleBytes);
  return bytes;
}

Uint8List _imageRefillPacket({
  List<int> pixels = const <int>[
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
  ],
}) {
  const header = 56;
  assert(pixels.length == 16);
  final bytes = Uint8List(header + pixels.length);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x49, 0x52, 0x31]);
  data.setUint16(4, 2, Endian.little);
  data.setUint16(6, header, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, pixels.length, Endian.little);
  data.setUint64(16, 7, Endian.little);
  data.setUint64(24, 11, Endian.little);
  data.setUint32(32, 17, Endian.little);
  data.setUint8(36, 1);
  data.setUint16(38, 2, Endian.little);
  data.setUint16(40, 2, Endian.little);
  data.setUint32(44, 8, Endian.little);
  data.setUint64(48, 23, Endian.little);
  bytes.setAll(header, pixels);
  return bytes;
}

Uint8List _externalRgbaCanvas() {
  const global = CanvasFrame.globalHeaderBytes;
  const frame = CanvasFrame.frameHeaderBytes;
  const resource = CanvasFrame.resourceRecordBytes;
  const command = CanvasFrame.commandRecordBytes;
  const recordBytes = frame + resource + command;
  final bytes = Uint8List(global + recordBytes);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x43, 0x52, 0x31]);
  data.setUint16(4, 2, Endian.little);
  data.setUint16(6, global, Endian.little);
  data.setUint16(8, 20, Endian.little);
  data.setUint16(10, 20, Endian.little);

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

  data.setUint64(at, 7, Endian.little);
  data.setUint64(at + 8, 11, Endian.little);
  data.setUint8(at + 16, 1);
  data.setUint16(at + 18, 2, Endian.little);
  data.setUint16(at + 20, 2, Endian.little);
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
  test(
    'replacement Canvas 1/gen1 cannot inherit old glyph residency',
    () async {
      final oldBytes = _oneFrameCanvas()..last = 0x40;
      final newBytes = _oneFrameCanvas()..last = 0xc0;
      final previous = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(oldBytes),
      );
      // Same logical namespace counters and extents, different glyph coverage.
      final oldResidency = encodeNativeHostResidency(previous.lease);
      expect(oldResidency, isNotEmpty);
      final replacementResidency = encodeNativeHostResidency(null);
      expect(replacementResidency, isEmpty);
      final replacement = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(newBytes),
      );
      try {
        expect(
          replacement.lease.images.keys.single,
          previous.lease.images.keys.single,
        );
        expect(replacement.introduced.length, 1);
        expect(
          replacement.lease.images.values.single,
          isNot(same(previous.lease.images.values.single)),
        );
        final oldPixels = await previous.lease.images.values.single
            .toByteData();
        final newPixels = await replacement.lease.images.values.single
            .toByteData();
        expect(oldPixels!.getUint8(3), 0x40);
        expect(newPixels!.getUint8(3), 0xc0);
      } finally {
        disposeNativeCanvasLease(previous.lease);
        disposeNativeCanvasLease(replacement.lease);
      }
    },
  );

  for (final throws in [false, true]) {
    test(
      'delayed candidate ${throws ? 'exception' : 'route abandonment'} releases introduced images only',
      () async {
        final previous = await prepareNativeCanvasFrame(
          null,
          CanvasFrame.parse(_oneFrameCanvas()),
        );
        final candidate = await prepareNativeCanvasFrame(
          previous.lease,
          CanvasFrame.parse(_oneFrameCanvas()),
        );
        final gate = Completer<CanvasLeaseUpdate>();
        var current = true;
        var disposals = 0;
        final introduced = candidate.introduced.single;
        final previousImage = previous.lease.images.values.single;
        final onDispose = ui.Image.onDispose;
        ui.Image.onDispose = (image) {
          if (identical(image, introduced)) disposals++;
          onDispose?.call(image);
        };
        try {
          final pending = currentNativeCanvasCandidate(gate.future, () {
            if (throws) throw StateError('context validation failure');
            return current;
          });
          final check = throws
              ? expectLater(pending, throwsStateError)
              : expectLater(pending, completion(isNull));
          current = false; // leave route while decoding/preparation is paused
          gate.complete(candidate);
          await check;
          expect(disposals, 1);
          expect(previousImage.debugDisposed, isFalse);
          expect(introduced.debugDisposed, isTrue);
        } finally {
          ui.Image.onDispose = onDispose;
          disposeNativeCanvasLease(previous.lease);
        }
      },
    );
  }

  test('interaction state parser exposes canonical mouse routing modes', () {
    final bytes = Uint8List(nativeInteractionStateBytes);
    final data = ByteData.sublistView(bytes);
    data.setUint64(0, 0x0102030405060708, Endian.host);
    data.setUint32(8, 3, Endian.host);
    data.setUint8(12, 4);
    data.setUint8(13, 3);
    data.setUint8(14, 3);
    final state = parseNativeInteractionState(bytes);
    expect(state.terminalRevision, 0x0102030405060708);
    expect(state.alternateScroll, isTrue);
    expect(state.mouseTracking, 4);
    expect(state.mouseTrackingEnabled, isTrue);
    expect(state.mouseProtocol, 3);
    expect(state.pointerMode, 3);

    final bad = Uint8List.fromList(bytes)..[15] = 1;
    expect(
      () => parseNativeInteractionState(bad),
      throwsA(isA<NativeHostException>()),
    );
  });

  test('alpha atlas applies the per-glyph foreground color', () async {
    final bytes = _oneFrameCanvas();
    final data = ByteData.sublistView(bytes);
    final alphaCommand =
        CanvasFrame.globalHeaderBytes +
        CanvasFrame.frameHeaderBytes +
        CanvasFrame.resourceRecordBytes +
        CanvasFrame.commandRecordBytes;
    // Canvas wire colors are little-endian RGBA bytes. Opaque red therefore
    // appears as 0xff0000ff when read as one u32.
    data.setUint32(alphaCommand + 4, 0xff0000ff, Endian.little);

    final update = await prepareNativeCanvasFrame(
      null,
      CanvasFrame.parse(bytes),
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
          CanvasFrame.globalHeaderBytes +
          CanvasFrame.frameHeaderBytes +
          CanvasFrame.resourceRecordBytes +
          CanvasFrame.commandRecordBytes;
      data.setUint32(alphaCommand + 4, 0xff0000ff, Endian.little);

      final update = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(bytes),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      CanvasSurface(
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
    final frame = CanvasFrame.parse(_oneFrameCanvas());
    expect(frame.surfaceWidth, 10);
    expect(frame.surfaceHeight, 20);
    expect(frame.commandCount, 3);
    expect(frame.resource(0).uploadLength, 1);
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 3);
  });

  test('consecutive alpha commands become one typed atlas batch', () {
    final frame = CanvasFrame.parse(_batchedAlphaCanvas());
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 1);
  });

  test('adjacent same-color solids coalesce horizontally', () {
    final frame = CanvasFrame.parse(_coalescedSolidCanvas());
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
    expect(packet.title, isNull);
  });

  test('native host carries Unicode terminal title independently of text', () {
    final packet = parseNativeHostPacket(
      _hostPacket(title: 'rain 🌧'),
      TerminalZoomPreset.normal.presentation,
    );
    expect(packet.title, 'rain 🌧');
    expect(packet.semanticText, 'visible terminal');
    expect(
      parseNativeHostPacket(
        _hostPacket(title: ''),
        TerminalZoomPreset.normal.presentation,
      ).title,
      '',
    );
    final badLength = _hostPacket(title: 'rain');
    ByteData.sublistView(badLength).setUint32(64, 1025, Endian.little);
    expect(
      () => parseNativeHostPacket(
        badLength,
        TerminalZoomPreset.normal.presentation,
      ),
      throwsA(isA<NativeHostException>()),
    );
  });

  test('native host external refill becomes exact Canvas residency', () async {
    final upload = parseNativeHostImageRefill(_imageRefillPacket());
    expect(upload.resource.key, const CanvasResourceKey(7, 11));
    expect(upload.resource.format, 1);
    expect(upload.resource.width, 2);
    expect(upload.resource.height, 2);
    expect(upload.resource.stride, 8);
    expect(upload.pixels.length, 16);

    final preload = await prepareNativeCanvasExternalUpload(upload);
    final beforeFrame = encodeNativeHostResidency(
      null,
      preloaded: <CanvasPreloadedResource>[preload],
    );
    final residency = ByteData.sublistView(beforeFrame);
    expect(beforeFrame.length, 24);
    expect(residency.getUint64(0, Endian.little), 7);
    expect(residency.getUint64(8, Endian.little), 11);
    expect(residency.getUint8(16), 1);
    expect(residency.getUint16(18, Endian.little), 2);
    expect(residency.getUint16(20, Endian.little), 2);

    final frame = CanvasFrame.parse(_externalRgbaCanvas());
    final prepared = await prepareNativeCanvasFrame(
      null,
      frame,
      preloaded: <CanvasPreloadedResource>[preload],
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
    'external sRGB images round-trip through linear terminal composition',
    () async {
      final gray = List<int>.filled(4 * 4, 32)
        ..setAll(3, const <int>[255])
        ..setAll(7, const <int>[255])
        ..setAll(11, const <int>[255])
        ..setAll(15, const <int>[255]);
      final preload = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(_imageRefillPacket(pixels: gray)),
      );
      final prepared = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <CanvasPreloadedResource>[preload],
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      CanvasSurface(
        lease: prepared.lease,
        logicalWidth: 20,
        logicalHeight: 20,
      ).paint(canvas, const ui.Size(20, 20));
      final image = await recorder.endRecording().toImage(20, 20);
      try {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(raw, isNotNull);
        final pixel = raw!.buffer.asUint8List(
          raw.offsetInBytes + (10 * 20 + 10) * 4,
          4,
        );
        expect(pixel[0], inInclusiveRange(30, 34));
        expect(pixel[1], inInclusiveRange(30, 34));
        expect(pixel[2], inInclusiveRange(30, 34));
        expect(pixel[3], 255);
      } finally {
        image.dispose();
        disposeNativeCanvasLease(prepared.lease);
        for (final retired in prepared.retired) {
          retired.dispose();
        }
      }
    },
  );

  test(
    'candidate residency replaces an older logical Canvas generation',
    () async {
      final previousUpload = parseNativeHostImageRefill(_imageRefillPacket());
      final previousPreload = await prepareNativeCanvasExternalUpload(
        previousUpload,
      );
      final previous = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <CanvasPreloadedResource>[previousPreload],
      );

      final newerPacket = _imageRefillPacket();
      final newerData = ByteData.sublistView(newerPacket);
      newerData.setUint64(24, 12, Endian.little);
      newerData.setUint64(48, 24, Endian.little);
      final newer = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(newerPacket),
      );
      try {
        final encoded = encodeNativeHostResidency(
          previous.lease,
          preloaded: <CanvasPreloadedResource>[newer],
        );
        expect(encoded.length, 24);
        final data = ByteData.sublistView(encoded);
        expect(data.getUint64(0, Endian.little), 7);
        expect(data.getUint64(8, Endian.little), 12);
      } finally {
        disposeNativeCanvasPreloadedResources(<CanvasPreloadedResource>[newer]);
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
        CanvasFrame.parse(_oneFrameCanvas()),
      );
      final previousImage = previous.lease.images.values.single;
      final preload = await prepareNativeCanvasExternalUpload(
        parseNativeHostImageRefill(_imageRefillPacket()),
      );
      final candidate = await prepareNativeCanvasFrame(
        previous.lease,
        CanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <CanvasPreloadedResource>[preload],
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
        CanvasFrame.parse(_externalRgbaCanvas()),
        preloaded: <CanvasPreloadedResource>[preload],
      );
      try {
        await expectLater(
          prepareNativeCanvasFrame(
            null,
            CanvasFrame.parse(_externalRgbaCanvas()),
          ),
          throwsA(isA<StateError>()),
        );
        final inFlight = await prepareNativeCanvasFrame(
          previous.lease,
          CanvasFrame.parse(_externalRgbaCanvas()),
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
    ByteData.sublistView(badStride).setUint32(44, 4, Endian.little);
    expect(
      () => parseNativeHostImageRefill(badStride),
      throwsA(isA<NativeHostException>()),
    );
    final badGeneration = _imageRefillPacket();
    ByteData.sublistView(badGeneration).setUint64(24, 0, Endian.little);
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
    expect(() => CanvasFrame.parse(badCanvas), throwsA(isA<CanvasException>()));
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

  test(
    'listenable painter invalidates paint without replacing its delegate',
    () async {
      final firstBytes = _oneFrameCanvas();
      final secondBytes = _oneFrameCanvas();
      ByteData.sublistView(secondBytes)
          .setUint64(CanvasFrame.globalHeaderBytes + 8, 3, Endian.little);
      final first = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(firstBytes),
      );
      final second = await prepareNativeCanvasFrame(
        null,
        CanvasFrame.parse(secondBytes),
      );
      final lease = ValueNotifier<CanvasLease?>(first.lease);
      final painter = CanvasSurface.listenable(
        lease: lease,
        logicalWidth: 10,
        logicalHeight: 20,
      );
      var notifications = 0;
      void listener() => notifications += 1;
      painter.addListener(listener);
      try {
        lease.value = second.lease;
        expect(notifications, 1);
        expect(painter.shouldRepaint(painter), isFalse);
      } finally {
        painter.removeListener(listener);
        lease.dispose();
        disposeNativeCanvasLease(first.lease);
        disposeNativeCanvasLease(second.lease);
      }
    },
  );
}
