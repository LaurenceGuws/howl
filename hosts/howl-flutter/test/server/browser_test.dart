import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/attachment.dart';
import 'package:howl_flutter/server/browser.dart';
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
          selectedSessionId: '7',
          fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(tree)),
          onOpenInstance: (target) => selected = target,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Instances'), findsOneWidget);
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('exited'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);

    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('howl-instance-7-1')))
          .onPressed,
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
            selectedSessionId: '7',
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
    await tester.tap(find.byTooltip('New Session + terminal'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Session name'),
    );
    expect(field.controller!.text, 'mobile-2');
    final shell = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Shell on Server'),
    );
    expect(shell.controller!.text, '/bin/bash');
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
