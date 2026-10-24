import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/instance_target.dart';
import 'package:howl_flutter/server_browser.dart';
import 'package:howl_flutter/server_launch.dart';
import 'package:howl_flutter/server_tree.dart';

void main() {
  const receipt =
      '{"schema":"howl.server.launch/v1","server_id":"18446744073709551615",'
      '"session_id":"17","instance_id":"3"}';

  test('launch receipt preserves exact unsigned identities', () {
    final result = HowlServerLaunchReceipt.parse(receipt);
    expect(result.serverId, '18446744073709551615');
    expect(result.sessionId, '17');
    expect(result.instanceId, '3');
    expect(
      () => HowlServerLaunchReceipt.parse(
        receipt.replaceFirst('18446744073709551615', '0'),
      ),
      throwsA(isA<HowlServerTreeException>()),
    );
  });

  testWidgets('empty Server can create and open its first terminal', (
    tester,
  ) async {
    ManagedHowlInstanceTarget? selected;
    String? name;
    String? shellSeen;
    String? serverId;
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
      '"tree_revision":"1","sessions":[]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HowlServerBrowser(
          endpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(tree)),
          launchTerminal:
              (endpoint, id, {sessionId, sessionName, required shell}) {
                serverId = id;
                name = sessionName;
                shellSeen = shell;
                expect(sessionId, isNull);
                return HowlServerLaunchRequest.fromFuture(
                  Future.value(HowlServerLaunchReceipt.parse(receipt)),
                );
              },
          onOpenTarget: (target) => selected = target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create first terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Session name'), findsOneWidget);
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(serverId, '18446744073709551615');
    expect(name, 'mobile');
    expect(shellSeen, '/bin/bash');
    expect(selected?.sessionId, '17');
    expect(selected?.instanceId, '3');
  });

  testWidgets('new Instance keeps the selected Session and Server identity', (
    tester,
  ) async {
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
      '"tree_revision":"2","sessions":['
      '{"session_id":"17","name":"work","instances":[]}]}',
    );
    String? selectedSession;
    final pending = Completer<HowlServerLaunchReceipt>();
    ManagedHowlInstanceTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: HowlServerBrowser(
          endpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(tree)),
          launchTerminal: (_, _, {sessionId, sessionName, required shell}) {
            selectedSession = sessionId;
            expect(sessionName, isNull);
            return HowlServerLaunchRequest.fromFuture(pending.future);
          },
          onOpenTarget: (target) => selected = target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New terminal in work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch'));
    await tester.pump();
    expect(selectedSession, '17');
    expect(find.text('Launching...'), findsOneWidget);
    pending.complete(HowlServerLaunchReceipt.parse(receipt));
    await tester.pumpAndSettle();
    expect(selected?.sessionId, '17');
  });

  testWidgets('a mismatched Server launch receipt cannot open a terminal', (
    tester,
  ) async {
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"9",'
      '"tree_revision":"1","sessions":[]}',
    );
    ManagedHowlInstanceTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: HowlServerBrowser(
          endpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(tree)),
          launchTerminal: (_, _, {sessionId, sessionName, required shell}) =>
              HowlServerLaunchRequest.fromFuture(
                Future.value(HowlServerLaunchReceipt.parse(receipt)),
              ),
          onOpenTarget: (target) => selected = target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create first terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.textContaining('launch_server_identity'), findsOneWidget);
  });
}
