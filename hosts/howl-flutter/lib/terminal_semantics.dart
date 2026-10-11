import 'package:flutter/widgets.dart';

/// Accessibility projection for one already-canonical terminal viewport.
///
/// Text is supplied by the app-private native host from `howl-client.view`;
/// this widget does not parse terminal bytes or reconstruct terminal state.
final class TerminalSemanticSurface extends StatelessWidget {
  const TerminalSemanticSurface({
    super.key,
    required this.value,
    required this.truncated,
    required this.child,
  });

  final String value;
  final bool truncated;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Terminal',
    value: value,
    hint: truncated ? 'Visible terminal text truncated' : null,
    readOnly: true,
    multiline: true,
    child: child,
  );
}
