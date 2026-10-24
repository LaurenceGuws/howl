import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/attachment.dart';
import 'package:howl_flutter/server/browser.dart';
import 'package:howl_flutter/server/change.dart';
import 'package:howl_flutter/server/connections.dart';
import 'package:howl_flutter/server/launch.dart';
import 'package:howl_flutter/server/tree.dart';

void main() {
  testWidgets('browser shows Session lineage and only opens running Instance', (
    tester,
  ) async {
    Attachment? selected;
    final tree = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615","tree_revision":"4","sessions":['
      '{"session_id":"7","name":"work","instances":['
      '{"instance_id":"1","state":"exited"},'
      '{"instance_id":"2","state":"running"}]}]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          initialExpandedSessionId: '7',
          fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(tree)),
          onOpenInstance: (target) => selected = target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('exited'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);

    expect(
      tester.widget<ListTile>(find.byKey(const Key('howl-instance-7-1'))).onTap,
      isNull,
    );
    expect(selected, isNull);

    await tester.tap(find.byKey(const Key('howl-instance-7-2')));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(selected!.serverId, '18446744073709551615');
    expect(selected!.nativeServerId, -1);
    expect(selected!.sessionId, '7');
    expect(selected!.instanceId, '2');
  });

  testWidgets(
    'row selection pins its rendered Server incarnation between frames',
    (tester) async {
      ServerTree tree(String serverId, String name) => ServerTree.parse(
        '{"schema":"howl.server.tree/v1","server_id":"$serverId","tree_revision":"4","sessions":['
        '{"session_id":"7","name":"$name","instances":['
        '{"instance_id":"3","state":"running"}]}]}',
      );
      final refresh = Completer<ServerTree>();
      var calls = 0;
      Attachment? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:1'),
            initialExpandedSessionId: '7',
            fetchTree: (_) => ServerTreeRequest.fromFuture(
              calls++ == 0
                  ? Future.value(tree('91', 'OLD_OCCURRENCE'))
                  : refresh.future,
            ),
            onOpenInstance: (target) => selected = target,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('OLD_OCCURRENCE'), findsOneWidget);
      expect(find.text('Instance 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();

      // Complete discovery without drawing a frame: the old row is still visible.
      refresh.complete(tree('92', 'NEW_OCCURRENCE'));
      await tester.idle();
      expect(find.text('OLD_OCCURRENCE'), findsOneWidget);
      expect(find.text('NEW_OCCURRENCE'), findsNothing);
      await tester.tap(find.byKey(const Key('howl-instance-7-3')));
      expect(selected, isNotNull);
      expect(selected!.serverId, '91');
      expect(selected!.sessionId, '7');
      expect(selected!.instanceId, '3');

      selected = null;
      await tester.pumpAndSettle();
      expect(find.text('OLD_OCCURRENCE'), findsNothing);
      expect(find.text('NEW_OCCURRENCE'), findsOneWidget);
      await tester.tap(find.byKey(const Key('howl-instance-7-3')));
      expect(selected, isNotNull);
      expect(selected!.serverId, '92');
      expect(selected!.sessionId, '7');
      expect(selected!.instanceId, '3');
      await tester.pumpAndSettle();
    },
  );

  testWidgets('disposing browser cancels its pending tree request once', (
    tester,
  ) async {
    final pending = Completer<ServerTree>();
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) => ServerTreeRequest(
            pending.future,
            onCancel: () {
              cancels += 1;
              if (!pending.isCompleted) {
                pending.completeError(StateError('fixture canceled'));
              }
            },
          ),
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancels, 1);
  });

  test('tree request cancellation is idempotent', () async {
    final completer = Completer<ServerTree>();
    var cancels = 0;
    final request = ServerTreeRequest(
      completer.future,
      onCancel: () => cancels += 1,
    );
    request.cancel();
    request.cancel();
    expect(cancels, 1);
  });

  testWidgets('returning to the app refreshes its Server browser', (
    tester,
  ) async {
    var requests = 0;
    final tree = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"9",'
      '"tree_revision":"1","sessions":[]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) {
            requests += 1;
            return ServerTreeRequest.fromFuture(Future.value(tree));
          },
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  testWidgets('new Session suggests an unused mobile name', (tester) async {
    final tree = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"9",'
      '"tree_revision":"1","sessions":['
      '{"session_id":"1","name":"mobile","instances":[]},'
      '{"session_id":"2","name":"mobile-3","instances":[]},'
      '{"session_id":"3","name":"work","instances":[]}]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(tree)),
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Session'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Session name'),
    );
    expect(field.controller!.text, 'mobile-2');
    expect(find.byKey(const Key('howl-new-session-server')), findsOneWidget);
  });

  testWidgets('New Session targets the selected configured Server', (
    tester,
  ) async {
    final home = Endpoint.parse('tcp://127.0.0.1:43130');
    final remote = Endpoint.parse('tcp://127.0.0.1:43131');
    final requests = <String>[];
    String? selectedServer;
    String? mutatedServer;
    String? mutatedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: home,
            availableServers: <ServerConnection>[
              ServerConnection(label: 'Home', endpoint: home.toString()),
              ServerConnection(label: 'Remote', endpoint: remote.toString()),
            ],
            fetchTree: (endpoint) {
              requests.add(endpoint.toString());
              final id = endpoint.toString() == home.toString() ? '91' : '92';
              return ServerTreeRequest.fromFuture(
                Future.value(
                  ServerTree.parse(
                    '{"schema":"howl.server.tree/v1","server_id":"$id",'
                    '"tree_revision":"1","sessions":[]}',
                  ),
                ),
              );
            },
            changeServer:
                (endpoint, id, {required kind, sessionId, instanceId, name}) {
                  mutatedServer = endpoint.toString();
                  mutatedId = id;
                  expect(kind, ServerChangeKind.createSession);
                  expect(name, 'mobile');
                  return ServerChangeRequest.fromFuture(
                    Future.value(
                      ServerChangeReceipt.parse(
                        '{"schema":"howl.server.change/v1","server_id":"92","session_id":"3"}',
                      ),
                    ),
                  );
                },
            onChooseServer: (server) async {
              selectedServer = server.endpoint;
              return true;
            },
            onOpenInstance: (_) =>
                fail('Session create must not launch an Instance'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-session-server')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(requests, <String>[home.toString(), remote.toString()]);
    expect(mutatedServer, remote.toString());
    expect(mutatedId, '92');
    expect(selectedServer, remote.toString());
  });

  testWidgets('new Instance refreshes its Session before reopening the drawer', (
    tester,
  ) async {
    final before = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91",'
      '"tree_revision":"2","sessions":['
      '{"session_id":"7","name":"work","instances":[]}]}',
    );
    final after = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91",'
      '"tree_revision":"3","sessions":['
      '{"session_id":"7","name":"work","instances":['
      '{"instance_id":"8","state":"running"}]}]}',
    );
    var fetches = 0;
    Attachment? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
            fetchTree: (_) => ServerTreeRequest.fromFuture(
              Future.value(fetches++ == 0 ? before : after),
            ),
            launchTerminal:
                (endpoint, serverId, {required sessionId, required shell}) {
                  expect(serverId, '91');
                  expect(sessionId, '7');
                  expect(shell, '/bin/bash');
                  return ServerLaunchRequest.fromFuture(
                    Future.value(
                      ServerLaunchReceipt.parse(
                        '{"schema":"howl.server.launch/v1",'
                        '"server_id":"91","session_id":"7","instance_id":"8"}',
                      ),
                    ),
                  );
                },
            onOpenInstance: (target) => opened = target,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-new-instance-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(opened?.instanceId, '8');
    expect(fetches, 2);
    expect(find.text('Instance 8'), findsOneWidget);
  });

  testWidgets('close Instance requires confirmation and refreshes Server', (
    tester,
  ) async {
    final before = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91","tree_revision":"2",'
      '"sessions":[{"session_id":"7","name":"work","instances":['
      '{"instance_id":"2","state":"running"}]}]}',
    );
    final after = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91","tree_revision":"3",'
      '"sessions":[{"session_id":"7","name":"work","instances":[]}]}',
    );
    var fetches = 0;
    var closes = 0;
    String? closedInstance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
            fetchTree: (_) => ServerTreeRequest.fromFuture(
              Future.value(fetches++ == 0 ? before : after),
            ),
            changeServer:
                (_, id, {required kind, sessionId, instanceId, name}) {
                  closes++;
                  expect(id, '91');
                  expect(kind, ServerChangeKind.closeInstance);
                  expect(sessionId, '7');
                  expect(instanceId, '2');
                  return ServerChangeRequest.fromFuture(
                    Future.value(
                      ServerChangeReceipt.parse(
                        '{"schema":"howl.server.change/v1","server_id":"91","session_id":"7"}',
                      ),
                    ),
                  );
                },
            onClosedInstance: (sessionId, instanceId) =>
                closedInstance = instanceId,
            onOpenInstance: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Instance options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Instance').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closes, 0);
    await tester.tap(find.byTooltip('Instance options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Instance').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Instance').last);
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(closedInstance, '2');
    expect(find.text('Instance 2'), findsNothing);
    expect(fetches, 2);
  });

  testWidgets('closing a Session closes its children only after confirmation', (
    tester,
  ) async {
    final before = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91","tree_revision":"2",'
      '"sessions":[{"session_id":"7","name":"work","instances":['
      '{"instance_id":"2","state":"running"},'
      '{"instance_id":"3","state":"exited"}]}]}',
    );
    final after = ServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"91","tree_revision":"3",'
      '"sessions":[]}',
    );
    var fetches = 0;
    var closes = 0;
    String? closedSession;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerBrowser(
            endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
            fetchTree: (_) => ServerTreeRequest.fromFuture(
              Future.value(fetches++ == 0 ? before : after),
            ),
            changeServer:
                (_, id, {required kind, sessionId, instanceId, name}) {
                  closes++;
                  expect(id, '91');
                  expect(kind, ServerChangeKind.closeSession);
                  expect(sessionId, '7');
                  expect(instanceId, isNull);
                  return ServerChangeRequest.fromFuture(
                    Future.value(
                      ServerChangeReceipt.parse(
                        '{"schema":"howl.server.change/v1","server_id":"91","session_id":"7"}',
                      ),
                    ),
                  );
                },
            onClosedSession: (sessionId) => closedSession = sessionId,
            onOpenInstance: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Session options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Session').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('all 2 Instances'), findsOneWidget);
    expect(closes, 0);
    await tester.tap(find.text('Close Session').last);
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(closedSession, '7');
    expect(find.byKey(const Key('howl-session-7')), findsNothing);
    expect(fetches, 2);
  });

  testWidgets('synchronous native request failure never strands loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) => throw StateError('native initialization failed'),
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.textContaining('native initialization failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('unresponsive native request has a finite UI deadline', (
    tester,
  ) async {
    final pending = Completer<ServerTree>();
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) =>
              ServerTreeRequest(pending.future, onCancel: () => cancels += 1),
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Connecting to Server'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 19));
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.textContaining('server_tree_timeout'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('operator can cancel an unresponsive Server connection', (
    tester,
  ) async {
    final pending = Completer<ServerTree>();
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerBrowser(
          endpoint: Endpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) => ServerTreeRequest(
            pending.future,
            onCancel: () {
              cancels += 1;
              pending.completeError(StateError('native canceled'));
            },
          ),
          onOpenInstance: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.textContaining('server_tree_canceled'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
