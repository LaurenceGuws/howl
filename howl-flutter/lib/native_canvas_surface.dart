import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'native_canvas.dart';

sealed class _PaintSegment {
  const _PaintSegment();
  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images);
}

final class _SolidSegment extends _PaintSegment {
  const _SolidSegment(this.rect, this.color);
  final ui.Rect rect;
  final ui.Color color;

  @override
  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images) {
    canvas.drawRect(rect, ui.Paint()..color = color);
  }
}

final class _AtlasSegment extends _PaintSegment {
  const _AtlasSegment({
    required this.resource,
    required this.transforms,
    required this.rects,
    required this.colors,
  });

  final NativeCanvasResourceKey resource;
  final Float32List transforms;
  final Float32List rects;
  final Int32List colors;

  @override
  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images) {
    final image = images[resource];
    if (image == null) {
      throw StateError('missing native Canvas resource $resource');
    }
    canvas.drawRawAtlas(
      image,
      transforms,
      rects,
      colors,
      ui.BlendMode.dstIn,
      null,
      ui.Paint(),
    );
  }
}

final class _RgbaSegment extends _PaintSegment {
  const _RgbaSegment({
    required this.resource,
    required this.source,
    required this.destination,
    required this.clip,
  });

  final NativeCanvasResourceKey resource;
  final ui.Rect source;
  final ui.Rect destination;
  final ui.Rect clip;

  @override
  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images) {
    final image = images[resource];
    if (image == null) {
      throw StateError('missing native Canvas resource $resource');
    }
    canvas.save();
    canvas.clipRect(clip);
    canvas.drawImageRect(image, source, destination, ui.Paint());
    canvas.restore();
  }
}

final class NativeCanvasPlan {
  NativeCanvasPlan._(this._segments);
  final List<_PaintSegment> _segments;

  int get segmentCountForTesting => _segments.length;

  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images) {
    for (final segment in _segments) {
      segment.paint(canvas, images);
    }
  }
}

NativeCanvasPlan buildNativeCanvasPlan(NativeCanvasFrame frame) {
  final resources = List<NativeCanvasResource>.generate(
    frame.resourceCount,
    frame.resource,
    growable: false,
  );
  final segments = <_PaintSegment>[];

  var index = 0;
  while (index < frame.commandCount) {
    final tag = frame.commandTag(index);
    if (tag == 0) {
      segments.add(
        _SolidSegment(
          _destination(frame, index),
          _rgbaBitsToColor(frame.commandColorRgba(index)),
        ),
      );
      index += 1;
      continue;
    }

    final resourceIndex = frame.commandResourceIndex(index);
    if (resourceIndex < 0 || resourceIndex >= resources.length) {
      throw const NativeCanvasException('paint_resource');
    }
    final resource = resources[resourceIndex];

    if (tag == 1) {
      var end = index + 1;
      while (end < frame.commandCount &&
          frame.commandTag(end) == 1 &&
          frame.commandResourceIndex(end) == resourceIndex) {
        end += 1;
      }
      final segment = _buildAtlasSegment(frame, resource.key, index, end);
      if (segment != null) segments.add(segment);
      index = end;
      continue;
    }

    if (tag == 2) {
      final destination = _destination(frame, index);
      final clip = _clip(frame, index);
      if (!destination.intersect(clip).isEmpty) {
        segments.add(
          _RgbaSegment(
            resource: resource.key,
            source: _source(frame, index),
            destination: destination,
            clip: clip,
          ),
        );
      }
      index += 1;
      continue;
    }
    throw const NativeCanvasException('paint_tag');
  }
  return NativeCanvasPlan._(List.unmodifiable(segments));
}

_AtlasSegment? _buildAtlasSegment(
  NativeCanvasFrame frame,
  NativeCanvasResourceKey resource,
  int start,
  int end,
) {
  final capacity = end - start;
  final transforms = Float32List(capacity * 4);
  final rects = Float32List(capacity * 4);
  final colors = Int32List(capacity);
  var count = 0;

  for (var index = start; index < end; index++) {
    final clipped = clipNativeCanvasSprite(
      _destination(frame, index),
      _clip(frame, index),
      _source(frame, index),
    );
    if (clipped == null) continue;
    final offset = count * 4;
    transforms[offset] = 1;
    transforms[offset + 1] = 0;
    transforms[offset + 2] = clipped.destination.left;
    transforms[offset + 3] = clipped.destination.top;
    rects[offset] = clipped.source.left;
    rects[offset + 1] = clipped.source.top;
    rects[offset + 2] = clipped.source.right;
    rects[offset + 3] = clipped.source.bottom;
    colors[count] = _rgbaBitsToColor(frame.commandColorRgba(index))
        .toARGB32()
        .toSigned(32);
    count += 1;
  }
  if (count == 0) return null;
  if (count == capacity) {
    return _AtlasSegment(
      resource: resource,
      transforms: transforms,
      rects: rects,
      colors: colors,
    );
  }
  return _AtlasSegment(
    resource: resource,
    transforms: Float32List.view(
      transforms.buffer,
      transforms.offsetInBytes,
      count * 4,
    ),
    rects: Float32List.view(rects.buffer, rects.offsetInBytes, count * 4),
    colors: Int32List.view(colors.buffer, colors.offsetInBytes, count),
  );
}

final class NativeCanvasClip {
  const NativeCanvasClip(this.destination, this.source);
  final ui.Rect destination;
  final ui.Rect source;
}

NativeCanvasClip? clipNativeCanvasSprite(
  ui.Rect destination,
  ui.Rect clip,
  ui.Rect source,
) {
  if (destination.width != source.width ||
      destination.height != source.height) {
    throw const NativeCanvasException('scaled_alpha');
  }
  final visible = destination.intersect(clip);
  if (visible.isEmpty) return null;
  return NativeCanvasClip(
    visible,
    ui.Rect.fromLTWH(
      source.left + visible.left - destination.left,
      source.top + visible.top - destination.top,
      visible.width,
      visible.height,
    ),
  );
}

final class NativeCanvasLease {
  const NativeCanvasLease({
    required this.frame,
    required this.images,
    required this.plan,
  });

  final NativeCanvasFrame frame;
  final Map<NativeCanvasResourceKey, ui.Image> images;
  final NativeCanvasPlan plan;
}

final class NativeCanvasLeaseUpdate {
  const NativeCanvasLeaseUpdate({required this.lease, required this.retired});
  final NativeCanvasLease lease;
  final List<ui.Image> retired;
}

Future<NativeCanvasLeaseUpdate> prepareNativeCanvasFrame(
  NativeCanvasLease? previous,
  NativeCanvasFrame frame,
) async {
  final images = <NativeCanvasResourceKey, ui.Image>{...?previous?.images};
  final retired = <ui.Image>[];

  for (var index = 0; index < frame.removalCount; index++) {
    final removed = images.remove(frame.removal(index));
    if (removed != null) retired.add(removed);
  }

  final resources = List<NativeCanvasResource>.generate(
    frame.resourceCount,
    frame.resource,
    growable: false,
  );
  final currentKeys = resources.map((resource) => resource.key).toSet();
  for (final key
      in images.keys.where((key) => !currentKeys.contains(key)).toList()) {
    final removed = images.remove(key);
    if (removed != null) retired.add(removed);
  }

  for (final resource in resources) {
    if (resource.uploaded) {
      final old = images.remove(resource.key);
      if (old != null) retired.add(old);
      images[resource.key] = await _decodeResource(frame, resource);
    }
    if (!images.containsKey(resource.key)) {
      for (final image in images.values) {
        if (!retired.contains(image)) retired.add(image);
      }
      throw StateError(
        'native Canvas frame references nonresident ${resource.key}',
      );
    }
  }

  return NativeCanvasLeaseUpdate(
    lease: NativeCanvasLease(
      frame: frame,
      images: Map.unmodifiable(images),
      plan: buildNativeCanvasPlan(frame),
    ),
    retired: retired,
  );
}

Future<ui.Image> _decodeResource(
  NativeCanvasFrame frame,
  NativeCanvasResource resource,
) async {
  final source = frame.uploadBytes(resource);
  if (source.length < resource.stride * resource.height) {
    throw const NativeCanvasException('upload_stride');
  }
  final rgba = Uint8List(resource.width * resource.height * 4);
  for (var y = 0; y < resource.height; y++) {
    for (var x = 0; x < resource.width; x++) {
      final target = (y * resource.width + x) * 4;
      if (resource.format == 0) {
        final coverage = source[y * resource.stride + x];
        rgba[target] = coverage;
        rgba[target + 1] = coverage;
        rgba[target + 2] = coverage;
        rgba[target + 3] = coverage;
      } else if (resource.format == 1) {
        final input = y * resource.stride + x * 4;
        if (input + 4 > source.length) {
          throw const NativeCanvasException('rgba_upload');
        }
        final alpha = source[input + 3];
        rgba[target] = (source[input] * alpha + 127) ~/ 255;
        rgba[target + 1] = (source[input + 1] * alpha + 127) ~/ 255;
        rgba[target + 2] = (source[input + 2] * alpha + 127) ~/ 255;
        rgba[target + 3] = alpha;
      } else {
        throw const NativeCanvasException('resource_format');
      }
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    resource.width,
    resource.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void disposeNativeCanvasLease(NativeCanvasLease? lease) {
  if (lease == null) return;
  for (final image in lease.images.values) {
    image.dispose();
  }
}

final class NativeCanvasPainter extends CustomPainter {
  const NativeCanvasPainter({
    required this.lease,
    required this.logicalWidth,
    required this.logicalHeight,
  });

  final NativeCanvasLease lease;
  final double logicalWidth;
  final double logicalHeight;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final scale = (size.width / logicalWidth).clamp(
      0.0,
      size.height / logicalHeight,
    );
    final paintedWidth = logicalWidth * scale;
    final paintedHeight = logicalHeight * scale;
    canvas.save();
    canvas.translate(
      (size.width - paintedWidth) / 2,
      (size.height - paintedHeight) / 2,
    );
    canvas.scale(scale);
    lease.plan.paint(canvas, lease.images);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant NativeCanvasPainter oldDelegate) =>
      oldDelegate.lease.frame.revision != lease.frame.revision;
}

ui.Rect _destination(NativeCanvasFrame frame, int index) => ui.Rect.fromLTWH(
  frame.commandDestinationX(index).toDouble(),
  frame.commandDestinationY(index).toDouble(),
  frame.commandDestinationWidth(index).toDouble(),
  frame.commandDestinationHeight(index).toDouble(),
);

ui.Rect _clip(NativeCanvasFrame frame, int index) => ui.Rect.fromLTWH(
  frame.commandClipX(index).toDouble(),
  frame.commandClipY(index).toDouble(),
  frame.commandClipWidth(index).toDouble(),
  frame.commandClipHeight(index).toDouble(),
);

ui.Rect _source(NativeCanvasFrame frame, int index) => ui.Rect.fromLTWH(
  frame.commandSourceX(index).toDouble(),
  frame.commandSourceY(index).toDouble(),
  frame.commandSourceWidth(index).toDouble(),
  frame.commandSourceHeight(index).toDouble(),
);

ui.Color _rgbaBitsToColor(int value) => ui.Color.fromARGB(
  (value >> 24) & 0xff,
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
);
