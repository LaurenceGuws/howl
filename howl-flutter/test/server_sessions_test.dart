import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server_sessions.dart';

void main() {
  test('parses exact native manager roster projection', () {
    final roster = parseHowlServerRoster('''
{"schema":"howl.flutter.server/v1","server_id":"fedcba9876543210","roster_revision":"9","capacity":16,"stopping":false,"sessions":[{"session_id":"17","created_sequence":"1","state":"running","name":"work"},{"session_id":"18","created_sequence":"2","state":"failed","name":"logs","failure":"AcceptFailed"}]}
''');
    expect(roster.serverId, 'fedcba9876543210');
    expect(roster.rosterRevision, 9);
    expect(roster.sessions.length, 2);
    expect(roster.byName('work')!.sessionId, 17);
    expect(roster.byId(18)!.failure, 'AcceptFailed');
    expect(roster.byId(18)!.attachable, isFalse);
  });

  test('rejects duplicate or nonmonotonic roster identity', () {
    expect(
      () => parseHowlServerRoster(
        '{"schema":"howl.flutter.server/v1","server_id":"1","roster_revision":"2","capacity":16,"stopping":false,"sessions":[{"session_id":"1","created_sequence":"2","state":"running","name":"a"},{"session_id":"1","created_sequence":"1","state":"running","name":"b"}]}',
      ),
      throwsA(isA<HowlServerRosterException>()),
    );
  });

  test('failed state requires an exact failure string', () {
    expect(
      () => parseHowlServerRoster(
        '{"schema":"howl.flutter.server/v1","server_id":"1","roster_revision":"2","capacity":16,"stopping":false,"sessions":[{"session_id":"1","created_sequence":"1","state":"failed","name":"a"}]}',
      ),
      throwsA(
        isA<HowlServerRosterException>().having(
          (error) => error.code,
          'code',
          'failure',
        ),
      ),
    );
  });
}
