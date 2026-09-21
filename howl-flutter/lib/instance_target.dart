import 'howl_endpoint.dart';

/// Identifies one concrete Howl Instance connection route.
///
/// Direct mode already has an HWLS endpoint. Managed mode reaches the same HWLS
/// Instance by first connecting to one Server and selecting exact Session+Instance
/// identity. Presentation code should only care about the resulting Instance.
sealed class HowlInstanceTarget {
  const HowlInstanceTarget();

  HowlEndpoint get transportEndpoint;
  String get endpointText => transportEndpoint.toString();
  bool get managed;
  int get sessionId;
  int get instanceId;

  String get diagnosticLabel => managed
      ? 'server=$endpointText session=$sessionId instance=$instanceId'
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
  int get sessionId => 0;

  @override
  int get instanceId => 0;
}

final class ManagedHowlInstanceTarget extends HowlInstanceTarget {
  const ManagedHowlInstanceTarget({
    required this.serverEndpoint,
    required this.sessionId,
    required this.instanceId,
  }) : assert(sessionId > 0),
       assert(instanceId > 0);

  final HowlEndpoint serverEndpoint;

  @override
  final int sessionId;

  @override
  final int instanceId;

  @override
  HowlEndpoint get transportEndpoint => serverEndpoint;

  @override
  bool get managed => true;
}
