import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/launch_config.dart';

void main() {
  test('explicit managed argument wins and requires one endpoint', () {
    final target = resolveHowlLaunchTarget(
      args: const <String>['--server', 'unix:/run/howl/manager.sock'],
      compiledServerEndpoint: '',
      compiledEndpoint: 'unix:/old.sock',
    );
    expect(target.managed, isTrue);
    expect(target.endpoint, 'unix:/run/howl/manager.sock');

    expect(
      () => resolveHowlLaunchTarget(
        args: const <String>['--server'],
        compiledServerEndpoint: '',
        compiledEndpoint: '',
      ),
      throwsA(isA<HowlLaunchException>()),
    );
  });

  test('legacy positional endpoint remains direct Session mode', () {
    final target = resolveHowlLaunchTarget(
      args: const <String>['unix:/run/howl/session.sock'],
      compiledServerEndpoint: 'unix:/compiled-manager.sock',
      compiledEndpoint: '',
    );
    expect(target.mode, HowlLaunchMode.directSession);
    expect(target.endpoint, 'unix:/run/howl/session.sock');
  });

  test('managed environment wins before legacy direct environment', () {
    final target = resolveHowlLaunchTarget(
      args: const <String>[],
      compiledServerEndpoint: '',
      compiledEndpoint: '',
      environmentServerEndpoint: 'tcp://127.0.0.1:44000',
      environmentEndpoint: 'tcp://127.0.0.1:43000',
    );
    expect(target.mode, HowlLaunchMode.managedServer);
    expect(target.endpoint, 'tcp://127.0.0.1:44000');
  });
}
