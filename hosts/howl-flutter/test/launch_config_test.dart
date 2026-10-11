import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/launch_config.dart';

void main() {
  test('Server launch selects an endpoint with explicit syntax', () {
    expect(
      resolveHowlServerEndpoint(
        args: const ['--server', 'tcp://127.0.0.1:43130'],
        compiledServerEndpoint: 'tcp://127.0.0.1:1',
        environmentServerEndpoint: 'tcp://127.0.0.1:2',
      ),
      'tcp://127.0.0.1:43130',
    );
    expect(
      () => resolveHowlServerEndpoint(
        args: const ['tcp://127.0.0.1:43131'],
        compiledServerEndpoint: '',
      ),
      throwsA(isA<HowlLaunchException>()),
    );
  });

  test('compiled Server wins over runtime environment and missing selection stays absent', () {
    expect(
      resolveHowlServerEndpoint(
        args: const [],
        compiledServerEndpoint: 'tcp://127.0.0.1:41001',
        environmentServerEndpoint: 'tcp://127.0.0.1:41002',
      ),
      'tcp://127.0.0.1:41001',
    );
    expect(
      resolveHowlServerEndpoint(
        args: const [],
        compiledServerEndpoint: '',
        environmentServerEndpoint: 'tcp://127.0.0.1:41002',
      ),
      'tcp://127.0.0.1:41002',
    );
    expect(
      () =>
          resolveHowlServerEndpoint(args: const [], compiledServerEndpoint: ''),
      throwsA(isA<HowlLaunchException>()),
    );
  });

  test('compiled geometry authority is usable on mobile builds', () {
    expect(
      geometryLeaderEnabled(compiledValue: '1', environmentValue: null),
      isTrue,
    );
    expect(
      geometryLeaderEnabled(compiledValue: 'true', environmentValue: null),
      isTrue,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '0', environmentValue: '1'),
      isFalse,
    );
  });

  test('desktop environment remains a fallback when no define is compiled', () {
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: '1'),
      isTrue,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: '0'),
      isFalse,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: null),
      isFalse,
    );
  });
}
