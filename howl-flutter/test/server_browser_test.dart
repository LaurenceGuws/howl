import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/instance_target.dart';
import 'package:howl_flutter/server_browser.dart';
import 'package:howl_flutter/server_tree.dart';

void main() {
  testWidgets('browser shows Session lineage and only opens running Instance', (
    tester,
  ) async {
    ManagedHowlInstanceTarget? selected;
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"1","tree_revision":"4","sessions":['
      '{"session_id":"7","name":"work","instances":['
      '{"instance_id":"1","state":"exited"},'
      '{"instance_id":"2","state":"running"}]}]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HowlServerBrowser(
          endpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) async => tree,
          terminalBuilder: (context, target) {
            selected = target;
            return const Text('terminal');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Instance 1'), findsOneWidget);
    expect(find.text('exited'), findsOneWidget);
    expect(find.text('Instance 2'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);

    await tester.tap(find.text('Instance 1'));
    await tester.pump();
    expect(selected, isNull);

    await tester.tap(find.text('Instance 2'));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(selected!.sessionId, 7);
    expect(selected!.instanceId, 2);
    expect(find.text('terminal'), findsOneWidget);
  });
}
