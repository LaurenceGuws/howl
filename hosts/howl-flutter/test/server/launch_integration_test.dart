import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server/change.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/launch.dart';
import 'package:howl_flutter/server/tree.dart';

void main() {
  final route = Platform.environment['HOWL_SERVER_LAUNCH_CANARY'];
  test(
    'native Flutter binding launches against a live disposable Server',
    () async {
      final endpoint = Endpoint.parse(route!);
      final before = await NativeServerTree.request(endpoint).future;
      expect(before.sessions, isEmpty);

      final created = await ServerChange.request(
        endpoint,
        before.serverId,
        kind: ServerChangeKind.createSession,
        name: 'flutter_canary',
      ).future;
      expect(created.serverId, before.serverId);

      final first = await ServerLaunch.request(
        endpoint,
        before.serverId,
        sessionId: created.sessionId,
        shell: '/bin/sh',
      ).future;
      expect(first.serverId, before.serverId);
      expect(first.sessionId, created.sessionId);

      final second = await ServerLaunch.request(
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

      final closedInstance = await ServerChange.request(
        endpoint,
        before.serverId,
        kind: ServerChangeKind.closeInstance,
        sessionId: created.sessionId,
        instanceId: first.instanceId,
      ).future;
      expect(closedInstance.sessionId, created.sessionId);
      final remaining = await NativeServerTree.request(endpoint).future;
      expect(remaining.sessions.single.instances, hasLength(1));
      expect(remaining.sessions.single.instances.single.id, second.instanceId);

      await ServerChange.request(
        endpoint,
        before.serverId,
        kind: ServerChangeKind.closeSession,
        sessionId: created.sessionId,
      ).future;
      final finalTree = await NativeServerTree.request(endpoint).future;
      expect(finalTree.sessions, isEmpty);
    },
    skip: route == null ? 'requires disposable Server endpoint' : false,
  );
}
