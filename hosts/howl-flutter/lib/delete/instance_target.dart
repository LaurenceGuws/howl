import '../server/endpoint.dart';

/// One exact Server-owned Instance selected by a Flutter client.
final class HowlInstanceTarget {
  HowlInstanceTarget({
    required this.serverEndpoint,
    required String serverId,
    required String sessionId,
    required String instanceId,
  }) : serverId = exactHowlIdentity(serverId),
       sessionId = exactHowlIdentity(sessionId),
       instanceId = exactHowlIdentity(instanceId);

  final Endpoint serverEndpoint;
  final String serverId;
  final String sessionId;
  final String instanceId;

  String get endpointText => serverEndpoint.toString();

  // Convert exact decimal identities only at the private Uint64 FFI seam.
  int get nativeServerId => BigInt.parse(serverId).toSigned(64).toInt();
  int get nativeSessionId => BigInt.parse(sessionId).toSigned(64).toInt();
  int get nativeInstanceId => BigInt.parse(instanceId).toSigned(64).toInt();

  String get diagnosticLabel =>
      'server=$endpointText incarnation=$serverId session=$sessionId instance=$instanceId';
}

/// Nonzero native u64 identity, retained canonically as decimal text in Dart.
String exactHowlIdentity(String value) {
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
