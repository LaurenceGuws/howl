import 'dart:async';

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
      '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615","tree_revision":"4","sessions":['
      '{"session_id":"7","name":"work","instances":['
      '{"instance_id":"1","state":"exited"},'
      '{"instance_id":"2","state":"running"}]}]}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HowlServerBrowser(
          endpoint: HowlEndpoint.parse('tcp://127.0.0.1:43130'),
          fetchTree: (_) async => tree,
          onOpenTarget: (target) => selected = target,
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
    expect(selected!.serverId, '18446744073709551615');
    expect(selected!.nativeServerId, -1);
    expect(selected!.sessionId, 7);
    expect(selected!.instanceId, 2);
  });

  testWidgets(
    'row selection pins its rendered Server incarnation between frames',
    (tester) async {
      HowlServerTree tree(String serverId, String name) => HowlServerTree.parse(
        '{"schema":"howl.server.tree/v1","server_id":"$serverId","tree_revision":"4","sessions":['
        '{"session_id":"7","name":"$name","instances":['
        '{"instance_id":"3","state":"running"}]}]}',
      );
      final refresh = Completer<HowlServerTree>();
      var calls = 0;
      ManagedHowlInstanceTarget? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: HowlServerBrowser(
            endpoint: HowlEndpoint.parse('tcp://127.0.0.1:1'),
            fetchTree: (_) => calls++ == 0
                ? Future.value(tree('91', 'OLD_OCCURRENCE'))
                : refresh.future,
            onOpenTarget: (target) => selected = target,
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
      await tester.tap(find.text('Instance 3'));
      expect(selected, isNotNull);
      expect(selected!.serverId, '91');
      expect(selected!.sessionId, 7);
      expect(selected!.instanceId, 3);

      selected = null;
      await tester.pumpAndSettle();
      expect(find.text('OLD_OCCURRENCE'), findsNothing);
      expect(find.text('NEW_OCCURRENCE'), findsOneWidget);
      await tester.tap(find.text('Instance 3'));
      expect(selected, isNotNull);
      expect(selected!.serverId, '92');
      expect(selected!.sessionId, 7);
      expect(selected!.instanceId, 3);
      await tester.pumpAndSettle();
    },
  );
}
