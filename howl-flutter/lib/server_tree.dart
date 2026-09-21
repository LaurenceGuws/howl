import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'howl_endpoint.dart';

const int _serverTreeOutputBytes = 64 * 1024;
const int _serverTreeDiagnosticBytes = 256;

final class HowlServerTreeException implements Exception {
  const HowlServerTreeException(this.code);
  final String code;

  @override
  String toString() => 'HowlServerTreeException($code)';
}

enum HowlServerInstanceState { running, exited }

final class HowlServerInstance {
  const HowlServerInstance({required this.id, required this.state});
  final int id;
  final HowlServerInstanceState state;
}

final class HowlServerSession {
  const HowlServerSession({
    required this.id,
    required this.name,
    required this.instances,
  });
  final int id;
  final String name;
  final List<HowlServerInstance> instances;
}

final class HowlServerTree {
  const HowlServerTree({
    required this.serverId,
    required this.treeRevision,
    required this.sessions,
  });

  final String serverId;
  final String treeRevision;
  final List<HowlServerSession> sessions;

  static HowlServerTree parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const HowlServerTreeException('json');
    }
    if (decoded is! Map<String, Object?> ||
        decoded['schema'] != 'howl.server.tree/v1') {
      throw const HowlServerTreeException('schema');
    }
    final serverId = _opaqueIdentity(decoded['server_id'], 'server_id');
    final revision = _opaqueIdentity(decoded['tree_revision'], 'tree_revision');
    final rawSessions = decoded['sessions'];
    if (rawSessions is! List<Object?>) {
      throw const HowlServerTreeException('sessions');
    }
    final sessions = <HowlServerSession>[];
    var previousSessionId = 0;
    for (final rawSession in rawSessions) {
      if (rawSession is! Map<String, Object?>) {
        throw const HowlServerTreeException('session');
      }
      final id = _identity(rawSession['session_id'], 'session_id');
      if (id <= previousSessionId) {
        throw const HowlServerTreeException('session_order');
      }
      previousSessionId = id;
      final name = rawSession['name'];
      final rawInstances = rawSession['instances'];
      if (name is! String || name.isEmpty || rawInstances is! List<Object?>) {
        throw const HowlServerTreeException('session_shape');
      }
      final instances = <HowlServerInstance>[];
      var previousInstanceId = 0;
      for (final rawInstance in rawInstances) {
        if (rawInstance is! Map<String, Object?>) {
          throw const HowlServerTreeException('instance');
        }
        final instanceId = _identity(rawInstance['instance_id'], 'instance_id');
        if (instanceId <= previousInstanceId) {
          throw const HowlServerTreeException('instance_order');
        }
        previousInstanceId = instanceId;
        final state = switch (rawInstance['state']) {
          'running' => HowlServerInstanceState.running,
          'exited' => HowlServerInstanceState.exited,
          _ => throw const HowlServerTreeException('instance_state'),
        };
        instances.add(HowlServerInstance(id: instanceId, state: state));
      }
      sessions.add(
        HowlServerSession(
          id: id,
          name: name,
          instances: List.unmodifiable(instances),
        ),
      );
    }
    return HowlServerTree(
      serverId: serverId,
      treeRevision: revision,
      sessions: List.unmodifiable(sessions),
    );
  }
}

String _opaqueIdentity(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      !RegExp(r'^[0-9]+$').hasMatch(value)) {
    throw HowlServerTreeException(field);
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed <= BigInt.zero || parsed.bitLength > 64) {
    throw HowlServerTreeException(field);
  }
  return value;
}

int _identity(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw HowlServerTreeException(field);
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) throw HowlServerTreeException(field);
  return parsed;
}

typedef _ServerTreeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Size>,
);
typedef _ServerTreeDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Size>,
);

final class NativeServerTree {
  const NativeServerTree._();

  static Future<HowlServerTree> fetch(HowlEndpoint endpoint) async {
    final json = await Isolate.run(() => _fetchJson(endpoint.toString()));
    return HowlServerTree.parse(json);
  }
}

String _fetchJson(String endpoint) {
  final library = Platform.isIOS
      ? ffi.DynamicLibrary.process()
      : ffi.DynamicLibrary.open('libhowl_native_host.so');
  final fetch = library.lookupFunction<_ServerTreeNative, _ServerTreeDart>(
    'howl_native_server_tree',
  );
  final endpointBytes = utf8.encode(endpoint);
  final endpointPointer = calloc<ffi.Uint8>(endpointBytes.length);
  endpointPointer.asTypedList(endpointBytes.length).setAll(0, endpointBytes);
  final output = calloc<ffi.Uint8>(_serverTreeOutputBytes);
  final outputLength = calloc<ffi.Size>();
  final diagnostic = calloc<ffi.Uint8>(_serverTreeDiagnosticBytes);
  final diagnosticLength = calloc<ffi.Size>();
  try {
    final code = fetch(
      endpointPointer,
      endpointBytes.length,
      output,
      _serverTreeOutputBytes,
      outputLength,
      diagnostic,
      _serverTreeDiagnosticBytes,
      diagnosticLength,
    );
    if (code != 0 || outputLength.value > _serverTreeOutputBytes) {
      final message = diagnosticLength.value == 0
          ? ''
          : utf8
                .decode(
                  diagnostic.asTypedList(diagnosticLength.value),
                  allowMalformed: true,
                )
                .replaceAll(RegExp(r'[\r\n]+'), ' ')
                .trim();
      throw HowlServerTreeException(
        message.isEmpty ? 'native_$code' : 'native_$code:$message',
      );
    }
    return utf8.decode(output.asTypedList(outputLength.value));
  } finally {
    calloc.free(diagnosticLength);
    calloc.free(diagnostic);
    calloc.free(outputLength);
    calloc.free(output);
    calloc.free(endpointPointer);
  }
}
