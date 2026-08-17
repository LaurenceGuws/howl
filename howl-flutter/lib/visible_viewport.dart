import 'package:flutter/widgets.dart';

final class TerminalVisibleViewport extends StatelessWidget {
  const TerminalVisibleViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: MediaQuery.viewInsetsOf(context), child: child);
}
