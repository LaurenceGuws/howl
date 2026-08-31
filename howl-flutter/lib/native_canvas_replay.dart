import 'dart:typed_data';

final class CanvasReplayException implements Exception {
  const CanvasReplayException(this.code);
  final String code;

  @override
  String toString() => 'CanvasReplayException($code)';
}

final class CanvasResourceKey {
  const CanvasResourceKey(this.source, this.resource, this.generation);

  final int source;
  final int resource;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is CanvasResourceKey &&
      source == other.source &&
      resource == other.resource &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(source, resource, generation);

  @override
  String toString() => '$source:$resource:$generation';
}

final class CanvasReplayResource {
  const CanvasReplayResource({
    required this.key,
    required this.format,
    required this.width,
    required this.height,
    required this.stride,
    required this.uploadOffset,
    required this.uploadLength,
  });

  final CanvasResourceKey key;
  final int format;
  final int width;
  final int height;
  final int stride;
  final int uploadOffset;
  final int uploadLength;

  bool get uploaded => uploadLength != 0;
}

final class _FrameIndex {
  const _FrameIndex({
    required this.offset,
    required this.recordBytes,
    required this.flags,
    required this.revision,
    required this.resourceCount,
    required this.removalCount,
    required this.commandCount,
    required this.pixelCount,
    required this.resourceOffset,
    required this.removalOffset,
    required this.commandOffset,
    required this.pixelOffset,
  });

  final int offset;
  final int recordBytes;
  final int flags;
  final int revision;
  final int resourceCount;
  final int removalCount;
  final int commandCount;
  final int pixelCount;
  final int resourceOffset;
  final int removalOffset;
  final int commandOffset;
  final int pixelOffset;
}

final class CanvasReplayCorpus {
  CanvasReplayCorpus._({
    required Uint8List bytes,
    required this.surfaceWidth,
    required this.surfaceHeight,
    required this.qualityFrameCount,
    required List<_FrameIndex> frames,
  }) : _bytes = bytes,
       _data = ByteData.sublistView(bytes),
       _frames = List.unmodifiable(frames);

  static const int globalHeaderBytes = 32;
  static const int frameHeaderBytes = 48;
  static const int resourceRecordBytes = 48;
  static const int removalRecordBytes = 24;
  static const int commandRecordBytes = 40;

  final Uint8List _bytes;
  final ByteData _data;
  final int surfaceWidth;
  final int surfaceHeight;
  final int qualityFrameCount;
  final List<_FrameIndex> _frames;

  int get frameCount => _frames.length;
  int get byteLength => _bytes.length;

  CanvasReplayFrame frame(int index) {
    if (index < 0 || index >= _frames.length) {
      throw const CanvasReplayException('frame_index');
    }
    return CanvasReplayFrame._(this, _frames[index], index);
  }

  static CanvasReplayCorpus parse(Uint8List bytes) {
    if (bytes.length < globalHeaderBytes) {
      throw const CanvasReplayException('global_truncated');
    }
    final data = ByteData.sublistView(bytes);
    if (bytes[0] != 0x48 ||
        bytes[1] != 0x43 ||
        bytes[2] != 0x52 ||
        bytes[3] != 0x31) {
      throw const CanvasReplayException('magic');
    }
    final version = data.getUint16(4, Endian.little);
    final headerBytes = data.getUint16(6, Endian.little);
    final frameCount = data.getUint32(8, Endian.little);
    final qualityFrames = data.getUint32(12, Endian.little);
    final width = data.getUint16(16, Endian.little);
    final height = data.getUint16(18, Endian.little);
    if (version != 1 || headerBytes != globalHeaderBytes) {
      throw const CanvasReplayException('version');
    }
    if (frameCount == 0 ||
        qualityFrames > frameCount ||
        width == 0 ||
        height == 0) {
      throw const CanvasReplayException('global_bounds');
    }

    var offset = headerBytes;
    final frames = <_FrameIndex>[];
    for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
      _require(bytes.length, offset, frameHeaderBytes, 'frame_header');
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
      if (recordBytes < frameHeaderBytes || revision == 0) {
        throw const CanvasReplayException('frame_bounds');
      }
      if (flags != (frameIndex == 0 ? 1 : 2)) {
        throw const CanvasReplayException('frame_phase');
      }
      if (resourceCount > 255 ||
          resourceBytes != resourceCount * resourceRecordBytes ||
          removalBytes != removalCount * removalRecordBytes ||
          commandBytes != commandCount * commandRecordBytes) {
        throw const CanvasReplayException('section_sizes');
      }
      final resourceOffset = offset + frameHeaderBytes;
      final removalOffset = resourceOffset + resourceBytes;
      final commandOffset = removalOffset + removalBytes;
      final pixelOffset = commandOffset + commandBytes;
      if (pixelOffset + pixelCount != offset + recordBytes) {
        throw const CanvasReplayException('section_layout');
      }
      _require(bytes.length, offset, recordBytes, 'frame_truncated');
      final entry = _FrameIndex(
        offset: offset,
        recordBytes: recordBytes,
        flags: flags,
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
      _validateFrame(data, bytes.length, entry);
      frames.add(entry);
      offset += recordBytes;
    }
    if (offset != bytes.length) {
      throw const CanvasReplayException('trailing_bytes');
    }
    return CanvasReplayCorpus._(
      bytes: bytes,
      surfaceWidth: width,
      surfaceHeight: height,
      qualityFrameCount: qualityFrames,
      frames: frames,
    );
  }

  static void _validateFrame(ByteData data, int totalBytes, _FrameIndex frame) {
    final resources = <CanvasReplayResource>[];
    for (var i = 0; i < frame.resourceCount; i++) {
      final offset = frame.resourceOffset + i * resourceRecordBytes;
      final resource = _readResource(data, offset);
      if (resource.key.source == 0 ||
          resource.key.resource == 0 ||
          resource.key.generation == 0 ||
          resource.width == 0 ||
          resource.height == 0 ||
          (resource.format != 0 && resource.format != 1)) {
        throw const CanvasReplayException('resource_bounds');
      }
      if (resource.uploaded) {
        if (resource.stride == 0 ||
            resource.uploadOffset + resource.uploadLength > frame.pixelCount) {
          throw const CanvasReplayException('resource_upload');
        }
      } else if (resource.uploadOffset != 0 ||
          resource.uploadLength != 0 ||
          resource.stride != 0) {
        throw const CanvasReplayException('resource_sparse');
      }
      resources.add(resource);
    }
    for (var i = 0; i < frame.removalCount; i++) {
      final offset = frame.removalOffset + i * removalRecordBytes;
      if (data.getUint64(offset, Endian.little) == 0 ||
          data.getUint64(offset + 8, Endian.little) == 0 ||
          data.getUint64(offset + 16, Endian.little) == 0) {
        throw const CanvasReplayException('removal_identity');
      }
    }
    for (var i = 0; i < frame.commandCount; i++) {
      final offset = frame.commandOffset + i * commandRecordBytes;
      final tag = data.getUint8(offset);
      final resourceIndex = data.getUint8(offset + 1);
      if (tag > 2) throw const CanvasReplayException('command_tag');
      if (tag == 0) {
        if (resourceIndex != 0xff ||
            data.getUint16(offset + 16, Endian.little) == 0 ||
            data.getUint16(offset + 18, Endian.little) == 0) {
          throw const CanvasReplayException('solid_command');
        }
        continue;
      }
      if (resourceIndex >= resources.length) {
        throw const CanvasReplayException('command_resource');
      }
      final destinationWidth = data.getUint16(offset + 16, Endian.little);
      final destinationHeight = data.getUint16(offset + 18, Endian.little);
      final clipWidth = data.getUint16(offset + 28, Endian.little);
      final clipHeight = data.getUint16(offset + 30, Endian.little);
      final sourceX = data.getUint16(offset + 32, Endian.little);
      final sourceY = data.getUint16(offset + 34, Endian.little);
      final sourceWidth = data.getUint16(offset + 36, Endian.little);
      final sourceHeight = data.getUint16(offset + 38, Endian.little);
      if (destinationWidth == 0 ||
          destinationHeight == 0 ||
          clipWidth == 0 ||
          clipHeight == 0 ||
          sourceWidth == 0 ||
          sourceHeight == 0) {
        throw const CanvasReplayException('draw_geometry');
      }
      final resource = resources[resourceIndex];
      if (sourceX + sourceWidth > resource.width ||
          sourceY + sourceHeight > resource.height) {
        throw const CanvasReplayException('source_bounds');
      }
    }
    _require(totalBytes, frame.pixelOffset, frame.pixelCount, 'pixels');
  }

  static CanvasReplayResource _readResource(ByteData data, int offset) {
    final source = data.getUint64(offset, Endian.little);
    final resource = data.getUint64(offset + 8, Endian.little);
    final generation = data.getUint64(offset + 16, Endian.little);
    return CanvasReplayResource(
      key: CanvasResourceKey(source, resource, generation),
      format: data.getUint8(offset + 24),
      width: data.getUint16(offset + 26, Endian.little),
      height: data.getUint16(offset + 28, Endian.little),
      stride: data.getUint32(offset + 32, Endian.little),
      uploadOffset: data.getUint32(offset + 36, Endian.little),
      uploadLength: data.getUint32(offset + 40, Endian.little),
    );
  }
}

final class CanvasReplayFrame {
  const CanvasReplayFrame._(this._corpus, this._index, this.index);

  final CanvasReplayCorpus _corpus;
  final _FrameIndex _index;
  final int index;

  int get flags => _index.flags;
  int get revision => _index.revision;
  int get resourceCount => _index.resourceCount;
  int get removalCount => _index.removalCount;
  int get commandCount => _index.commandCount;
  int get pixelCount => _index.pixelCount;
  bool get isQuality => flags == 1;
  bool get isChurn => flags == 2;

  CanvasReplayResource resource(int index) {
    if (index < 0 || index >= resourceCount) {
      throw const CanvasReplayException('resource_index');
    }
    return CanvasReplayCorpus._readResource(
      _corpus._data,
      _index.resourceOffset + index * CanvasReplayCorpus.resourceRecordBytes,
    );
  }

  CanvasResourceKey removal(int index) {
    if (index < 0 || index >= removalCount) {
      throw const CanvasReplayException('removal_index');
    }
    final offset =
        _index.removalOffset + index * CanvasReplayCorpus.removalRecordBytes;
    return CanvasResourceKey(
      _corpus._data.getUint64(offset, Endian.little),
      _corpus._data.getUint64(offset + 8, Endian.little),
      _corpus._data.getUint64(offset + 16, Endian.little),
    );
  }

  int commandTag(int index) => _u8(index, 0);
  int commandResourceIndex(int index) => _u8(index, 1);
  int commandFlags(int index) => _u8(index, 2);
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

  Uint8List uploadBytes(CanvasReplayResource resource) {
    if (!resource.uploaded) return Uint8List(0);
    return Uint8List.sublistView(
      _corpus._bytes,
      _index.pixelOffset + resource.uploadOffset,
      _index.pixelOffset + resource.uploadOffset + resource.uploadLength,
    );
  }

  int _commandOffset(int index) {
    if (index < 0 || index >= commandCount) {
      throw const CanvasReplayException('command_index');
    }
    return _index.commandOffset + index * CanvasReplayCorpus.commandRecordBytes;
  }

  int _u8(int index, int relative) =>
      _corpus._data.getUint8(_commandOffset(index) + relative);
  int _u16(int index, int relative) =>
      _corpus._data.getUint16(_commandOffset(index) + relative, Endian.little);
  int _u32(int index, int relative) =>
      _corpus._data.getUint32(_commandOffset(index) + relative, Endian.little);
  int _i32(int index, int relative) =>
      _corpus._data.getInt32(_commandOffset(index) + relative, Endian.little);
}

void _require(int total, int offset, int length, String code) {
  if (offset < 0 || length < 0 || offset > total || length > total - offset) {
    throw CanvasReplayException(code);
  }
}
