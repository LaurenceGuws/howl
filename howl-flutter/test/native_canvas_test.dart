import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/native_canvas.dart';
import 'package:howl_flutter/native_canvas_surface.dart';
import 'package:howl_flutter/native_host.dart';

Uint8List _oneFrameCanvas() {
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
  data.setUint16(16, 10, Endian.little);
  data.setUint16(18, 20, Endian.little);

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
  rect(at + 8, 0, 0, 10, 20);
  rect(at + 20, 0, 0, 10, 20);
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

Uint8List _hostPacket() {
  final canvas = _oneFrameCanvas();
  final bytes = Uint8List(64 + canvas.length);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, const <int>[0x48, 0x4e, 0x48, 0x31]);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, 64, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, 64, Endian.little);
  data.setUint32(16, canvas.length, Endian.little);
  data.setUint32(20, 1 << 5, Endian.little);
  data.setUint64(24, 7, Endian.little);
  data.setUint64(32, 11, Endian.little);
  data.setUint32(40, 0, Endian.little);
  data.setUint32(44, 23, Endian.little);
  data.setUint32(48, 3, Endian.little);
  data.setUint16(52, 1, Endian.little);
  data.setUint16(54, 1, Endian.little);
  data.setUint16(56, 0, Endian.little);
  data.setUint16(58, 0, Endian.little);
  bytes.setAll(64, canvas);
  return bytes;
}

void main() {
  test('one-frame Canvas packet preserves resource and batch order', () {
    final frame = NativeCanvasFrame.parse(_oneFrameCanvas());
    expect(frame.surfaceWidth, 10);
    expect(frame.surfaceHeight, 20);
    expect(frame.commandCount, 3);
    expect(frame.resource(0).uploadLength, 1);
    final plan = buildNativeCanvasPlan(frame);
    expect(plan.segmentCountForTesting, 3);
  });

  test('native host metadata wraps exactly one final Canvas frame', () {
    final packet = parseNativeHostPacket(_hostPacket());
    expect(packet.metadata.revision, 7);
    expect(packet.metadata.terminalRevision, 11);
    expect(packet.metadata.historyCount, 23);
    expect(packet.metadata.historyRowBase, 3);
    expect(packet.metadata.rows, 1);
    expect(packet.metadata.columns, 1);
    expect(packet.metadata.cursorVisible, isTrue);
    expect(packet.canvas.commandCount, 3);
  });

  test('sprite clipping crops source and destination identically', () {
    final clipped = clipNativeCanvasSprite(
      const ui.Rect.fromLTWH(10, 10, 10, 10),
      const ui.Rect.fromLTWH(15, 12, 10, 5),
      const ui.Rect.fromLTWH(20, 30, 10, 10),
    );
    expect(clipped, isNotNull);
    expect(clipped!.destination, const ui.Rect.fromLTWH(15, 12, 5, 5));
    expect(clipped.source, const ui.Rect.fromLTWH(25, 32, 5, 5));
    expect(
      () => clipNativeCanvasSprite(
        const ui.Rect.fromLTWH(0, 0, 20, 10),
        const ui.Rect.fromLTWH(0, 0, 20, 10),
        const ui.Rect.fromLTWH(0, 0, 10, 10),
      ),
      throwsA(isA<NativeCanvasException>()),
    );
  });

  test('Canvas and native-host parsers reject corrupt identity/layout', () {
    final badCanvas = _oneFrameCanvas()..[0] = 0;
    expect(
      () => NativeCanvasFrame.parse(badCanvas),
      throwsA(isA<NativeCanvasException>()),
    );
    final badHost = _hostPacket()..[0] = 0;
    expect(
      () => parseNativeHostPacket(badHost),
      throwsA(isA<NativeHostException>()),
    );
  });
}
