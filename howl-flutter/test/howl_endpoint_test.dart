import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_endpoint.dart';

void main() {
  test('launch endpoint accepts local Unix and explicit numeric IPv4 TCP', () {
    expect(
      HowlEndpoint.parse('/tmp/howl.sock').toString(),
      'unix:/tmp/howl.sock',
    );
    expect(
      HowlEndpoint.parse('unix:/tmp/howl.sock').toString(),
      'unix:/tmp/howl.sock',
    );
    expect(
      HowlEndpoint.parse('tcp://127.0.0.1:43127').toString(),
      'tcp://127.0.0.1:43127',
    );
    expect(
      HowlEndpoint.parse('tcp://100.96.0.2:43128').toString(),
      'tcp://100.96.0.2:43128',
    );
  });

  test('launch endpoint refuses named, unspecified, or malformed TCP', () {
    for (final value in <String>[
      'tcp://0.0.0.0:43127',
      'tcp://localhost:43127',
      'tcp://100.96.0.999:43127',
      'tcp://127.0.0.1',
      'tcp://127.0.0.1:0',
      'tcp://127.0.0.1:43127/path',
      'http://127.0.0.1:43127',
    ]) {
      expect(
        () => HowlEndpoint.parse(value),
        throwsA(isA<HowlEndpointException>()),
      );
    }
  });
}
