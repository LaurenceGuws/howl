import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'native_canvas.dart';
import 'terminal_fit.dart';

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
      // drawRawAtlas blends the atlas image with each sprite color in image-first
      // order. Modulation preserves the white alpha-mask coverage while applying
      // the per-sprite foreground RGB; srcIn would keep the atlas RGB white.
      ui.BlendMode.modulate,
      null,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
  }
}

final class _ScaledAlphaSegment extends _PaintSegment {
  const _ScaledAlphaSegment({
    required this.resource,
    required this.source,
    required this.destination,
    required this.color,
  });

  final NativeCanvasResourceKey resource;
  final ui.Rect source;
  final ui.Rect destination;
  final ui.Color color;

  @override
  void paint(ui.Canvas canvas, Map<NativeCanvasResourceKey, ui.Image> images) {
    final image = images[resource];
    if (image == null) {
      throw StateError('missing native Canvas resource $resource');
    }
    canvas.drawImageRect(
      image,
      source,
      destination,
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn),
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
      final colorBits = frame.commandColorRgba(index);
      var destination = _destination(frame, index);
      var end = index + 1;
      while (end < frame.commandCount &&
          frame.commandTag(end) == 0 &&
          frame.commandColorRgba(end) == colorBits) {
        final next = _destination(frame, end);
        if (destination.top != next.top ||
            destination.bottom != next.bottom ||
            destination.right != next.left) {
          break;
        }
        destination = ui.Rect.fromLTRB(
          destination.left,
          destination.top,
          next.right,
          destination.bottom,
        );
        end += 1;
      }
      segments.add(_SolidSegment(destination, _rgbaBitsToColor(colorBits)));
      index = end;
      continue;
    }

    final resourceIndex = frame.commandResourceIndex(index);
    if (resourceIndex < 0 || resourceIndex >= resources.length) {
      throw const NativeCanvasException('paint_resource');
    }
    final resource = resources[resourceIndex];

    if (tag == 1) {
      final destination = _destination(frame, index);
      final source = _source(frame, index);
      if (!_sameExtent(destination, source)) {
        final clipped = clipNativeCanvasSprite(
          destination,
          _clip(frame, index),
          source,
        );
        if (clipped != null) {
          segments.add(
            _ScaledAlphaSegment(
              resource: resource.key,
              source: clipped.source,
              destination: clipped.destination,
              color: _rgbaBitsToColor(frame.commandColorRgba(index)),
            ),
          );
        }
        index += 1;
        continue;
      }
      var end = index + 1;
      while (end < frame.commandCount &&
          frame.commandTag(end) == 1 &&
          frame.commandResourceIndex(end) == resourceIndex &&
          _sameExtent(_destination(frame, end), _source(frame, end))) {
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
  final visible = destination.intersect(clip);
  if (visible.isEmpty) return null;
  final scaleX = source.width / destination.width;
  final scaleY = source.height / destination.height;
  return NativeCanvasClip(
    visible,
    ui.Rect.fromLTWH(
      source.left + (visible.left - destination.left) * scaleX,
      source.top + (visible.top - destination.top) * scaleY,
      visible.width * scaleX,
      visible.height * scaleY,
    ),
  );
}

bool _sameExtent(ui.Rect left, ui.Rect right) =>
    left.width == right.width && left.height == right.height;

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

/// One decoded external resource which is resident before its retry frame.
final class NativeCanvasPreloadedResource {
  const NativeCanvasPreloadedResource({
    required this.resource,
    required this.image,
  });

  final NativeCanvasResource resource;
  final ui.Image image;
}

final class NativeCanvasLeaseUpdate {
  const NativeCanvasLeaseUpdate({
    required this.lease,
    required this.retired,
    required this.introduced,
  });
  final NativeCanvasLease lease;

  /// Images owned by the previous lease which become disposable after adoption.
  final List<ui.Image> retired;

  /// Images created for this candidate and safe to dispose if it is abandoned.
  final List<ui.Image> introduced;
}

Future<NativeCanvasLeaseUpdate> prepareNativeCanvasFrame(
  NativeCanvasLease? previous,
  NativeCanvasFrame frame, {
  Iterable<NativeCanvasPreloadedResource> preloaded = const [],
}) async {
  final images = <NativeCanvasResourceKey, ui.Image>{...?previous?.images};
  final retired = <ui.Image>[];
  final introduced = <ui.Image>[];
  final preloadByKey =
      <NativeCanvasResourceKey, NativeCanvasPreloadedResource>{};
  final preloads = preloaded.toList(growable: false);

  void introduce(ui.Image image) {
    if (!introduced.contains(image)) introduced.add(image);
  }

  for (final preload in preloads) {
    if (preloadByKey.containsKey(preload.resource.key)) {
      for (final resource in preloads) {
        if (!introduced.contains(resource.image)) introduce(resource.image);
      }
      for (final image in introduced) {
        image.dispose();
      }
      throw const NativeCanvasException('external_upload_duplicate');
    }
    preloadByKey[preload.resource.key] = preload;
    introduce(preload.image);
  }

  try {
    for (final preload in preloadByKey.values) {
      final old = images.remove(preload.resource.key);
      if (old != null && old != preload.image) retired.add(old);
      images[preload.resource.key] = preload.image;
    }

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
      final preload = preloadByKey[resource.key];
      if (preload != null &&
          (preload.resource.format != resource.format ||
              preload.resource.width != resource.width ||
              preload.resource.height != resource.height)) {
        throw const NativeCanvasException('external_upload_metadata');
      }
      if (resource.uploaded) {
        final old = images.remove(resource.key);
        if (old != null) retired.add(old);
        final decoded = await _decodeResource(frame, resource);
        introduce(decoded);
        images[resource.key] = decoded;
      }
      if (!images.containsKey(resource.key)) {
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
      introduced: introduced,
    );
  } catch (_) {
    for (final image in introduced) {
      image.dispose();
    }
    rethrow;
  }
}

/// Disposes only images created by an unadopted candidate.
///
/// Images in `retired` still belong to `previous` until the candidate is
/// actually installed, so abandoning a candidate must leave them untouched.
void disposeNativeCanvasLeaseCandidate(NativeCanvasLeaseUpdate update) {
  for (final image in update.introduced) {
    image.dispose();
  }
}

Future<ui.Image> _decodeResource(
  NativeCanvasFrame frame,
  NativeCanvasResource resource,
) async {
  return _decodeResourceBytes(resource, frame.uploadBytes(resource));
}

Future<NativeCanvasPreloadedResource> prepareNativeCanvasExternalUpload(
  NativeCanvasExternalUpload upload,
) async {
  if (upload.resource.uploaded || upload.resource.format != 1) {
    throw const NativeCanvasException('external_upload_resource');
  }
  return NativeCanvasPreloadedResource(
    resource: upload.resource,
    image: await _decodeResourceBytes(upload.resource, upload.pixels),
  );
}

void disposeNativeCanvasPreloadedResources(
  Iterable<NativeCanvasPreloadedResource> resources,
) {
  for (final resource in resources) {
    resource.image.dispose();
  }
}

Future<ui.Image> _decodeResourceBytes(
  NativeCanvasResource resource,
  Uint8List source,
) async {
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
    final fit = TerminalFit.contain(
      viewportSize: size,
      logicalSize: ui.Size(logicalWidth, logicalHeight),
    );
    if (fit == null) return;
    final surfaceWidth = lease.frame.surfaceWidth.toDouble();
    final surfaceHeight = lease.frame.surfaceHeight.toDouble();
    if (surfaceWidth <= 0 || surfaceHeight <= 0) return;
    canvas.save();
    canvas.translate(fit.rect.left, fit.rect.top);
    canvas.scale(
      fit.scale * logicalWidth / surfaceWidth,
      fit.scale * logicalHeight / surfaceHeight,
    );
    canvas.saveLayer(
      ui.Rect.fromLTWH(0, 0, surfaceWidth, surfaceHeight),
      ui.Paint()..colorFilter = const ui.ColorFilter.linearToSrgbGamma(),
    );
    lease.plan.paint(canvas, lease.images);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant NativeCanvasPainter oldDelegate) =>
      oldDelegate.lease.frame.revision != lease.frame.revision ||
      oldDelegate.lease.frame.surfaceWidth != lease.frame.surfaceWidth ||
      oldDelegate.lease.frame.surfaceHeight != lease.frame.surfaceHeight ||
      oldDelegate.logicalWidth != logicalWidth ||
      oldDelegate.logicalHeight != logicalHeight;
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

ui.Color _rgbaBitsToColor(int value) => ui.Color.from(
  alpha: ((value >> 24) & 0xff) / 255.0,
  red: _srgbByteToLinear(value & 0xff),
  green: _srgbByteToLinear((value >> 8) & 0xff),
  blue: _srgbByteToLinear((value >> 16) & 0xff),
);

double _srgbByteToLinear(int value) {
  final encoded = value / 255.0;
  return encoded <= 0.04045
      ? encoded / 12.92
      : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
}
