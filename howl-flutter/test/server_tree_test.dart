import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server_tree.dart';

void main() {
  test(
    'tree parser preserves full unsigned Server identity as opaque text',
    () {
      final tree = HowlServerTree.parse(
        '{"schema":"howl.server.tree/v1","server_id":"18446744073709551615",'
        '"tree_revision":"9223372036854775808","sessions":[]}',
      );
      expect(tree.serverId, '18446744073709551615');
      expect(tree.treeRevision, '9223372036854775808');
    },
  );

  test('tree parser preserves Session and Instance lifecycle hierarchy', () {
    final tree = HowlServerTree.parse(
      '{"schema":"howl.server.tree/v1","server_id":"99","tree_revision":"7","sessions":['
      '{"session_id":"2","name":"work","instances":['
      '{"instance_id":"1","state":"exited"},'
      '{"instance_id":"3","state":"running"}]},'
      '{"session_id":"5","name":"logs","instances":[]}]}',
    );
    expect(tree.serverId, '99');
    expect(tree.treeRevision, '7');
    expect(tree.sessions.length, 2);
    expect(tree.sessions.first.name, 'work');
    expect(tree.sessions.first.instances.length, 2);
    expect(
      tree.sessions.first.instances.last.state,
      HowlServerInstanceState.running,
    );
    expect(tree.sessions.last.instances, isEmpty);
  });

  test('tree parser rejects ambiguous ordering and states', () {
    expect(
      () => HowlServerTree.parse(
        '{"schema":"howl.server.tree/v1","server_id":"1","tree_revision":"1","sessions":['
        '{"session_id":"2","name":"a","instances":[]},'
        '{"session_id":"2","name":"b","instances":[]}]}',
      ),
      throwsA(isA<HowlServerTreeException>()),
    );
    expect(
      () => HowlServerTree.parse(
        '{"schema":"howl.server.tree/v1","server_id":"1","tree_revision":"1","sessions":['
        '{"session_id":"2","name":"a","instances":[{"instance_id":"1","state":"mystery"}]}]}',
      ),
      throwsA(isA<HowlServerTreeException>()),
    );
  });
}
