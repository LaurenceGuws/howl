import 'native_host.dart';

/// Bounded reconnect cadence for a long-lived visual client.
///
/// Attempts may continue while the app remains alive, but the wait itself is
/// capped so a long outage does not grow into minutes between probes.
final class TransportRecovery {
  TransportRecovery({
    this.delays = const <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
    ],
  }) : assert(delays.isNotEmpty);

  final List<Duration> delays;
  int _failures = 0;

  Duration failed() {
    final index = _failures < delays.length ? _failures : delays.length - 1;
    _failures += 1;
    return delays[index];
  }

  void succeeded() => _failures = 0;

  int get failures => _failures;
}

bool retriableTransportFailure(Object error, {required bool attached}) {
  if (error is! NativeHostException) return false;
  return switch (error.code) {
    // Dart already validated platform/font policy before entering the private
    // native create seam, leaving endpoint availability as the useful retry.
    'worker_host_create' || 'control_host_create' => true,
    // These coarse private-binding codes are retryable only after a pair was
    // successfully attached. Invalid packets/buffers/actions remain hard.
    'observe_4' ||
    'control_2' ||
    'worker_closed' ||
    'control_worker_closed' => attached,
    _ => false,
  };
}
