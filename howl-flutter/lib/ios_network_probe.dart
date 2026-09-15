import 'dart:io';

import 'package:flutter/services.dart';

import 'howl_endpoint.dart';

/// Attended iOS-only lens for Apple's Local Network policy boundary.
///
/// The real Howl transport remains the native client. This probe opens a
/// short-lived Network.framework TCP connection only when the operator taps
/// Log, so diagnostics can distinguish iOS policy/path denial from a raw BSD
/// socket failure. It retains no socket and sends no Howl protocol bytes.
final class IosNetworkProbe {
  const IosNetworkProbe();

  static const MethodChannel _channel = MethodChannel(
    'howl.flutter/ios_network_probe',
  );

  Future<String?> probe(HowlEndpoint endpoint) async {
    if (!Platform.isIOS ||
        endpoint.tcpHost == null ||
        endpoint.tcpPort == null) {
      return null;
    }
    try {
      final result = await _channel.invokeMethod<Object?>(
        'probeTcp',
        <String, Object>{'host': endpoint.tcpHost!, 'port': endpoint.tcpPort!},
      );
      if (result is! Map) return 'invalid_result';
      final state = _field(result, 'state');
      final reason = _field(result, 'reason');
      final error = _field(result, 'error');
      return 'state=$state reason=$reason error=$error';
    } on PlatformException catch (error) {
      return 'platform_error code=${_safe(error.code)} message=${_safe(error.message ?? '')}';
    } on MissingPluginException {
      return 'plugin_missing';
    }
  }

  static String _field(Map<Object?, Object?> value, String key) =>
      _safe(value[key]?.toString() ?? 'missing');

  static String _safe(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  }
}
