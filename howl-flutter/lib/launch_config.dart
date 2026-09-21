enum HowlLaunchMode { directSession, managedServer }

final class HowlLaunchTarget {
  const HowlLaunchTarget({required this.mode, required this.endpoint});

  final HowlLaunchMode mode;
  final String endpoint;

  bool get managed => mode == HowlLaunchMode.managedServer;
}

final class HowlLaunchException implements Exception {
  const HowlLaunchException(this.code);

  final String code;

  @override
  String toString() => 'HowlLaunchException($code)';
}

HowlLaunchTarget resolveHowlLaunchTarget({
  required List<String> args,
  required String compiledServerEndpoint,
  required String compiledEndpoint,
  String? environmentServerEndpoint,
  String? environmentEndpoint,
  String? environmentSocket,
}) {
  if (args.isNotEmpty) {
    if (args.first == '--server') {
      if (args.length != 2 || args[1].isEmpty) {
        throw const HowlLaunchException('server_arguments');
      }
      return HowlLaunchTarget(
        mode: HowlLaunchMode.managedServer,
        endpoint: args[1],
      );
    }
    if (args.length != 1 || args.first.isEmpty) {
      throw const HowlLaunchException('session_arguments');
    }
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directSession,
      endpoint: args.first,
    );
  }

  if (compiledServerEndpoint.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.managedServer,
      endpoint: compiledServerEndpoint,
    );
  }
  if (environmentServerEndpoint case final endpoint? when endpoint.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.managedServer,
      endpoint: endpoint,
    );
  }
  if (compiledEndpoint.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directSession,
      endpoint: compiledEndpoint,
    );
  }
  final direct = environmentEndpoint?.isNotEmpty == true
      ? environmentEndpoint
      : environmentSocket;
  if (direct != null && direct.isNotEmpty) {
    return HowlLaunchTarget(
      mode: HowlLaunchMode.directSession,
      endpoint: direct,
    );
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
