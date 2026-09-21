import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server_session_bar.dart';
import 'package:howl_flutter/server_sessions.dart';

void main() {
  const roster = HowlServerRoster(
    serverId: '1',
    rosterRevision: 3,
    capacity: 16,
    stopping: false,
    sessions: <HowlServerSession>[
      HowlServerSession(
        sessionId: 1,
        createdSequence: 1,
        state: HowlServerSessionState.running,
        name: 'work',
      ),
      HowlServerSession(
        sessionId: 2,
        createdSequence: 2,
        state: HowlServerSessionState.failed,
        name: 'logs',
        failure: 'AcceptFailed',
      ),
    ],
  );

  testWidgets('shows current session and lifecycle controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HowlServerSessionBar(
            roster: roster,
            selectedSessionId: 1,
            managerFailure: null,
            busy: false,
            onSelect: (_) {},
            onCreate: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('work  ·  running'), findsOneWidget);
    expect(find.text('2/16 sessions'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('howl-session-create')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('howl-session-close')),
      findsOneWidget,
    );
  });
}
