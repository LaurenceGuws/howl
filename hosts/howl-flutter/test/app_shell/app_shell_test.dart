import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/app_shell/app_shell.dart';
import 'package:howl_flutter/server/attachment.dart';
import 'package:howl_flutter/server/connections.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/tree.dart';

final class _MemoryStore implements ServerConnectionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String encoded) async => value = encoded;
}

final class _ThrowingReadStore implements ServerConnectionStore {
  @override
  Future<String?> read() async => throw StateError('read failed');

  @override
  Future<void> write(String encoded) async =>
      throw StateError('write forbidden');
}

final Endpoint _endpoint = Endpoint.parse('tcp://127.0.0.1:43130');

ServerTree _tree({bool bothRunning = false}) {
  final firstState = bothRunning ? 'running' : 'exited';
  return ServerTree.parse(
    '{"schema":"howl.server.tree/v1","server_id":"91",'
    '"tree_revision":"4","sessions":['
    '{"session_id":"7","name":"work","instances":['
    '{"instance_id":"1","state":"$firstState"},'
    '{"instance_id":"2","state":"running"}]}]}',
  );
}

Future<ServerConnections> _savedServer(_MemoryStore store) async {
  final connections = ServerConnections(store);
  await connections.initialize();
  await connections.upsert(
    ServerConnection(label: 'Home', endpoint: _endpoint.toString()),
  );
  await connections.select(_endpoint.toString());
  return connections;
}

Future<void> _selectWork(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('howl-shell-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('howl-session-7')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('terminal has no Flutter tab strip or double-spent safe area', (
    tester,
  ) async {
    double? topInset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 48),
            viewPadding: EdgeInsets.only(top: 48),
          ),
          child: AppShell(
            connections: ServerConnections(_MemoryStore()),
            initialAttachment: Attachment(
              serverEndpoint: _endpoint,
              serverId: '91',
              sessionId: '7',
              instanceId: '2',
            ),
            terminalBuilder: (context, _, _, _) {
              topInset = MediaQuery.viewPaddingOf(context).top;
              return const Text('terminal');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(topInset, 48);
    expect(find.text('terminal'), findsOneWidget);
    expect(find.byKey(const Key('howl-tab-actions')), findsNothing);
    expect(find.byKey(const Key('howl-tab-browse')), findsNothing);
  });

  testWidgets(
    'Settings selects Server, drawer selects Session, chips open Instance',
    (tester) async {
      final connections = ServerConnections(_MemoryStore());
      VoidCallback? browseInstances;
      var fetches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            connections: connections,
            fetchTree: (_) {
              fetches++;
              return ServerTreeRequest.fromFuture(Future.value(_tree()));
            },
            terminalBuilder: (_, attachment, _, browse) {
              browseInstances = browse;
              return Text(
                'terminal ${attachment.instanceId}',
                key: const Key('fake-terminal'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Server configured'), findsOneWidget);

      await tester.tap(find.byKey(const Key('howl-shell-configure')));
      await tester.pumpAndSettle();
      expect(find.text('Server Settings'), findsOneWidget);
      await tester.tap(find.byKey(const Key('howl-shell-add-server')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('howl-server-label')),
        'Home',
      );
      await tester.enterText(
        find.byKey(const Key('howl-server-endpoint')),
        _endpoint.toString(),
      );
      await tester.tap(find.byKey(const Key('howl-server-save')));
      await tester.pumpAndSettle();
      expect(connections.servers.single.label, 'Home');
      await tester.tap(
        find.byKey(Key('howl-shell-server-${_endpoint.toString()}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose a Session'), findsOneWidget);

      await _selectWork(tester);
      expect(find.text('Instance 1'), findsOneWidget);
      expect(find.text('Instance 2'), findsOneWidget);
      expect(find.text('exited'), findsOneWidget);
      expect(
        tester
            .widget<ActionChip>(find.byKey(const Key('howl-instance-7-1')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('fake-terminal')), findsNothing);
      await tester.tap(find.byKey(const Key('howl-instance-7-2')));
      await tester.pumpAndSettle();
      expect(find.text('terminal 2'), findsOneWidget);
      expect(find.byKey(const Key('howl-tab-actions')), findsNothing);
      expect(browseInstances, isNotNull);

      browseInstances!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-terminal')), findsNothing);
      expect(find.text('Instance 2'), findsOneWidget);
      expect(fetches, greaterThanOrEqualTo(2));
    },
  );

  testWidgets('Instance switching uses fresh Server chips, not local tabs', (
    tester,
  ) async {
    final connections = await _savedServer(_MemoryStore());
    VoidCallback? browse;
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          connections: connections,
          fetchTree: (_) => ServerTreeRequest.fromFuture(
            Future.value(_tree(bothRunning: true)),
          ),
          terminalBuilder: (_, attachment, _, back) {
            opened.add(attachment.instanceId);
            browse = back;
            return Text('active ${attachment.instanceId}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectWork(tester);
    await tester.tap(find.byKey(const Key('howl-instance-7-1')));
    await tester.pumpAndSettle();
    expect(find.text('active 1'), findsOneWidget);
    browse!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-instance-7-2')));
    await tester.pumpAndSettle();
    expect(find.text('active 2'), findsOneWidget);
    expect(opened, containsAllInOrder(<String>['1', '2']));
    expect(find.byKey(const Key('howl-tab-actions')), findsNothing);
  });

  testWidgets(
    'relaunch refreshes Server, not a saved Session or Instance tab',
    (tester) async {
      final store = _MemoryStore();
      final initialConnections = await _savedServer(store);
      var requests = 0;
      ServerTreeRequest fetch(Endpoint _) {
        requests++;
        return ServerTreeRequest.fromFuture(Future.value(_tree()));
      }

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('first-launch'),
          home: AppShell(
            connections: initialConnections,
            fetchTree: fetch,
            terminalBuilder: (_, attachment, _, _) =>
                Text('active ${attachment.instanceId}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectWork(tester);
      await tester.tap(find.byKey(const Key('howl-instance-7-2')));
      await tester.pumpAndSettle();
      expect(find.text('active 2'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('second-launch'),
          home: AppShell(
            connections: ServerConnections(store),
            fetchTree: fetch,
            terminalBuilder: (_, attachment, _, _) =>
                Text('active ${attachment.instanceId}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('Choose a Session'), findsOneWidget);
      expect(find.text('active 2'), findsNothing);
      await _selectWork(tester);
      expect(find.text('Instance 2'), findsOneWidget);
    },
  );

  testWidgets('editing the selected Server follows its replacement endpoint', (
    tester,
  ) async {
    final connections = await _savedServer(_MemoryStore());
    final fetched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          connections: connections,
          fetchTree: (endpoint) {
            fetched.add(endpoint.toString());
            return ServerTreeRequest.fromFuture(Future.value(_tree()));
          },
          terminalBuilder: (_, _, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final replacement = ServerConnection(
      label: 'Home',
      endpoint: 'tcp://127.0.0.1:43132',
    );
    await connections.upsert(
      replacement,
      replacingEndpoint: _endpoint.toString(),
    );
    await tester.pumpAndSettle();
    expect(connections.selectedEndpoint, replacement.endpoint);
    expect(fetched.last, replacement.endpoint);
    expect(find.text('Choose a Session'), findsOneWidget);
  });

  testWidgets('removing selected Server detaches its visible Instance', (
    tester,
  ) async {
    final connections = await _savedServer(_MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          connections: connections,
          fetchTree: (_) => ServerTreeRequest.fromFuture(Future.value(_tree())),
          terminalBuilder: (_, attachment, _, _) => Text(
            'active ${attachment.instanceId}',
            key: const Key('terminal-under-removal'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectWork(tester);
    await tester.tap(find.byKey(const Key('howl-instance-7-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-under-removal')), findsOneWidget);
    await connections.remove(_endpoint.toString());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-under-removal')), findsNothing);
    expect(find.text('No Server configured'), findsOneWidget);
  });

  testWidgets('stale attachment returns to freshly fetched Server state', (
    tester,
  ) async {
    VoidCallback? stale;
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          connections: ServerConnections(_MemoryStore()),
          initialAttachment: Attachment(
            serverEndpoint: _endpoint,
            serverId: '91',
            sessionId: '7',
            instanceId: '2',
          ),
          fetchTree: (_) {
            requests++;
            return ServerTreeRequest.fromFuture(Future.value(_tree()));
          },
          terminalBuilder: (_, attachment, onStale, _) {
            stale = onStale;
            return Text('active ${attachment.instanceId}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('active 2'), findsOneWidget);
    stale!();
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('active 2'), findsNothing);
    expect(find.text('Instance 2'), findsOneWidget);
  });

  testWidgets('explicit attachment survives a failed saved Server read', (
    tester,
  ) async {
    final connections = ServerConnections(_ThrowingReadStore());
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          connections: connections,
          initialAttachment: Attachment(
            serverEndpoint: _endpoint,
            serverId: '91',
            sessionId: '7',
            instanceId: '2',
          ),
          terminalBuilder: (_, attachment, _, _) => Text(
            attachment.endpointText,
            key: const Key('explicit-terminal'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explicit-terminal')), findsOneWidget);
    expect(connections.loadError, isNotNull);
  });
}
