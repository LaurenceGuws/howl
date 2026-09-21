final class HowlLaunchException implements Exception {
  const HowlLaunchException(this.code);

  final String code;

  @override
  String toString() => 'HowlLaunchException($code)';
}

enum HowlLaunchMode { directInstance, managedServer }

final class HowlLaunchTarget {
  const HowlLaunchTarget({required this.mode, required this.endpoint});

  final HowlLaunchMode mode;
  final String endpoint;

  bool get managed => mode == HowlLaunchMode.managedServer;
}

HowlLaunchTarget resolveHowlLaunch({
  required List<String> args,
  required String compiledEndpoint,
  required String compiledServerEndpoint,
  String? environmentEndpoint,
  String? environmentSocket,
  String? environmentServerEndpoint,
}) {
  if (args.isNotEmpty) {
    if (args.length == 2 && args.first == '--server' && args[1].isNotEmpty) {
      return HowlLaunchTarget(
        mode: HowlLaunchMode.managedServer,
        endpoint: args[1],
      );
    }
    if (args.length == 1 && args.first.isNotEmpty) {
      return HowlLaunchTarget(
        mode: HowlLaunchMode.directInstance,
        endpoint: args.first,
      );
    }
    throw const HowlLaunchException('arguments');
  }
  if (compiledServerEndpoint.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.managedServer,
      endpoint: compiledServerEndpoint,
    );
  }
  if (environmentServerEndpoint case final value? when value.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.managedServer,
      endpoint: value,
    );
  }
  if (compiledEndpoint.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directInstance,
      endpoint: compiledEndpoint,
    );
  }
  if (environmentEndpoint case final value? when value.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directInstance,
      endpoint: value,
    );
  }
  if (environmentSocket case final value? when value.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directInstance,
      endpoint: value,
    );
  }
  throw const HowlLaunchException('missing_endpoint');
}

String resolveHowlEndpoint({
  required List<String> args,
  required String compiledEndpoint,
  String? environmentEndpoint,
  String? environmentSocket,
}) => resolveHowlLaunch(
  args: args,
  compiledEndpoint: compiledEndpoint,
  compiledServerEndpoint: '',
  environmentEndpoint: environmentEndpoint,
  environmentSocket: environmentSocket,
).endpoint;

bool geometryLeaderEnabled({
  required String compiledValue,
  String? environmentValue,
}) {
  final value = compiledValue.isNotEmpty ? compiledValue : environmentValue;
  return value == '1' || value == 'true';
}
