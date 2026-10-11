import 'package:flutter/widgets.dart';

final class TerminalVisibleViewport extends StatelessWidget {
  const TerminalVisibleViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final obscured = MediaQuery.viewInsetsOf(context);
    final safe = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        obscured.left > safe.left ? obscured.left : safe.left,
        obscured.top > safe.top ? obscured.top : safe.top,
        obscured.right > safe.right ? obscured.right : safe.right,
        obscured.bottom > safe.bottom ? obscured.bottom : safe.bottom,
      ),
      child: child,
    );
  }
}
