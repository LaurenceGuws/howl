import 'package:flutter/material.dart';

import 'howl_input.dart';

/// Compact mobile terminal controls that software keyboards do not reliably
/// expose. Modifiers are caller-owned one-shot latches; this widget only
/// presents their current state and exact semantic key identities.
final class TerminalControlStrip extends StatelessWidget {
  const TerminalControlStrip({
    super.key,
    required this.modifierLatch,
    required this.onModifier,
    required this.onKey,
    required this.onKeyboard,
    required this.onCopy,
    required this.onPaste,
  });

  final int modifierLatch;
  final ValueChanged<int> onModifier;
  final ValueChanged<int> onKey;
  final VoidCallback onKeyboard;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff11161b),
    child: SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          _modifier('Ctrl', HowlInput.modifierControl),
          _modifier('Alt', HowlInput.modifierAlt),
          _key('Esc', HowlInput.namedEscape),
          _key('Tab', HowlInput.namedTab),
          _key('←', HowlInput.namedArrowLeft),
          _key('↓', HowlInput.namedArrowDown),
          _key('↑', HowlInput.namedArrowUp),
          _key('→', HowlInput.namedArrowRight),
          _action('Kbd', onKeyboard),
          _action('Copy', onCopy),
          _action('Paste', onPaste),
        ],
      ),
    ),
  );

  Widget _modifier(String label, int bit) => Expanded(
    child: _TerminalControlButton(
      label: label,
      latched: modifierLatch & bit != 0,
      onTap: () => onModifier(bit),
    ),
  );

  Widget _key(String label, int keyName) => Expanded(
    child: _TerminalControlButton(label: label, onTap: () => onKey(keyName)),
  );

  Widget _action(String label, VoidCallback action) => Expanded(
    child: _TerminalControlButton(label: label, onTap: action),
  );
}

final class _TerminalControlButton extends StatelessWidget {
  const _TerminalControlButton({
    required this.label,
    required this.onTap,
    this.latched,
  });

  final String label;
  final VoidCallback onTap;
  final bool? latched;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(2),
    child: Semantics(
      button: true,
      toggled: latched,
      child: Material(
        color: latched == true
            ? const Color(0xff40515f)
            : const Color(0xff202a32),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xffd7e0e7),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
