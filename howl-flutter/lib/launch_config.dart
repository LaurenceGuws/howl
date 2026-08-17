bool geometryLeaderEnabled({
  required String compiledValue,
  String? environmentValue,
}) {
  final value = compiledValue.isNotEmpty ? compiledValue : environmentValue;
  return value == '1';
}
