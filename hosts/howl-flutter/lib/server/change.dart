import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../delete/native_host.dart';
import 'endpoint.dart';
import 'identity.dart';
import 'tree.dart';

enum ServerChangeKind { createSession, closeSession, closeInstance }

final class ServerChangeReceipt {
  const ServerChangeReceipt({required this.serverId, required this.sessionId});

  final String serverId;
  final String sessionId;

  static ServerChangeReceipt parse(String json) {
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      throw const ServerTreeException('change_json');
    }
    if (value is! Map<String, Object?> ||
        value['schema'] != 'howl.server.change/v1') {
      throw const ServerTreeException('change_schema');
    }
    final receipt = value;
    String id(String field) {
      final raw = receipt[field];
      if (raw is! String) throw ServerTreeException('change_$field');
      try {
        return exactIdentity(raw);
      } on FormatException {
        throw ServerTreeException('change_$field');
      }
    }

    return ServerChangeReceipt(
      serverId: id('server_id'),
      sessionId: id('session_id'),
    );
  }
}

final class ServerChangeRequest {
  ServerChangeRequest(this.future, {this.onCancel});

  final Future<ServerChangeReceipt> future;
  final void Function()? onCancel;
  bool _canceled = false;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    onCancel?.call();
  }

  static ServerChangeRequest fromFuture(Future<ServerChangeReceipt> future) =>
      ServerChangeRequest(future);
}

typedef ServerChanger = ServerChangeRequest Function(
  Endpoint endpoint,
  String serverId, {
  required ServerChangeKind kind,
  String? sessionId,
  String? instanceId,
  String? name,
});

final class ServerChange {
  const ServerChange._();

  static const Duration responseTimeout = Duration(seconds: 20);

  static ServerChangeRequest request(
    Endpoint endpoint,
    String serverId, {
    required ServerChangeKind kind,
    String? sessionId,
    String? instanceId,
    String? name,
  }) {
    switch (kind) {
      case ServerChangeKind.createSession:
        if (sessionId != null ||
            instanceId != null ||
            name == null ||
            !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(name)) {
          throw ArgumentError('createSession requires one valid new name');
        }
      case ServerChangeKind.closeSession:
        if (sessionId == null || instanceId != null || name != null) {
          throw ArgumentError('closeSession requires exactly one Session');
        }
      case ServerChangeKind.closeInstance:
        if (sessionId == null || instanceId == null || name != null) {
          throw ArgumentError('closeInstance requires exact Instance identity');
        }
    }
    final interrupt = NativeInterruptScope.create();
    var deadlineExpired = false;
    final worker = Isolate.run(
      () => _change(
        endpoint.toString(),
        BigInt.parse(serverId).toSigned(64).toInt(),
        kind.index + 1,
        sessionId == null ? 0 : BigInt.parse(sessionId).toSigned(64).toInt(),
        instanceId == null ? 0 : BigInt.parse(instanceId).toSigned(64).toInt(),
        name ?? '',
        interrupt.address,
      ),
    );
    final deadline = Timer(responseTimeout, () {
      deadlineExpired = true;
      interrupt.cancel();
    });
    final future = worker
        .then(ServerChangeReceipt.parse)
        .catchError((Object error, StackTrace stackTrace) {
          if (deadlineExpired &&
              error is ServerTreeException &&
              error.kind == NativeFailureKind.canceled) {
            throw const ServerTreeException(
              'server_change_timeout',
              kind: NativeFailureKind.transport,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        })
        .whenComplete(() {
          deadline.cancel();
          interrupt.destroy();
        });
    return ServerChangeRequest(
      future,
      onCancel: () {
        deadline.cancel();
        interrupt.cancel();
      },
    );
  }
}

typedef _ChangeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint64,
  ffi.Uint32,
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
typedef _ChangeDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
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

String _change(
  String endpoint,
  int serverId,
  int action,
  int sessionId,
  int instanceId,
  String name,
  int interruptAddress,
) {
  final library = Platform.isIOS
      ? ffi.DynamicLibrary.process()
      : ffi.DynamicLibrary.open('libhowl_native_host.so');
  final call = library.lookupFunction<_ChangeNative, _ChangeDart>(
    'howl_native_server_change',
  );
  ffi.Pointer<ffi.Uint8> copy(List<int> data) {
    final pointer = calloc<ffi.Uint8>(data.isEmpty ? 1 : data.length);
    if (data.isNotEmpty) pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  final endpointBytes = utf8.encode(endpoint);
  final nameBytes = utf8.encode(name);
  final endpointPointer = copy(endpointBytes);
  final namePointer = copy(nameBytes);
  final output = calloc<ffi.Uint8>(192);
  final outputLength = calloc<ffi.Size>();
  final diagnostic = calloc<ffi.Uint8>(256);
  final diagnosticLength = calloc<ffi.Size>();
  try {
    final code = call(
      endpointPointer,
      endpointBytes.length,
      serverId,
      action,
      sessionId,
      instanceId,
      namePointer,
      nameBytes.length,
      ffi.Pointer<ffi.Void>.fromAddress(interruptAddress),
      output,
      192,
      outputLength,
      diagnostic,
      256,
      diagnosticLength,
    );
    if (code != 0 || outputLength.value > 192 || diagnosticLength.value > 256) {
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
      throw ServerTreeException('change:$message', kind: kind);
    }
    return utf8.decode(output.asTypedList(outputLength.value));
  } finally {
    calloc.free(diagnosticLength);
    calloc.free(diagnostic);
    calloc.free(outputLength);
    calloc.free(output);
    calloc.free(namePointer);
    calloc.free(endpointPointer);
  }
}
