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
    return TerminalFit._(
      scale: scale,
      rect: ui.Rect.fromLTWH(
        (viewportSize.width - width) / 2,
        (viewportSize.height - height) / 2,
        width,
        height,
      ),
    );
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
