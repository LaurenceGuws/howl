import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server/attachment.dart';
import 'package:howl_flutter/server/browser.dart';
import 'package:howl_flutter/server/change.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/launch.dart';
import 'package:howl_flutter/server/tree.dart';

void main() {
  const receipt =
      '{"schema":"howl.server.launch/v1","server_id":"18446744073709551615",'
      '"session_id":"17","instance_id":"3"}';
  const changeReceipt =
      '{"schema":"howl.server.change/v1","server_id":"18446744073709551615",'
      '"session_id":"17"}';

  test('launch and change receipts preserve exact unsigned identities', () {
    final launched = ServerLaunchReceipt.parse(receipt);
    expect(launched.serverId, '18446744073709551615');
    expect(launched.sessionId, '17');
    expect(launched.instanceId, '3');
    final changed = ServerChangeReceipt.parse(changeReceipt);
    expect(changed.serverId, '18446744073709551615');
    expect(changed.sessionId, '17');
    expect(
      () => ServerChangeReceipt.parse(changeReceipt.replaceFirst('17', '0')),
      throwsA(isA<ServerTreeException>()),
    );
  });

  testWidgets('New Session creates an empty Server-owned Session', (
    tester,
  ) async {
    String? createdName;
    String? serverId;
    var fetched = 0;
    final endpoint = Endpoint.parse('tcp://127.0.0.1:43130');
    final empty = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
      '"tree_revision":"1","sessions":[]}',
    );
    final populated = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
      '"tree_revision":"2","sessions":['
      '{"session_id":"17","name":"mobile","instances":[]}]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: endpoint,
            fetchTree: (_) => ServerTreeRequest.fromFuture(
              Future.value(fetched++ == 0 ? empty : populated),
            ),
            changeServer:
                (target, id, {required kind, sessionId, instanceId, name}) {
                  expect(target.toString(), endpoint.toString());
                  expect(kind, ServerChangeKind.createSession);
                  expect(sessionId, isNull);
                  expect(instanceId, isNull);
                  serverId = id;
                  createdName = name;
                  return ServerChangeRequest.fromFuture(
                    Future.value(ServerChangeReceipt.parse(changeReceipt)),
                  );
                },
            onOpenInstance: (_) => fail('creating a Session must not attach'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('howl-new-session-server')), findsOneWidget);
    expect(find.text('Session name'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(serverId, '18446744073709551615');
    expect(createdName, 'mobile');
    expect(find.text('mobile'), findsOneWidget);
    expect(find.text('No Sessions yet'), findsNothing);
    expect(find.byKey(const Key('howl-new-instance-17')), findsOneWidget);
    expect(fetched, 2);
  });

  testWidgets('New Instance preserves exact Session and Server identity', (
    tester,
  ) async {
    final tree = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
      '"tree_revision":"2","sessions":['
      '{"session_id":"17","name":"work","instances":[]}]}',
    );
    String? selectedSession;
    final pending = Completer<ServerLaunchReceipt>();
    Attachment? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
            initialExpandedSessionId: '17',
            fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(tree)),
            launchTerminal: (_, _, {required sessionId, required shell}) {
              selectedSession = sessionId;
              expect(shell, '/bin/bash');
              return ServerLaunchRequest.fromFuture(pending.future);
            },
            onOpenInstance: (target) => selected = target,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-instance-17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch'));
    await tester.pump();
    expect(selectedSession, '17');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(ServerLaunchReceipt.parse(receipt));
    await tester.pumpAndSettle();
    expect(selected?.sessionId, '17');
    expect(selected?.instanceId, '3');
  });

  testWidgets('mismatched Server launch receipt cannot open Instance', (
    tester,
  ) async {
    final tree = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"9",'
      '"tree_revision":"1","sessions":['
      '{"session_id":"17","name":"work","instances":[]}]}',
    );
    Attachment? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
            fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(tree)),
            launchTerminal: (_, _, {required sessionId, required shell}) =>
                ServerLaunchRequest.fromFuture(
                  Future.value(ServerLaunchReceipt.parse(receipt)),
                ),
            onOpenInstance: (target) => selected = target,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-instance-17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.textContaining('launch_identity'), findsOneWidget);
  });
}
