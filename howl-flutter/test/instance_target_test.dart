import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';
import 'package:howl_flutter/instance_target.dart';

void main() {
  test('direct target carries no orchestration identity', () {
    final endpoint = HowlEndpoint.parse('tcp://127.0.0.1:43127');
    final target = DirectHowlInstanceTarget(endpoint);
    expect(target.managed, isFalse);
    expect(target.endpointText, 'tcp://127.0.0.1:43127');
    expect(target.sessionId, 0);
    expect(target.instanceId, 0);
  });

  test('managed target preserves exact Session and Instance identity', () {
    final endpoint = HowlEndpoint.parse('unix:/tmp/howl-server.sock');
    final target = ManagedHowlInstanceTarget(
      serverEndpoint: endpoint,
      sessionId: 7,
      instanceId: 3,
    );
    expect(target.managed, isTrue);
    expect(target.endpointText, 'unix:/tmp/howl-server.sock');
    expect(target.sessionId, 7);
    expect(target.instanceId, 3);
    expect(target.diagnosticLabel, contains('session=7 instance=3'));
  });
}
