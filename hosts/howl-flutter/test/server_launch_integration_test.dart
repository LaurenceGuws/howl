import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/server_launch.dart';
import 'package:howl_flutter/server_tree.dart';

void main() {
  final route = Platform.environment['HOWL_SERVER_LAUNCH_CANARY'];
  test('native Flutter binding launches against a live disposable Server', () async {
    final endpoint = HowlEndpoint.parse(route!);
    final before = await NativeServerTree.request(endpoint).future;
    expect(before.sessions, isEmpty);

    final first = await NativeServerLaunch.request(
      endpoint,
      before.serverId,
      sessionName: 'flutter_canary',
      shell: '/bin/sh',
    ).future;
    expect(first.serverId, before.serverId);

    final second = await NativeServerLaunch.request(
      endpoint,
      before.serverId,
      sessionId: first.sessionId,
      shell: '/bin/sh',
    ).future;
    expect(second.serverId, before.serverId);
    expect(second.sessionId, first.sessionId);
    expect(second.instanceId, isNot(first.instanceId));

    final after = await NativeServerTree.request(endpoint).future;
    expect(after.sessions, hasLength(1));
    expect(after.sessions.single.name, 'flutter_canary');
    expect(after.sessions.single.instances, hasLength(2));
    expect(
      after.sessions.single.instances.map((instance) => instance.id),
      containsAll(<String>[first.instanceId, second.instanceId]),
    );
  }, skip: route == null ? 'requires disposable Server endpoint' : false);
}
