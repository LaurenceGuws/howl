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

  test('only machine-classified transport availability is retriable', () {
    for (final attached in <bool>[false, true]) {
      expect(
        retriableTransportFailure(
          const NativeHostException(
            'connect',
            kind: NativeFailureKind.transport,
          ),
          attached: attached,
        ),
        true,
      );
      for (final kind in <NativeFailureKind>[
        NativeFailureKind.canceled,
        NativeFailureKind.stale,
        NativeFailureKind.permanent,
      ]) {
        expect(
          retriableTransportFailure(
            NativeHostException('fixture', kind: kind),
            attached: attached,
          ),
          false,
          reason: '${kind.name} attached=$attached',
        );
      }
    }
    // Human text cannot accidentally opt a permanent failure into retry.
    expect(
      retriableTransportFailure(
        const NativeHostException(
          'worker_host_create:SocketConnectFailed stage=socket_verify',
        ),
        attached: false,
      ),
      false,
    );
  });
}
