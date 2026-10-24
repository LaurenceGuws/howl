import 'endpoint.dart';
import 'identity.dart';

/// Exact identity needed to attach to one Server-owned Instance.
/// This is a wire boundary value, not Session navigation or client tab state.
final class Attachment {
  Attachment({
    required this.serverEndpoint,
    required String serverId,
    required String sessionId,
    required String instanceId,
  }) : serverId = exactIdentity(serverId),
       sessionId = exactIdentity(sessionId),
       instanceId = exactIdentity(instanceId);

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
