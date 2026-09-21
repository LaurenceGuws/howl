import 'package:flutter/material.dart';

import 'server_sessions.dart';

final class HowlServerSessionBar extends StatelessWidget {
  const HowlServerSessionBar({
    super.key,
    required this.roster,
    required this.selectedSessionId,
    required this.managerFailure,
    required this.busy,
    required this.onSelect,
    required this.onCreate,
    required this.onClose,
  });

  final HowlServerRoster? roster;
  final int? selectedSessionId;
  final Object? managerFailure;
  final bool busy;
  final ValueChanged<HowlServerSession> onSelect;
  final VoidCallback onCreate;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final currentRoster = roster;
    final sessions = currentRoster?.sessions ?? const <HowlServerSession>[];
    final selected = selectedSessionId == null
        ? null
        : currentRoster?.byId(selectedSessionId!);
    final selectedValue = selected?.sessionId;
    final status = managerFailure != null
        ? 'manager unavailable'
        : currentRoster == null
        ? 'connecting…'
        : currentRoster.stopping
        ? 'server stopping'
        : '${sessions.length}/${currentRoster.capacity} sessions';

    return Material(
      color: const Color(0xff11151a),
      child: SizedBox(
        height: 48,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            const Icon(Icons.terminal, size: 18, color: Color(0xffb8c1cc)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const ValueKey<String>('howl-session-picker'),
                  value: selectedValue,
                  isExpanded: true,
                  hint: Text(
                    sessions.isEmpty ? 'No sessions' : 'Select session',
                    overflow: TextOverflow.ellipsis,
                  ),
                  items: sessions
                      .map(
                        (session) => DropdownMenuItem<int>(
                          value: session.sessionId,
                          enabled: session.attachable,
                          child: Text(
                            session.failure == null
                                ? '${session.name}  ·  ${session.state.name}'
                                : '${session.name}  ·  ${session.state.name}  ·  ${session.failure}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value == null || currentRoster == null) return;
                          final session = currentRoster.byId(value);
                          if (session != null && session.attachable) {
                            onSelect(session);
                          }
                        },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: const TextStyle(fontSize: 11, color: Color(0xff7f8b99)),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const ValueKey<String>('howl-session-create'),
              tooltip: 'Create session',
              onPressed: busy || currentRoster?.stopping == true
                  ? null
                  : onCreate,
              icon: const Icon(Icons.add, size: 19),
            ),
            IconButton(
              key: const ValueKey<String>('howl-session-close'),
              tooltip: 'Close selected session',
              onPressed: busy || selected == null ? null : onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}
