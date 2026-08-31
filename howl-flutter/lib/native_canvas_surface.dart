import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'native_canvas_replay.dart';

final class CanvasReplayPlanStats {
  const CanvasReplayPlanStats({
    required this.segments,
    required this.solids,
    required this.atlasSegments,
    required this.sprites,
    required this.rgbaDraws,
  });

  final int segments;
  final int solids;
  final int atlasSegments;
  final int sprites;
  final int rgbaDraws;
}

sealed class _PaintSegment {
  const _PaintSegment();

  String get kind;
  void paint(ui.Canvas canvas, Map<CanvasResourceKey, ui.Image> images);
}

final class _SolidSegment extends _PaintSegment {
  const _SolidSegment(this.rect, this.color);
  final ui.Rect rect;
  final ui.Color color;

  @override
  String get kind => 'solid';

  @override
  void paint(ui.Canvas canvas, Map<CanvasResourceKey, ui.Image> images) {
    canvas.drawRect(rect, ui.Paint()..color = color);
  }
}

final class _AtlasSegment extends _PaintSegment {
  const _AtlasSegment({
    required this.resource,
    required this.transforms,
    required this.rects,
    required this.colors,
    required this.spriteCount,
  });

  final CanvasResourceKey resource;
  final Float32List transforms;
  final Float32List rects;
  final Int32List colors;
  final int spriteCount;

  @override
  String get kind => 'atlas';

  @override
  void paint(ui.Canvas canvas, Map<CanvasResourceKey, ui.Image> images) {
    final image = images[resource];
    if (image == null) throw StateError('missing replay resource $resource');
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

  final CanvasResourceKey resource;
  final ui.Rect source;
  final ui.Rect destination;
  final ui.Rect clip;

  @override
  String get kind => 'rgba';

  @override
  void paint(ui.Canvas canvas, Map<CanvasResourceKey, ui.Image> images) {
    final image = images[resource];
    if (image == null) throw StateError('missing replay resource $resource');
    canvas.save();
    canvas.clipRect(clip);
    canvas.drawImageRect(image, source, destination, ui.Paint());
    canvas.restore();
  }
}

final class _AtlasBuilder {
  _AtlasBuilder(this.resource);

  final CanvasResourceKey resource;
  final List<double> _transforms = <double>[];
  final List<double> _rects = <double>[];
  final List<int> _colors = <int>[];

  int get count => _colors.length;

  void add({
    required ui.Rect destination,
    required ui.Rect source,
    required ui.Color color,
  }) {
    _transforms.addAll(<double>[1, 0, destination.left, destination.top]);
    _rects.addAll(<double>[
      source.left,
      source.top,
      source.right,
      source.bottom,
    ]);
    _colors.add(color.toARGB32().toSigned(32));
  }

  _AtlasSegment finish() => _AtlasSegment(
    resource: resource,
    transforms: Float32List.fromList(_transforms),
    rects: Float32List.fromList(_rects),
    colors: Int32List.fromList(_colors),
    spriteCount: count,
  );
}

final class CanvasReplayPaintPlan {
  CanvasReplayPaintPlan._(this._segments, this.stats);

  final List<_PaintSegment> _segments;
  final CanvasReplayPlanStats stats;

  List<String> get segmentKindsForTesting =>
      List<String>.unmodifiable(_segments.map((segment) => segment.kind));

  void paint(ui.Canvas canvas, Map<CanvasResourceKey, ui.Image> images) {
    for (final segment in _segments) {
      segment.paint(canvas, images);
    }
  }
}

CanvasReplayPaintPlan buildCanvasReplayPaintPlan(CanvasReplayFrame frame) {
  final resources = List<CanvasReplayResource>.generate(
    frame.resourceCount,
    frame.resource,
    growable: false,
  );
  final segments = <_PaintSegment>[];
  _AtlasBuilder? atlas;
  var solidCount = 0;
  var atlasCount = 0;
  var spriteCount = 0;
  var rgbaCount = 0;

  void flushAtlas() {
    final current = atlas;
    if (current == null || current.count == 0) {
      atlas = null;
      return;
    }
    segments.add(current.finish());
    atlasCount += 1;
    spriteCount += current.count;
    atlas = null;
  }

  for (var index = 0; index < frame.commandCount; index++) {
    final tag = frame.commandTag(index);
    if (tag == 0) {
      flushAtlas();
      segments.add(
        _SolidSegment(
          _destination(frame, index),
          _rgbaBitsToColor(frame.commandColorRgba(index)),
        ),
      );
      solidCount += 1;
      continue;
    }
    final resourceIndex = frame.commandResourceIndex(index);
    if (resourceIndex < 0 || resourceIndex >= resources.length) {
      throw const CanvasReplayException('paint_resource');
    }
    final resource = resources[resourceIndex];
    final destination = _destination(frame, index);
    final clip = _clip(frame, index);
    final source = _source(frame, index);

    if (tag == 1) {
      final clipped = clipReplaySprite(destination, clip, source);
      if (clipped == null) continue;
      if (atlas == null || atlas!.resource != resource.key) {
        flushAtlas();
        atlas = _AtlasBuilder(resource.key);
      }
      atlas!.add(
        destination: clipped.destination,
        source: clipped.source,
        color: _rgbaBitsToColor(frame.commandColorRgba(index)),
      );
      continue;
    }

    flushAtlas();
    if (tag == 2) {
      if (destination.intersect(clip).isEmpty) continue;
      segments.add(
        _RgbaSegment(
          resource: resource.key,
          source: source,
          destination: destination,
          clip: clip,
        ),
      );
      rgbaCount += 1;
      continue;
    }
    throw const CanvasReplayException('paint_tag');
  }
  flushAtlas();
  return CanvasReplayPaintPlan._(
    List.unmodifiable(segments),
    CanvasReplayPlanStats(
      segments: segments.length,
      solids: solidCount,
      atlasSegments: atlasCount,
      sprites: spriteCount,
      rgbaDraws: rgbaCount,
    ),
  );
}

final class CanvasReplayClipResult {
  const CanvasReplayClipResult(this.destination, this.source);

  final ui.Rect destination;
  final ui.Rect source;
}

CanvasReplayClipResult? clipReplaySprite(
  ui.Rect destination,
  ui.Rect clip,
  ui.Rect source,
) {
  if (destination.width != source.width ||
      destination.height != source.height) {
    throw const CanvasReplayException('scaled_alpha_pressure');
  }
  final visible = destination.intersect(clip);
  if (visible.isEmpty) return null;
  return CanvasReplayClipResult(
    visible,
    ui.Rect.fromLTWH(
      source.left + visible.left - destination.left,
      source.top + visible.top - destination.top,
      visible.width,
      visible.height,
    ),
  );
}

final class CanvasReplayFrameLease {
  const CanvasReplayFrameLease({
    required this.frame,
    required this.images,
    required this.plan,
  });

  final CanvasReplayFrame frame;
  final Map<CanvasResourceKey, ui.Image> images;
  final CanvasReplayPaintPlan plan;
}

final class CanvasReplayLeaseUpdate {
  const CanvasReplayLeaseUpdate({
    required this.lease,
    required this.retired,
    required this.uploadCount,
    required this.uploadBytes,
    required this.removalCount,
    required this.prepareMicroseconds,
  });

  final CanvasReplayFrameLease lease;
  final List<ui.Image> retired;
  final int uploadCount;
  final int uploadBytes;
  final int removalCount;
  final int prepareMicroseconds;
}

Future<CanvasReplayLeaseUpdate> prepareCanvasReplayFrame(
  CanvasReplayFrameLease? previous,
  CanvasReplayFrame frame,
) async {
  final watch = Stopwatch()..start();
  final images = <CanvasResourceKey, ui.Image>{...?previous?.images};
  final retired = <ui.Image>[];
  var uploadCount = 0;
  var uploadBytes = 0;

  for (var index = 0; index < frame.removalCount; index++) {
    final removed = images.remove(frame.removal(index));
    if (removed != null) retired.add(removed);
  }

  final currentKeys = <CanvasResourceKey>{};
  final resources = List<CanvasReplayResource>.generate(
    frame.resourceCount,
    frame.resource,
    growable: false,
  );
  for (final resource in resources) {
    currentKeys.add(resource.key);
  }
  final stale = images.keys.where((key) => !currentKeys.contains(key)).toList();
  for (final key in stale) {
    final image = images.remove(key);
    if (image != null) retired.add(image);
  }

  for (final resource in resources) {
    if (resource.uploaded) {
      final old = images.remove(resource.key);
      if (old != null) retired.add(old);
      images[resource.key] = await _decodeResource(frame, resource);
      uploadCount += 1;
      uploadBytes += resource.uploadLength;
    }
    if (!images.containsKey(resource.key)) {
      for (final image in images.values) {
        if (!retired.contains(image)) retired.add(image);
      }
      throw StateError('replay frame references nonresident ${resource.key}');
    }
  }

  final plan = buildCanvasReplayPaintPlan(frame);
  watch.stop();
  return CanvasReplayLeaseUpdate(
    lease: CanvasReplayFrameLease(
      frame: frame,
      images: Map.unmodifiable(images),
      plan: plan,
    ),
    retired: retired,
    uploadCount: uploadCount,
    uploadBytes: uploadBytes,
    removalCount: frame.removalCount,
    prepareMicroseconds: watch.elapsedMicroseconds,
  );
}

Future<ui.Image> _decodeResource(
  CanvasReplayFrame frame,
  CanvasReplayResource resource,
) async {
  final source = frame.uploadBytes(resource);
  if (source.length < resource.stride * resource.height) {
    throw const CanvasReplayException('upload_stride');
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
          throw const CanvasReplayException('rgba_upload');
        }
        final alpha = source[input + 3];
        rgba[target] = (source[input] * alpha + 127) ~/ 255;
        rgba[target + 1] = (source[input + 1] * alpha + 127) ~/ 255;
        rgba[target + 2] = (source[input + 2] * alpha + 127) ~/ 255;
        rgba[target + 3] = alpha;
      } else {
        throw const CanvasReplayException('resource_format');
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

void disposeCanvasReplayLease(CanvasReplayFrameLease? lease) {
  if (lease == null) return;
  for (final image in lease.images.values) {
    image.dispose();
  }
}

final class CanvasReplayPainter extends CustomPainter {
  const CanvasReplayPainter({
    required this.lease,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.onPaint,
  });

  final CanvasReplayFrameLease lease;
  final double logicalWidth;
  final double logicalHeight;
  final VoidCallback onPaint;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    onPaint();
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
  bool shouldRepaint(covariant CanvasReplayPainter oldDelegate) =>
      oldDelegate.lease.frame.revision != lease.frame.revision;
}

ui.Rect _destination(CanvasReplayFrame frame, int index) => ui.Rect.fromLTWH(
  frame.commandDestinationX(index).toDouble(),
  frame.commandDestinationY(index).toDouble(),
  frame.commandDestinationWidth(index).toDouble(),
  frame.commandDestinationHeight(index).toDouble(),
);

ui.Rect _clip(CanvasReplayFrame frame, int index) => ui.Rect.fromLTWH(
  frame.commandClipX(index).toDouble(),
  frame.commandClipY(index).toDouble(),
  frame.commandClipWidth(index).toDouble(),
  frame.commandClipHeight(index).toDouble(),
);

ui.Rect _source(CanvasReplayFrame frame, int index) => ui.Rect.fromLTWH(
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
