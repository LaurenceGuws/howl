import 'package:flutter/widgets.dart';

import 'terminal_fit.dart';

/// Centers one terminal surface while aligning its origin to physical pixels.
///
/// Flutter's ordinary [Center] may place a child at a half logical pixel when
/// the remaining viewport extent is odd. On a DPR-3 display that becomes a
/// half-physical-pixel phase after the native 3x glyph atlas is scaled back to
/// logical coordinates. Nearest-neighbour terminal masks must not inherit that
/// fractional layer translation.
final class TerminalPixelAlignedCenter extends StatelessWidget {
  const TerminalPixelAlignedCenter({
    super.key,
    required this.devicePixelRatio,
    required this.child,
  });

  final double devicePixelRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _TerminalPixelAlignedCenterDelegate(devicePixelRatio),
    child: child,
  );
}

final class _TerminalPixelAlignedCenterDelegate extends SingleChildLayoutDelegate {
  const _TerminalPixelAlignedCenterDelegate(this.devicePixelRatio);

  final double devicePixelRatio;

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      TerminalFit.centeredOrigin(
        viewportSize: size,
        contentSize: childSize,
        devicePixelRatio: devicePixelRatio,
      );

  @override
  bool shouldRelayout(_TerminalPixelAlignedCenterDelegate oldDelegate) =>
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
