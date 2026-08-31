final class HowlEndpointException implements Exception {
  const HowlEndpointException(this.code);
  final String code;

  @override
  String toString() => 'HowlEndpointException($code)';
}

/// Launch-time endpoint grammar only.
///
/// Native Howl owns connection/framing. Flutter preserves this small parser
/// because command-line / dart-define configuration is platform-host policy.
final class HowlEndpoint {
  const HowlEndpoint._({this.unixPath, this.tcpPort});

  final String? unixPath;
  final int? tcpPort;

  static HowlEndpoint parse(String text) {
    if (text.startsWith('tcp://')) {
      final uri = Uri.tryParse(text);
      _require(uri != null, 'endpoint_uri');
      _require(uri!.scheme == 'tcp', 'endpoint_scheme');
      _require(uri.userInfo.isEmpty, 'endpoint_userinfo');
      _require(uri.host == '127.0.0.1', 'endpoint_host');
      _require(
        uri.hasPort && uri.port >= 1 && uri.port <= 65535,
        'endpoint_port',
      );
      _require(uri.path.isEmpty, 'endpoint_path');
      _require(!uri.hasQuery && !uri.hasFragment, 'endpoint_suffix');
      return HowlEndpoint._(tcpPort: uri.port);
    }
    _require(!text.contains('://'), 'endpoint_scheme');
    final path = text.startsWith('unix:')
        ? text.substring('unix:'.length)
        : text;
    _require(path.isNotEmpty, 'endpoint_path');
    return HowlEndpoint._(unixPath: path);
  }

  @override
  String toString() {
    final port = tcpPort;
    if (port != null) return 'tcp://127.0.0.1:$port';
    return 'unix:${unixPath!}';
  }
}

void _require(bool condition, String code) {
  if (!condition) throw HowlEndpointException(code);
}
