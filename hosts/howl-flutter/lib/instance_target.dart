import 'howl_endpoint.dart';

enum HowlInstanceRoute { managed, local }

/// Selects an exact Server occurrence or a direct in-process Local Instance.
sealed class HowlInstanceTarget {
  const HowlInstanceTarget();

  HowlInstanceRoute get route;
  HowlEndpoint? get transportEndpoint;
  String get endpointText => transportEndpoint?.toString() ?? '';
  bool get managed => route == HowlInstanceRoute.managed;
  bool get local => route == HowlInstanceRoute.local;
  int get nativeRoute => switch (route) {
    HowlInstanceRoute.managed => 1,
    HowlInstanceRoute.local => 2,
  };
  String get serverId => '0';

  // Convert exact decimal identities only at the private Uint64 FFI seam.
  int get nativeServerId => BigInt.parse(serverId).toSigned(64).toInt();
  int get nativeSessionId => BigInt.parse(sessionId).toSigned(64).toInt();
  int get nativeInstanceId => BigInt.parse(instanceId).toSigned(64).toInt();

  String get sessionId => '0';
  String get instanceId => '0';

  String get diagnosticLabel => switch (route) {
    HowlInstanceRoute.managed =>
      'server=$endpointText incarnation=$serverId session=$sessionId instance=$instanceId',
    HowlInstanceRoute.local => 'local instance',
  };
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
  HowlInstanceRoute get route => HowlInstanceRoute.managed;
}

final class LocalHowlInstanceTarget extends HowlInstanceTarget {
  const LocalHowlInstanceTarget();

  @override
  HowlInstanceRoute get route => HowlInstanceRoute.local;

  @override
  HowlEndpoint? get transportEndpoint => null;
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
