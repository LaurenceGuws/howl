import 'package:flutter/widgets.dart';

/// Small non-terminal status surface used before a snapshot can be painted.
///
/// It deliberately does not depend on Material. Howl's terminal surface is a
/// custom painter, so status text must carry its own presentation instead of
/// falling through to MaterialApp's conspicuous missing-Material debug style.
final class TerminalStatusText extends StatelessWidget {
  const TerminalStatusText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5),
      style: const TextStyle(
        color: Color(0xffc7ced9),
        fontFamily: 'monospace',
        fontSize: 16,
        fontWeight: FontWeight.normal,
        decoration: TextDecoration.none,
      ),
    ),
  );
}
