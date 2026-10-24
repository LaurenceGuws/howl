import 'dart:math' as math;
import 'dart:ui' as ui;

/// One centered, aspect-preserving terminal surface transform.
///
/// Native terminal pixels are never enlarged here. A terminal larger than its
/// viewport is uniformly reduced; a smaller terminal keeps its natural size and
/// is centered. Canvas painting and input/selection geometry share this exact
/// transform so presentation coordinates cannot drift apart.
final class TerminalFit {
  const TerminalFit._({required this.scale, required this.rect});

  final double scale;
  final ui.Rect rect;

  static TerminalFit? contain({
    required ui.Size viewportSize,
    required ui.Size logicalSize,
    double? devicePixelRatio,
  }) {
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        !logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0) {
      return null;
    }
    final scale = math.min(
      1.0,
      math.min(
        viewportSize.width / logicalSize.width,
        viewportSize.height / logicalSize.height,
      ),
    );
    final width = logicalSize.width * scale;
    final height = logicalSize.height * scale;
    final origin = centeredOrigin(
      viewportSize: viewportSize,
      contentSize: ui.Size(width, height),
      devicePixelRatio: devicePixelRatio,
    );
    return TerminalFit._(
      scale: scale,
      rect: ui.Rect.fromLTWH(origin.dx, origin.dy, width, height),
    );
  }

  /// Centers one surface and optionally snaps its origin to physical pixels.
  ///
  /// This is shared by the render-tree child placement and pointer/selection
  /// geometry so the terminal cannot be painted on one pixel phase while input
  /// still targets the unsnapped centered rectangle.
  static ui.Offset centeredOrigin({
    required ui.Size viewportSize,
    required ui.Size contentSize,
    double? devicePixelRatio,
  }) {
    final raw = ui.Offset(
      (viewportSize.width - contentSize.width) / 2,
      (viewportSize.height - contentSize.height) / 2,
    );
    final ratio = devicePixelRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) return raw;
    double snap(double value) => (value * ratio).round() / ratio;
    return ui.Offset(snap(raw.dx), snap(raw.dy));
  }

  ui.Offset? logicalOffset(ui.Offset position) {
    if (!position.dx.isFinite ||
        !position.dy.isFinite ||
        !rect.contains(position)) {
      return null;
    }
    return ui.Offset(
      (position.dx - rect.left) / scale,
      (position.dy - rect.top) / scale,
    );
  }
}
