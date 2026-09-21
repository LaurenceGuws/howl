final class HowlLaunchException implements Exception {
  const HowlLaunchException(this.code);

  final String code;

  @override
  String toString() => 'HowlLaunchException($code)';
}

String resolveHowlEndpoint({
  required List<String> args,
  required String compiledEndpoint,
  String? environmentEndpoint,
  String? environmentSocket,
}) {
  if (args.isNotEmpty) {
    if (args.length != 1 || args.first.isEmpty) {
      throw const HowlLaunchException('arguments');
    }
    return args.first;
  }
  if (compiledEndpoint.isNotEmpty) return compiledEndpoint;
  if (environmentEndpoint case final value? when value.isNotEmpty) return value;
  if (environmentSocket case final value? when value.isNotEmpty) return value;
  throw const HowlLaunchException('missing_endpoint');
}

bool geometryLeaderEnabled({
  required String compiledValue,
  String? environmentValue,
}) {
  final value = compiledValue.isNotEmpty ? compiledValue : environmentValue;
  return value == '1' || value == 'true';
}
