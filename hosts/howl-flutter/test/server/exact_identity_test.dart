import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/server/endpoint.dart';
import 'package:howl_flutter/server/attachment.dart';
import 'package:howl_flutter/server/tree.dart';

String tree(String session, String instance) => jsonEncode({
  'schema': 'howl.server.tree/v1',
  'server_id': '91',
  'tree_revision': '1',
  'sessions': [
    {
      'session_id': session,
      'name': 'exact',
      'instances': [
        {'instance_id': instance, 'state': 'running'},
      ],
    },
  ],
});

void main() {
  for (final value in ['9223372036854775808', '18446744073709551615']) {
    test(
      'exact u64 $value survives tree target isolate and FFI bits',
      () async {
        final parsed = ServerTree.parse(tree(value, value));
        final target = Attachment(
          serverEndpoint: Endpoint.parse('tcp://127.0.0.1:1'),
          serverId: parsed.serverId,
          sessionId: parsed.sessions.single.id,
          instanceId: parsed.sessions.single.instances.single.id,
        );
        expect(target.sessionId, value);
        expect(target.instanceId, value);
        final bits = await Isolate.run(
          () => [target.nativeSessionId, target.nativeInstanceId],
        );
        for (final bitPattern in bits) {
          expect(BigInt.from(bitPattern).toUnsigned(64).toString(), value);
        }
      },
    );
  }
  for (final value in ['0', '-1', '+1', '1x', '', '18446744073709551616']) {
    test('reject invalid Session and Instance identity "$value"', () {
      for (final text in [tree(value, '1'), tree('1', value)]) {
        expect(
          () => ServerTree.parse(text),
          throwsA(isA<ServerTreeException>()),
        );
      }
      for (final pair in [(value, '1'), ('1', value)]) {
        expect(
          () => Attachment(
            serverEndpoint: Endpoint.parse('tcp://127.0.0.1:1'),
            serverId: '91',
            sessionId: pair.$1,
            instanceId: pair.$2,
          ),
          throwsFormatException,
        );
      }
    });
  }
}
