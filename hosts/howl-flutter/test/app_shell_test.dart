import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/app_shell.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/instance_target.dart';
import 'package:howl_flutter/server_connections.dart';
import 'package:howl_flutter/server_tree.dart';

final class _MemoryStore implements HowlServerConnectionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String encoded) async => value = encoded;
}

final class _ThrowingReadStore implements HowlServerConnectionStore {
  @override
  Future<String?> read() async => throw StateError('read failed');

  @override
  Future<void> write(String encoded) async =>
      throw StateError('write forbidden');
}

HowlServerTree _tree() => HowlServerTree.parse(
  '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
  '"tree_revision":"4","sessions":['
  '{"session_id":"7","name":"work","instances":['
  '{"instance_id":"1","state":"exited"},'
  '{"instance_id":"2","state":"running"}]}]}',
);

void main() {
  testWidgets('terminal tab strip consumes the top safe area exactly once', (
    tester,
  ) async {
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
      serverId: '99',
      sessionId: '7',
      instanceId: '1',
    );
    double? terminalTopInset;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: 48),
          viewPadding: EdgeInsets.only(top: 48),
        ),
          child: HowlAppShell(
            initialInstanceTarget: target,
            connections: HowlServerConnections(_MemoryStore()),
            terminalBuilder: (_, _, _, _) => Builder(
              builder: (context) {
                terminalTopInset = MediaQuery.viewPaddingOf(context).top;
                return const Text('terminal');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(terminalTopInset, 0);
    final menu = tester.getTopLeft(find.byKey(const Key('howl-shell-menu')));
    expect(menu.dy, greaterThanOrEqualTo(48));
  });

  testWidgets(
    'tabs follow VT titles, allow overrides, and close only attachments',
    (tester) async {
      final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:43130');
      final first = ManagedHowlInstanceTarget(
        serverEndpoint: endpoint,
        serverId: '18446744073709551615',
        sessionId: '7',
        instanceId: '2',
      );
      final reported = <String, ValueChanged<String?>>{};
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            connections: HowlServerConnections(_MemoryStore()),
            initialInstanceTarget: first,
            fetchTree: (_) =>
                HowlServerTreeRequest.fromFuture(Future.value(_tree())),
            terminalBuilder: (_, target, _, onTitleChanged) {
              reported[target.instanceId] = onTitleChanged;
              selected.add(target.instanceId);
              return const SizedBox(key: Key('fake-terminal'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Instance 2'), findsOneWidget);

      reported['2']!('rain \u001b[31m\u202ex');
      await tester.pump();
      expect(find.text('rain [31mx'), findsOneWidget);
      await tester.tap(find.byKey(const Key('howl-tab-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename tab'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('howl-tab-name')), 'My TUI');
      await tester.tap(find.byKey(const Key('howl-tab-save')));
      await tester.pumpAndSettle();
      reported['2']!('a new program');
      await tester.pump();
      expect(find.text('My TUI'), findsOneWidget);
      expect(find.text('a new program'), findsNothing);

      await tester.tap(find.byKey(const Key('howl-tab-browse')));
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
      await tester.tap(find.text('Instance 1'));
      await tester.pump();
      expect(find.byKey(const Key('fake-terminal')), findsNothing);
      await tester.tap(find.text('Instance 2'));
      await tester.pumpAndSettle();
      expect(selected.last, '2');
      expect(find.text('My TUI'), findsOneWidget);

      await tester.tap(find.byKey(const Key('howl-tab-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename tab'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('howl-tab-name')), '');
      await tester.tap(find.byKey(const Key('howl-tab-save')));
      await tester.pumpAndSettle();
      expect(find.text('a new program'), findsOneWidget);

      await tester.tap(find.byKey(const Key('howl-tab-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close tab'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-terminal')), findsNothing);
      expect(find.text('work'), findsOneWidget);
      expect(find.text('Instance 2'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop shell opens one Local target without inventing a Server route',
    (tester) async {
      final connections = HowlServerConnections(_MemoryStore());
      final builtTargets = <HowlInstanceTarget>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            localEnabled: true,
            connections: connections,
            terminalBuilder: (_, target, _, _) {
              builtTargets.add(target);
              return Text(
                target.diagnosticLabel,
                key: const Key('local-terminal'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open Howl'), findsOneWidget);
      expect(find.byKey(const Key('howl-shell-local')), findsOneWidget);
      expect(connections.selectedEndpoint, isNull);

      await tester.tap(find.byKey(const Key('howl-shell-local')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-terminal')), findsOneWidget);
      expect(find.text('local instance'), findsOneWidget);
      expect(builtTargets.single, isA<LocalHowlInstanceTarget>());
      expect(connections.selectedEndpoint, isNull);

      await tester.tap(find.byKey(const Key('howl-shell-menu')));
      await tester.pumpAndSettle();
      final localTile = tester.widget<ListTile>(
        find.byKey(const Key('howl-shell-local-drawer')),
      );
      expect(localTile.selected, isTrue);
    },
  );

  testWidgets(
    'route-less shell uses button-only drawer and opens managed Instance',
    (tester) async {
      final connections = HowlServerConnections(_MemoryStore());
      final builtTargets = <HowlInstanceTarget>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: false),
          home: HowlAppShell(
            connections: connections,
            fetchTree: (_) =>
                HowlServerTreeRequest.fromFuture(Future.value(_tree())),
            terminalBuilder: (context, target, _, _) {
              builtTargets.add(target);
              return Text(
                'terminal ${target.sessionId}/${target.instanceId}',
                key: const Key('fake-terminal'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Server configured'), findsOneWidget);
      expect(find.byKey(const Key('howl-shell-menu')), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawerEnableOpenDragGesture, isFalse);

      await tester.tap(find.byKey(const Key('howl-shell-configure')));
      await tester.pumpAndSettle();
      expect(find.text('Connections'), findsOneWidget);
      await tester.tap(find.byKey(const Key('howl-shell-add-server')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('howl-server-label')),
        'Home',
      );
      await tester.enterText(
        find.byKey(const Key('howl-server-endpoint')),
        'tcp://127.0.0.1:43130',
      );
      await tester.tap(find.byKey(const Key('howl-server-save')));
      await tester.pumpAndSettle();
      expect(connections.servers.single.label, 'Home');

      await tester.tap(
        find.byKey(const Key('howl-shell-server-tcp://127.0.0.1:43130')),
      );
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
      expect(find.text('Instance 1'), findsOneWidget);
      expect(find.text('Instance 2'), findsOneWidget);

      await tester.tap(find.text('Instance 1'));
      await tester.pump();
      expect(find.byKey(const Key('fake-terminal')), findsNothing);

      await tester.tap(find.text('Instance 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-terminal')), findsOneWidget);
      expect(find.text('terminal 7/2'), findsOneWidget);
      expect(find.byKey(const Key('howl-shell-menu')), findsOneWidget);
      expect(builtTargets.single, isA<ManagedHowlInstanceTarget>());

      await tester.tap(find.byKey(const Key('howl-shell-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('howl-shell-back-server')), findsOneWidget);
      await tester.tap(find.byKey(const Key('howl-shell-back-server')));
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
      expect(find.byKey(const Key('fake-terminal')), findsNothing);
    },
  );

  testWidgets(
    'saved selected Server becomes startup surface without launch route',
    (tester) async {
      final store = _MemoryStore();
      final connections = HowlServerConnections(store);
      await connections.initialize();
      final server = HowlServerConnection(
        label: 'Home',
        endpoint: 'tcp://127.0.0.1:43130',
      );
      await connections.upsert(server);
      await connections.select(server.endpoint);

      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            connections: connections,
            fetchTree: (_) =>
                HowlServerTreeRequest.fromFuture(Future.value(_tree())),
            terminalBuilder: (_, target, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
    },
  );

  testWidgets(
    'exact Instance launch stays terminal-first with shell navigation',
    (tester) async {
      final target = ManagedHowlInstanceTarget(
        serverEndpoint: HowlEndpoint.parse('tcp://127.0.0.1:43127'),
        serverId: '91',
        sessionId: '7',
        instanceId: '3',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            connections: HowlServerConnections(_MemoryStore()),
            initialInstanceTarget: target,
            terminalBuilder: (_, value, _, _) =>
                Text(value.endpointText, key: const Key('selected-terminal')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-terminal')), findsOneWidget);
      expect(find.byKey(const Key('howl-shell-menu')), findsOneWidget);
    },
  );

  testWidgets(
    'editing selected saved Server follows the replacement endpoint',
    (tester) async {
      final store = _MemoryStore();
      final connections = HowlServerConnections(store);
      await connections.initialize();
      final oldServer = HowlServerConnection(
        label: 'Home',
        endpoint: 'tcp://127.0.0.1:43130',
      );
      await connections.upsert(oldServer);
      await connections.select(oldServer.endpoint);

      final fetched = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            connections: connections,
            fetchTree: (endpoint) {
              fetched.add(endpoint.toString());
              return HowlServerTreeRequest.fromFuture(Future.value(_tree()));
            },
            terminalBuilder: (_, _, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fetched.last, oldServer.endpoint);

      final moved = HowlServerConnection(
        label: 'Home',
        endpoint: 'tcp://127.0.0.1:43132',
      );
      await connections.upsert(moved, replacingEndpoint: oldServer.endpoint);
      await tester.pumpAndSettle();

      expect(connections.selectedEndpoint, moved.endpoint);
      expect(fetched.last, moved.endpoint);
      expect(find.text('work'), findsOneWidget);
    },
  );

  testWidgets('removing selected saved Server ejects managed terminal', (
    tester,
  ) async {
    final store = _MemoryStore();
    final connections = HowlServerConnections(store);
    await connections.initialize();
    final server = HowlServerConnection(
      label: 'Home',
      endpoint: 'tcp://127.0.0.1:43130',
    );
    await connections.upsert(server);
    await connections.select(server.endpoint);

    await tester.pumpWidget(
      MaterialApp(
        home: HowlAppShell(
          connections: connections,
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(_tree())),
          terminalBuilder: (_, target, _, _) => Text(
            'terminal ${target.sessionId}/${target.instanceId}',
            key: const Key('managed-terminal-under-removal'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instance 2'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('managed-terminal-under-removal')),
      findsOneWidget,
    );

    await connections.remove(server.endpoint);
    await tester.pumpAndSettle();

    expect(connections.selectedEndpoint, isNull);
    expect(
      find.byKey(const Key('managed-terminal-under-removal')),
      findsNothing,
    );
    expect(find.text('No Server configured'), findsOneWidget);
    expect(find.byKey(const Key('howl-shell-menu')), findsOneWidget);
  });

  testWidgets('two client tabs switch Instances without closing either', (
    tester,
  ) async {
    final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:43130');
    final first = ManagedHowlInstanceTarget(
      serverEndpoint: endpoint,
      serverId: '99',
      sessionId: '7',
      instanceId: '1',
    );
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"99",'
      '"tree_revision":"3","sessions":['
      '{"session_id":"7","name":"work","instances":['
      '{"instance_id":"1","state":"running"},'
      '{"instance_id":"2","state":"running"}]}]}',
    );
    final visited = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HowlAppShell(
          connections: HowlServerConnections(_MemoryStore()),
          initialInstanceTarget: first,
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(tree)),
          terminalBuilder: (_, target, _, _) {
            visited.add(target.instanceId);
            return Text('active ${target.instanceId}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howl-tab-browse')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instance 2'));
    await tester.pumpAndSettle();
    expect(find.text('active 2'), findsOneWidget);
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);

    await tester.tap(find.byKey(Key('howl-tab-${first.diagnosticLabel}')));
    await tester.pumpAndSettle();
    expect(find.text('active 1'), findsOneWidget);
    expect(visited.last, '1');

    await tester.tap(find.byKey(const Key('howl-tab-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close tab'));
    await tester.pumpAndSettle();
    expect(find.text('active 2'), findsOneWidget);
    expect(visited.last, '2');
    await tester.tap(find.byKey(const Key('howl-tab-browse')));
    await tester.pumpAndSettle();
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
  });

  testWidgets('transient Server launch ignores saved selection mutations', (
    tester,
  ) async {
    final store = _MemoryStore();
    final connections = HowlServerConnections(store);
    await connections.initialize();
    final saved = HowlServerConnection(
      label: 'Saved',
      endpoint: 'tcp://127.0.0.1:43130',
    );
    final other = HowlServerConnection(
      label: 'Other',
      endpoint: 'tcp://127.0.0.1:43131',
    );
    await connections.upsert(saved);
    await connections.upsert(other);
    await connections.select(saved.endpoint);

    final transient = HowlEndpoint.parse('tcp://127.0.0.1:43999');
    final fetched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HowlAppShell(
          connections: connections,
          initialServerEndpoint: transient,
          fetchTree: (endpoint) {
            fetched.add(endpoint.toString());
            return HowlServerTreeRequest.fromFuture(Future.value(_tree()));
          },
          terminalBuilder: (_, _, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetched.last, transient.toString());

    await connections.select(other.endpoint);
    await tester.pumpAndSettle();

    expect(connections.selectedEndpoint, other.endpoint);
    expect(fetched.last, transient.toString());
    expect(find.text('work'), findsOneWidget);
  });

  testWidgets('stale managed terminal returns to its Server browser', (
    tester,
  ) async {
    final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:43130');
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: endpoint,
      serverId: '91',
      sessionId: '7',
      instanceId: '2',
    );
    VoidCallback? stale;
    await tester.pumpWidget(
      MaterialApp(
        home: HowlAppShell(
          connections: HowlServerConnections(_MemoryStore()),
          initialInstanceTarget: target,
          fetchTree: (_) =>
              HowlServerTreeRequest.fromFuture(Future.value(_tree())),
          terminalBuilder: (_, value, onStaleTarget, _) {
            stale = onStaleTarget;
            return Text(
              'terminal ${value.sessionId}/${value.instanceId}',
              key: const Key('stale-terminal'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stale-terminal')), findsOneWidget);
    expect(stale, isNotNull);

    stale!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stale-terminal')), findsNothing);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
  });

  testWidgets('explicit launch route is visible while saved-route read fails', (
    tester,
  ) async {
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: HowlEndpoint.parse('tcp://127.0.0.1:43127'),
      serverId: '91',
      sessionId: '7',
      instanceId: '3',
    );
    final connections = HowlServerConnections(_ThrowingReadStore());
    await tester.pumpWidget(
      MaterialApp(
        home: HowlAppShell(
          connections: connections,
          initialInstanceTarget: target,
          terminalBuilder: (_, value, _, _) => Text(
            value.endpointText,
            key: const Key('explicit-terminal-read-failure'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('explicit-terminal-read-failure')),
      findsOneWidget,
    );
    expect(connections.initialized, isTrue);
    expect(connections.loadError, isNotNull);
  });
}
