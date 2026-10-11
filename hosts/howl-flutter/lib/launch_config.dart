final class HowlLaunchException implements Exception {
  const HowlLaunchException(this.code);

  final String code;

  @override
  String toString() => 'HowlLaunchException($code)';
}

/// Resolves an explicitly selected Server endpoint; absence leaves the app shell route-less.
String resolveHowlServerEndpoint({
  required List<String> args,
  required String compiledServerEndpoint,
  String? environmentServerEndpoint,
}) {
  if (args.isNotEmpty) {
    if (args.length == 2 && args.first == '--server' && args[1].isNotEmpty) {
      return args[1];
    }
    throw const HowlLaunchException('arguments');
  }
  if (compiledServerEndpoint.isNotEmpty) return compiledServerEndpoint;
  if (environmentServerEndpoint case final value? when value.isNotEmpty) {
    return value;
  }
  throw const HowlLaunchException('missing_endpoint');
}

bool geometryLeaderEnabled({
  required String compiledValue,
  String? environmentValue,
}) {
  final value = compiledValue.isNotEmpty ? compiledValue : environmentValue;
  return value == '1' || value == 'true';
}
