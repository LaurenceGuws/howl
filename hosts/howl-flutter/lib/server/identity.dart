/// Nonzero native u64 identity, retained canonically as decimal text in Dart.
String exactIdentity(String value) {
  if (value.isEmpty ||
      value.length > 20 ||
      !RegExp(r'^[0-9]+$').hasMatch(value)) {
    throw const FormatException('Invalid Howl identity');
  }
  final parsed = BigInt.parse(value);
  if (parsed <= BigInt.zero || parsed.bitLength > 64) {
    throw const FormatException('Invalid Howl identity');
  }
  return parsed.toString();
}
