import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/delete/howl_endpoint.dart';
import 'package:howl_flutter/delete/instance_target.dart';

void main() {
  test(
    'managed target preserves exact Server Session and Instance identity',
    () {
      final endpoint = HowlEndpoint.parse('unix:/tmp/howl-server.sock');
      final target = HowlInstanceTarget(
        serverEndpoint: endpoint,
        serverId: '91',
        sessionId: '7',
        instanceId: '3',
      );
      expect(target.endpointText, 'unix:/tmp/howl-server.sock');
      expect(target.serverId, '91');
      expect(target.nativeServerId, 91);
      expect(target.sessionId, '7');
      expect(target.instanceId, '3');
      expect(target.diagnosticLabel, contains('session=7 instance=3'));
    },
  );

  test('Server incarnation retains all u64 bits and rejects out of range', () {
    final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:1');
    HowlInstanceTarget target(String server) => HowlInstanceTarget(
      serverEndpoint: endpoint,
      serverId: server,
      sessionId: '1',
      instanceId: '1',
    );
    expect(target('9223372036854775808').nativeServerId, -9223372036854775808);
    expect(target('18446744073709551615').nativeServerId, -1);
    for (final invalid in ['0', '-1', '18446744073709551616']) {
      expect(() => target(invalid).nativeServerId, throwsFormatException);
    }
  });
}
