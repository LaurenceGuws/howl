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

HowlServerTree _tree() => HowlServerTree.parse(
  '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
  '"tree_revision":"4","sessions":['
  '{"session_id":"7","name":"work","instances":['
  '{"instance_id":"1","state":"exited"},'
  '{"instance_id":"2","state":"running"}]}]}',
);

void main() {
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
            fetchTree: (_) async => _tree(),
            terminalBuilder: (context, target) {
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
            fetchTree: (_) async => _tree(),
            terminalBuilder: (_, target) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
    },
  );

  testWidgets(
    'direct launch stays terminal-first but shell menu remains available',
    (tester) async {
      final target = DirectHowlInstanceTarget(
        HowlEndpoint.parse('tcp://127.0.0.1:43127'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HowlAppShell(
            connections: HowlServerConnections(_MemoryStore()),
            initialInstanceTarget: target,
            terminalBuilder: (_, value) =>
                Text(value.endpointText, key: const Key('direct-terminal')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-terminal')), findsOneWidget);
      expect(find.byKey(const Key('howl-shell-menu')), findsOneWidget);
    },
  );
}
