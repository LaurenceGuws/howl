import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/native_host.dart';
import 'package:howl_flutter/transport_recovery.dart';

void main() {
  test('transport retry cadence caps and resets after a healthy frame', () {
    final recovery = TransportRecovery();
    expect(recovery.failed(), const Duration(milliseconds: 250));
    expect(recovery.failed(), const Duration(milliseconds: 500));
    expect(recovery.failed(), const Duration(seconds: 1));
    expect(recovery.failed(), const Duration(seconds: 2));
    expect(recovery.failed(), const Duration(seconds: 5));
    expect(recovery.failed(), const Duration(seconds: 5));
    expect(recovery.failures, 6);
    recovery.succeeded();
    expect(recovery.failures, 0);
    expect(recovery.failed(), const Duration(milliseconds: 250));
  });

  test('only endpoint and established transport envelopes are retriable', () {
    expect(
      retriableTransportFailure(
        const NativeHostException('worker_host_create'),
        attached: false,
      ),
      true,
    );
    expect(
      retriableTransportFailure(
        const NativeHostException('control_host_create'),
        attached: false,
      ),
      true,
    );
    expect(
      retriableTransportFailure(
        const NativeHostException('observe_4'),
        attached: true,
      ),
      true,
    );
    expect(
      retriableTransportFailure(
        const NativeHostException('observe_4'),
        attached: false,
      ),
      false,
    );
    for (final code in <String>[
      'primary_font_missing',
      'packet_version',
      'observe_3',
      'control_3',
      'worker_isolate_error',
    ]) {
      expect(
        retriableTransportFailure(NativeHostException(code), attached: true),
        false,
        reason: code,
      );
    }
  });
}
