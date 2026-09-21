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

  /// Dart native ints carry unsigned FFI arguments as their signed 64-bit bits.
  int get nativeServerId {
    final value = BigInt.parse(serverId);
    if (value < BigInt.zero ||
        value >= (BigInt.one << 64) ||
        (managed && value == BigInt.zero)) {
      throw const FormatException('Invalid Server incarnation');
    }
    return value.toSigned(64).toInt();
  }

  int get sessionId;
  int get instanceId;

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
  int get sessionId => 0;

  @override
  int get instanceId => 0;
}

final class ManagedHowlInstanceTarget extends HowlInstanceTarget {
  const ManagedHowlInstanceTarget({
    required this.serverEndpoint,
    required this.serverId,
    required this.sessionId,
    required this.instanceId,
  }) : assert(sessionId > 0),
       assert(instanceId > 0);

  final HowlEndpoint serverEndpoint;

  @override
  final String serverId;

  @override
  final int sessionId;

  @override
  final int instanceId;

  @override
  HowlEndpoint get transportEndpoint => serverEndpoint;

  @override
  bool get managed => true;
}
