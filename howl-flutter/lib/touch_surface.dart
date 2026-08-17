import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Touch-only terminal gesture policy.
///
/// A tap is intentionally distinct from a vertical drag so scrolling history
/// does not also summon the platform text editor. Mouse/stylus input remains
/// outside this gesture recognizer for a later semantic-pointer slice.
final class TerminalTouchSurface extends StatelessWidget {
  const TerminalTouchSurface({
    super.key,
    required this.onTap,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.child,
  });

  final VoidCallback onTap;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch},
    onTap: onTap,
    onVerticalDragStart: onVerticalDragStart,
    onVerticalDragUpdate: onVerticalDragUpdate,
    onVerticalDragEnd: onVerticalDragEnd,
    child: child,
  );
}
