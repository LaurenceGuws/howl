import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'endpoint.dart';
import 'identity.dart';
import '../delete/native_host.dart';
import 'tree.dart';

final class ServerLaunchReceipt {
  const ServerLaunchReceipt({
    required this.serverId,
    required this.sessionId,
    required this.instanceId,
  });

  final String serverId;
  final String sessionId;
  final String instanceId;

  static ServerLaunchReceipt parse(String json) {
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      throw const ServerTreeException('launch_json');
    }
    if (value is! Map<String, Object?> ||
        value['schema'] != 'howl.server.launch/v1') {
      throw const ServerTreeException('launch_schema');
    }
    final receipt = value;
    String identity(String field) {
      final raw = receipt[field];
      if (raw is! String) throw ServerTreeException('launch_$field');
      try {
        return exactIdentity(raw);
      } on FormatException {
        throw ServerTreeException('launch_$field');
      }
    }

    return ServerLaunchReceipt(
      serverId: identity('server_id'),
      sessionId: identity('session_id'),
      instanceId: identity('instance_id'),
    );
  }
}

final class ServerLaunchRequest {
  ServerLaunchRequest(this.future, {this.onCancel});

  final Future<ServerLaunchReceipt> future;
  final void Function()? onCancel;
  bool _canceled = false;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    onCancel?.call();
  }

  static ServerLaunchRequest fromFuture(Future<ServerLaunchReceipt> future) =>
      ServerLaunchRequest(future);
}

typedef ServerLauncher = ServerLaunchRequest Function(
  Endpoint endpoint,
  String serverId, {
  required String sessionId,
  required String shell,
});

final class ServerLaunch {
  const ServerLaunch._();

  static const Duration responseTimeout = Duration(seconds: 20);

  static ServerLaunchRequest request(
    Endpoint endpoint,
    String serverId, {
    required String sessionId,
    required String shell,
  }) {
    exactIdentity(sessionId);
    final bytes = utf8.encode(shell);
    if (bytes.isEmpty || bytes.length > 1024 || bytes.contains(0)) {
      throw ArgumentError.value(shell, 'shell', 'invalid executable path');
    }

    final interrupt = NativeInterruptScope.create();
    var deadlineExpired = false;
    final worker = Isolate.run(
      () => _launch(
        endpoint.toString(),
        BigInt.parse(serverId).toSigned(64).toInt(),
        BigInt.parse(sessionId).toSigned(64).toInt(),
        shell,
        interrupt.address,
      ),
    );
    final deadline = Timer(responseTimeout, () {
      deadlineExpired = true;
      interrupt.cancel();
    });
    final future = worker
        .then(ServerLaunchReceipt.parse)
        .catchError((Object error, StackTrace stackTrace) {
          if (deadlineExpired &&
              error is ServerTreeException &&
              error.kind == NativeFailureKind.canceled) {
            throw const ServerTreeException(
              'server_launch_timeout',
              kind: NativeFailureKind.transport,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        })
        .whenComplete(() {
          deadline.cancel();
          interrupt.destroy();
        });
    return ServerLaunchRequest(
      future,
      onCancel: () {
        deadline.cancel();
        interrupt.cancel();
      },
    );
  }
}

typedef _LaunchNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _LaunchDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);

String _launch(
  String endpoint,
  int serverId,
  int sessionId,
  String shell,
  int interruptAddress,
) {
  final library = Platform.isIOS
      ? ffi.DynamicLibrary.process()
      : ffi.DynamicLibrary.open('libhowl_native_host.so');
  final call = library.lookupFunction<_LaunchNative, _LaunchDart>(
    'howl_native_server_launch',
  );
  final endpointBytes = utf8.encode(endpoint);
  final shellBytes = utf8.encode(shell);
  ffi.Pointer<ffi.Uint8> bytes(List<int> data) {
    final pointer = calloc<ffi.Uint8>(data.isEmpty ? 1 : data.length);
    if (data.isNotEmpty) pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  final endpointPointer = bytes(endpointBytes);
  final shellPointer = bytes(shellBytes);
  final output = calloc<ffi.Uint8>(256);
  final outputLength = calloc<ffi.Size>();
  final diagnostic = calloc<ffi.Uint8>(256);
  final diagnosticLength = calloc<ffi.Size>();
  try {
    final code = call(
      endpointPointer,
      endpointBytes.length,
      serverId,
      sessionId,
      shellPointer,
      shellBytes.length,
      ffi.Pointer<ffi.Void>.fromAddress(interruptAddress),
      output,
      256,
      outputLength,
      diagnostic,
      256,
      diagnosticLength,
    );
    if (code != 0 || outputLength.value > 256 || diagnosticLength.value > 256) {
      final raw = diagnostic.asTypedList(
        diagnosticLength.value > 256 ? 256 : diagnosticLength.value,
      );
      final kind = raw.isEmpty
          ? NativeFailureKind.permanent
          : switch (raw[0]) {
              2 => NativeFailureKind.transport,
              3 => NativeFailureKind.canceled,
              4 => NativeFailureKind.stale,
              _ => NativeFailureKind.permanent,
            };
      final message = raw.length < 2
          ? 'native_$code'
          : utf8.decode(raw.sublist(1), allowMalformed: true).trim();
      throw ServerTreeException('launch:$message', kind: kind);
    }
    return utf8.decode(output.asTypedList(outputLength.value));
  } finally {
    calloc.free(diagnosticLength);
    calloc.free(diagnostic);
    calloc.free(outputLength);
    calloc.free(output);
    calloc.free(shellPointer);
    calloc.free(endpointPointer);
  }
}
