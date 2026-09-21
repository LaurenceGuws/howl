import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/launch_config.dart';

void main() {
  test(
    'server argument selects managed launch without changing direct syntax',
    () {
      final managed = resolveHowlLaunch(
        args: const ['--server', 'tcp://127.0.0.1:43130'],
        compiledEndpoint: '',
        compiledServerEndpoint: '',
      );
      expect(managed.mode, HowlLaunchMode.managedServer);
      expect(managed.endpoint, 'tcp://127.0.0.1:43130');

      final direct = resolveHowlLaunch(
        args: const ['tcp://127.0.0.1:43131'],
        compiledEndpoint: '',
        compiledServerEndpoint: '',
      );
      expect(direct.mode, HowlLaunchMode.directInstance);
    },
  );

  test('runtime Server environment outranks direct endpoint fallback', () {
    final target = resolveHowlLaunch(
      args: const [],
      compiledEndpoint: '',
      compiledServerEndpoint: '',
      environmentEndpoint: 'tcp://127.0.0.1:41001',
      environmentServerEndpoint: 'tcp://127.0.0.1:41002',
    );
    expect(target.mode, HowlLaunchMode.managedServer);
    expect(target.endpoint, 'tcp://127.0.0.1:41002');
  });

  test('runtime endpoint argument wins without a compiled route', () {
    expect(
      resolveHowlEndpoint(
        args: const ['tcp://127.0.0.1:41001'],
        compiledEndpoint: '',
        environmentEndpoint: 'tcp://127.0.0.1:41002',
      ),
      'tcp://127.0.0.1:41001',
    );
  });

  test('runtime environment supplies an uncompiled endpoint', () {
    expect(
      resolveHowlEndpoint(
        args: const [],
        compiledEndpoint: '',
        environmentEndpoint: 'tcp://127.0.0.1:41002',
      ),
      'tcp://127.0.0.1:41002',
    );
    expect(
      () => resolveHowlEndpoint(args: const [], compiledEndpoint: ''),
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
