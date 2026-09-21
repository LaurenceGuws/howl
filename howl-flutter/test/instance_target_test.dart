import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/instance_target.dart';

void main() {
  test('direct target carries no orchestration identity', () {
    final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:43127');
    final target = DirectHowlInstanceTarget(endpoint);
    expect(target.managed, isFalse);
    expect(target.endpointText, 'tcp://127.0.0.1:43127');
    expect(target.serverId, '0');
    expect(target.nativeServerId, 0);
    expect(target.sessionId, '0');
    expect(target.instanceId, '0');
  });

  test(
    'managed target preserves exact Server Session and Instance identity',
    () {
      final endpoint = HowlEndpoint.parse('unix:/tmp/howl-server.sock');
      final target = ManagedHowlInstanceTarget(
        serverEndpoint: endpoint,
        serverId: '91',
        sessionId: '7',
        instanceId: '3',
      );
      expect(target.managed, isTrue);
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
    ManagedHowlInstanceTarget target(String server) =>
        ManagedHowlInstanceTarget(
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
