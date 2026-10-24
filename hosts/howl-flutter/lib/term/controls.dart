import 'package:flutter/material.dart';

import '../delete/howl_input.dart';
import 'presentation.dart';

enum _ExtraControl { alt, zoom, lead, copy, paste, log }

/// Compact mobile terminal controls that software keyboards do not reliably
/// expose. Modifiers are caller-owned one-shot latches; this widget only
/// presents their current state and exact semantic key identities.
final class TerminalControls extends StatelessWidget {
  const TerminalControls({
    super.key,
    required this.modifierLatch,
    required this.zoomPreset,
    required this.geometryLeader,
    required this.keyboardRequestedVisible,
    required this.onModifier,
    required this.onKey,
    required this.onZoom,
    required this.onLead,
    required this.onKeyboard,
    required this.onCopy,
    required this.onPaste,
    required this.onLog,
  });

  final int modifierLatch;
  final TerminalZoomPreset zoomPreset;
  final bool geometryLeader;
  final bool keyboardRequestedVisible;
  final ValueChanged<int> onModifier;
  final ValueChanged<int> onKey;
  final ValueChanged<TerminalZoomPreset> onZoom;
  final VoidCallback onLead;
  final VoidCallback onKeyboard;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff11161b),
    child: SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          _modifier('Ctrl', HowlInput.modifierControl),
          _key('Esc', HowlInput.namedEscape),
          _key('Tab', HowlInput.namedTab),
          _key('←', HowlInput.namedArrowLeft),
          _key('↓', HowlInput.namedArrowDown),
          _key('↑', HowlInput.namedArrowUp),
          _key('→', HowlInput.namedArrowRight),
          _action('Kbd', onKeyboard, latched: keyboardRequestedVisible),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: PopupMenuButton<_ExtraControl>(
                tooltip: 'More terminal actions',
                onSelected: (control) {
                  switch (control) {
                    case _ExtraControl.alt:
                      onModifier(HowlInput.modifierAlt);
                    case _ExtraControl.zoom:
                      onZoom(zoomPreset.next);
                    case _ExtraControl.lead:
                      onLead();
                    case _ExtraControl.copy:
                      onCopy();
                    case _ExtraControl.paste:
                      onPaste();
                    case _ExtraControl.log:
                      onLog();
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<_ExtraControl>>[
                  _menuItem(
                    'Alt',
                    _ExtraControl.alt,
                    checked: modifierLatch & HowlInput.modifierAlt != 0,
                  ),
                  _menuItem(
                    '${zoomPreset.presentation.fontPixels}px',
                    _ExtraControl.zoom,
                  ),
                  _menuItem(
                    'Lead',
                    _ExtraControl.lead,
                    checked: geometryLeader,
                  ),
                  _menuItem('Copy', _ExtraControl.copy),
                  _menuItem('Paste', _ExtraControl.paste),
                  _menuItem('Log', _ExtraControl.log),
                ],
                child: const Material(
                  color: Color(0xff202a32),
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  child: _TerminalControlFace(label: '•••'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  PopupMenuItem<_ExtraControl> _menuItem(
    String label,
    _ExtraControl action, {
    bool checked = false,
  }) => PopupMenuItem<_ExtraControl>(
    value: action,
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 28,
          child: checked ? const Icon(Icons.check, size: 18) : null,
        ),
        Text(label),
      ],
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

  Widget _action(String label, VoidCallback action, {bool? latched}) =>
      Expanded(
        child: _TerminalControlButton(
          label: label,
          latched: latched,
          onTap: action,
        ),
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
          child: _TerminalControlFace(label: label),
        ),
      ),
    ),
  );
}

final class _TerminalControlFace extends StatelessWidget {
  const _TerminalControlFace({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      label,
      maxLines: 1,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Color(0xffd7e0e7),
      ),
    ),
  );
}
