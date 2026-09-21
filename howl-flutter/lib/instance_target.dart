import 'howl_endpoint.dart';

/// Identifies one concrete Howl Instance connection route.
///
/// Direct mode already has an HWLS endpoint. Managed mode reaches the same HWLS
/// Instance by first connecting to one Server and selecting exact Server incarnation+Session+Instance
/// identity. Presentation code should only care about the resulting Instance.
sealed class HowlInstanceTarget {
  const HowlInstanceTarget();

  HowlEndpoint get transportEndpoint;
  String get endpointText => transportEndpoint.toString();
  bool get managed;
  String get serverId;

  // Convert exact decimal identities only at the private Uint64 FFI seam.
  int get nativeServerId => BigInt.parse(serverId).toSigned(64).toInt();
  int get nativeSessionId => BigInt.parse(sessionId).toSigned(64).toInt();
  int get nativeInstanceId => BigInt.parse(instanceId).toSigned(64).toInt();

  String get sessionId;
  String get instanceId;

  String get diagnosticLabel => managed
      ? 'server=$endpointText incarnation=$serverId session=$sessionId instance=$instanceId'
      : 'instance=$endpointText';
}

final class DirectHowlInstanceTarget extends HowlInstanceTarget {
  const DirectHowlInstanceTarget(this.endpoint);

  final HowlEndpoint endpoint;

  @override
  HowlEndpoint get transportEndpoint => endpoint;

  @override
  bool get managed => false;

  @override
  String get serverId => '0';

  @override
  String get sessionId => '0';

  @override
  String get instanceId => '0';
}

final class ManagedHowlInstanceTarget extends HowlInstanceTarget {
  ManagedHowlInstanceTarget({
    required this.serverEndpoint,
    required String serverId,
    required String sessionId,
    required String instanceId,
  }) : serverId = exactHowlIdentity(serverId),
       sessionId = exactHowlIdentity(sessionId),
       instanceId = exactHowlIdentity(instanceId);

  final HowlEndpoint serverEndpoint;

  @override
  final String serverId;

  @override
  final String sessionId;

  @override
  final String instanceId;

  @override
  HowlEndpoint get transportEndpoint => serverEndpoint;

  @override
  bool get managed => true;
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
