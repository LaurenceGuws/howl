import 'dart:typed_data';

final class NativeCanvasException implements Exception {
  const NativeCanvasException(this.code);
  final String code;

  @override
  String toString() => 'NativeCanvasException($code)';
}

final class NativeCanvasResourceKey {
  const NativeCanvasResourceKey(this.source, this.resource, this.generation);

  final int source;
  final int resource;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is NativeCanvasResourceKey &&
      source == other.source &&
      resource == other.resource &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(source, resource, generation);

  @override
  String toString() => '$source:$resource:$generation';
}

final class NativeCanvasResource {
  const NativeCanvasResource({
    required this.key,
    required this.format,
    required this.width,
    required this.height,
    required this.stride,
    required this.uploadOffset,
    required this.uploadLength,
  });

  final NativeCanvasResourceKey key;
  final int format;
  final int width;
  final int height;
  final int stride;
  final int uploadOffset;
  final int uploadLength;

  bool get uploaded => uploadLength != 0;
}

/// One copied, final native Canvas frame.
///
/// This is an app-private, version-locked packet. It is deliberately not a
/// public Howl ABI and exposes no terminal cells, styles, fonts, or cursor
/// policy to Flutter.
final class NativeCanvasFrame {
  NativeCanvasFrame._({
    required Uint8List bytes,
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.revision,
    required this.resourceCount,
    required this.removalCount,
    required this.commandCount,
    required this.pixelCount,
    required this._resourceOffset,
    required this._removalOffset,
    required this._commandOffset,
    required this._pixelOffset,
  }) : _bytes = bytes,
       _data = ByteData.sublistView(bytes);

  static const int globalHeaderBytes = 32;
  static const int frameHeaderBytes = 48;
  static const int resourceRecordBytes = 48;
  static const int removalRecordBytes = 24;
  static const int commandRecordBytes = 40;

  final Uint8List _bytes;
  final ByteData _data;
  final int surfaceWidth;
  final int surfaceHeight;
  final int revision;
  final int resourceCount;
  final int removalCount;
  final int commandCount;
  final int pixelCount;
  final int _resourceOffset;
  final int _removalOffset;
  final int _commandOffset;
  final int _pixelOffset;

  static NativeCanvasFrame parse(Uint8List bytes) {
    if (bytes.length < globalHeaderBytes + frameHeaderBytes) {
      throw const NativeCanvasException('frame_truncated');
    }
    final data = ByteData.sublistView(bytes);
    if (bytes[0] != 0x48 ||
        bytes[1] != 0x43 ||
        bytes[2] != 0x52 ||
        bytes[3] != 0x31) {
      throw const NativeCanvasException('magic');
    }
    if (data.getUint16(4, Endian.little) != 1 ||
        data.getUint16(6, Endian.little) != globalHeaderBytes ||
        data.getUint32(8, Endian.little) != 1 ||
        data.getUint32(12, Endian.little) != 1) {
      throw const NativeCanvasException('version');
    }
    final width = data.getUint16(16, Endian.little);
    final height = data.getUint16(18, Endian.little);
    if (width == 0 || height == 0) {
      throw const NativeCanvasException('surface');
    }

    const offset = globalHeaderBytes;
    final recordBytes = data.getUint32(offset, Endian.little);
    final flags = data.getUint32(offset + 4, Endian.little);
    final revision = data.getUint64(offset + 8, Endian.little);
    final resourceCount = data.getUint32(offset + 16, Endian.little);
    final removalCount = data.getUint32(offset + 20, Endian.little);
    final commandCount = data.getUint32(offset + 24, Endian.little);
    final pixelCount = data.getUint32(offset + 28, Endian.little);
    final resourceBytes = data.getUint32(offset + 32, Endian.little);
    final removalBytes = data.getUint32(offset + 36, Endian.little);
    final commandBytes = data.getUint32(offset + 40, Endian.little);
    if (recordBytes < frameHeaderBytes || flags != 1 || revision == 0) {
      throw const NativeCanvasException('frame_bounds');
    }
    if (resourceCount > 255 ||
        resourceBytes != resourceCount * resourceRecordBytes ||
        removalBytes != removalCount * removalRecordBytes ||
        commandBytes != commandCount * commandRecordBytes) {
      throw const NativeCanvasException('section_sizes');
    }
    final resourceOffset = offset + frameHeaderBytes;
    final removalOffset = resourceOffset + resourceBytes;
    final commandOffset = removalOffset + removalBytes;
    final pixelOffset = commandOffset + commandBytes;
    if (pixelOffset + pixelCount != offset + recordBytes ||
        offset + recordBytes != bytes.length) {
      throw const NativeCanvasException('section_layout');
    }

    final frame = NativeCanvasFrame._(
      bytes: bytes,
      surfaceWidth: width,
      surfaceHeight: height,
      revision: revision,
      resourceCount: resourceCount,
      removalCount: removalCount,
      commandCount: commandCount,
      pixelCount: pixelCount,
      resourceOffset: resourceOffset,
      removalOffset: removalOffset,
      commandOffset: commandOffset,
      pixelOffset: pixelOffset,
    );
    frame._validate();
    return frame;
  }

  NativeCanvasResource resource(int index) {
    if (index < 0 || index >= resourceCount) {
      throw const NativeCanvasException('resource_index');
    }
    final offset = _resourceOffset + index * resourceRecordBytes;
    return NativeCanvasResource(
      key: NativeCanvasResourceKey(
        _data.getUint64(offset, Endian.little),
        _data.getUint64(offset + 8, Endian.little),
        _data.getUint64(offset + 16, Endian.little),
      ),
      format: _data.getUint8(offset + 24),
      width: _data.getUint16(offset + 26, Endian.little),
      height: _data.getUint16(offset + 28, Endian.little),
      stride: _data.getUint32(offset + 32, Endian.little),
      uploadOffset: _data.getUint32(offset + 36, Endian.little),
      uploadLength: _data.getUint32(offset + 40, Endian.little),
    );
  }

  NativeCanvasResourceKey removal(int index) {
    if (index < 0 || index >= removalCount) {
      throw const NativeCanvasException('removal_index');
    }
    final offset = _removalOffset + index * removalRecordBytes;
    return NativeCanvasResourceKey(
      _data.getUint64(offset, Endian.little),
      _data.getUint64(offset + 8, Endian.little),
      _data.getUint64(offset + 16, Endian.little),
    );
  }

  int commandTag(int index) => _u8(index, 0);
  int commandResourceIndex(int index) => _u8(index, 1);
  int commandColorRgba(int index) => _u32(index, 4);
  int commandDestinationX(int index) => _i32(index, 8);
  int commandDestinationY(int index) => _i32(index, 12);
  int commandDestinationWidth(int index) => _u16(index, 16);
  int commandDestinationHeight(int index) => _u16(index, 18);
  int commandClipX(int index) => _i32(index, 20);
  int commandClipY(int index) => _i32(index, 24);
  int commandClipWidth(int index) => _u16(index, 28);
  int commandClipHeight(int index) => _u16(index, 30);
  int commandSourceX(int index) => _u16(index, 32);
  int commandSourceY(int index) => _u16(index, 34);
  int commandSourceWidth(int index) => _u16(index, 36);
  int commandSourceHeight(int index) => _u16(index, 38);

  Uint8List uploadBytes(NativeCanvasResource resource) {
    if (!resource.uploaded) return Uint8List(0);
    return Uint8List.sublistView(
      _bytes,
      _pixelOffset + resource.uploadOffset,
      _pixelOffset + resource.uploadOffset + resource.uploadLength,
    );
  }

  void _validate() {
    final resources = <NativeCanvasResource>[];
    for (var i = 0; i < resourceCount; i++) {
      final value = resource(i);
      if (value.key.source == 0 ||
          value.key.resource == 0 ||
          value.key.generation == 0 ||
          value.width == 0 ||
          value.height == 0 ||
          (value.format != 0 && value.format != 1)) {
        throw const NativeCanvasException('resource_bounds');
      }
      if (value.uploaded) {
        if (value.stride == 0 ||
            value.uploadOffset + value.uploadLength > pixelCount) {
          throw const NativeCanvasException('resource_upload');
        }
      } else if (value.stride != 0 ||
          value.uploadOffset != 0 ||
          value.uploadLength != 0) {
        throw const NativeCanvasException('resource_sparse');
      }
      resources.add(value);
    }
    for (var i = 0; i < removalCount; i++) {
      final key = removal(i);
      if (key.source == 0 || key.resource == 0 || key.generation == 0) {
        throw const NativeCanvasException('removal_identity');
      }
    }
    for (var i = 0; i < commandCount; i++) {
      final tag = commandTag(i);
      final resourceIndex = commandResourceIndex(i);
      if (tag > 2) throw const NativeCanvasException('command_tag');
      if (commandDestinationWidth(i) == 0 || commandDestinationHeight(i) == 0) {
        throw const NativeCanvasException('draw_geometry');
      }
      if (tag == 0) {
        if (resourceIndex != 0xff) {
          throw const NativeCanvasException('solid_command');
        }
        continue;
      }
      if (resourceIndex >= resources.length ||
          commandClipWidth(i) == 0 ||
          commandClipHeight(i) == 0 ||
          commandSourceWidth(i) == 0 ||
          commandSourceHeight(i) == 0) {
        throw const NativeCanvasException('draw_geometry');
      }
      final resource = resources[resourceIndex];
      if (commandSourceX(i) + commandSourceWidth(i) > resource.width ||
          commandSourceY(i) + commandSourceHeight(i) > resource.height) {
        throw const NativeCanvasException('source_bounds');
      }
    }
  }

  int _commandOffsetFor(int index) {
    if (index < 0 || index >= commandCount) {
      throw const NativeCanvasException('command_index');
    }
    return _commandOffset + index * commandRecordBytes;
  }

  int _u8(int index, int relative) =>
      _data.getUint8(_commandOffsetFor(index) + relative);
  int _u16(int index, int relative) =>
      _data.getUint16(_commandOffsetFor(index) + relative, Endian.little);
  int _u32(int index, int relative) =>
      _data.getUint32(_commandOffsetFor(index) + relative, Endian.little);
  int _i32(int index, int relative) =>
      _data.getInt32(_commandOffsetFor(index) + relative, Endian.little);
}
