import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/services.dart';

const String _primaryAsset = 'assets/pressure/native-primary.ttf';
const String _fallbackAsset = 'assets/pressure/native-symbols.ttf';
const int _outputCapacity = 256 * 1024;

typedef _VersionNative = ffi.Uint32 Function();
typedef _VersionDart = int Function();
typedef _RenderNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.Uint8>,
  ffi.IntPtr,
  ffi.Pointer<ffi.IntPtr>,
);
typedef _RenderDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.IntPtr>,
);
typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

final class NativeIosCanvasResult {
  const NativeIosCanvasResult({
    required this.canaryVersion,
    required this.hostVersion,
    required this.bytes,
  });

  final int canaryVersion;
  final int hostVersion;
  final Uint8List bytes;
}

Future<NativeIosCanvasResult> loadNativeIosCanvasHcr1() async {
  final directory = await Directory.systemTemp.createTemp('howl-ios-native-');
  try {
    final primary = await _writeAsset(directory, 'primary.ttf', _primaryAsset);
    final fallback = await _writeAsset(
      directory,
      'symbols.ttf',
      _fallbackAsset,
    );
    return _render(primary.path, fallback.path);
  } finally {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Pressure-only cleanup failure must not invalidate copied presentation.
    }
  }
}

Future<File> _writeAsset(
  Directory directory,
  String fileName,
  String asset,
) async {
  final data = await rootBundle.load(asset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

NativeIosCanvasResult _render(String primaryPath, String fallbackPath) {
  final process = ffi.DynamicLibrary.process();
  final canaryVersion = process.lookupFunction<_VersionNative, _VersionDart>(
    'howl_ios_native_canary_version',
  )();
  final hostVersion = process.lookupFunction<_VersionNative, _VersionDart>(
    'howl_native_host_version',
  )();
  if (canaryVersion != 2 || hostVersion != 1) {
    throw StateError(
      'unexpected native versions canary=$canaryVersion host=$hostVersion',
    );
  }
  // Compile/link proof for the exact Android host/control surface. These are
  // deliberately not called because iOS remote reachability remains SSH-only.
  process.lookup<ffi.NativeFunction<ffi.Void Function()>>(
    'howl_native_host_create',
  );
  process.lookup<ffi.NativeFunction<ffi.Void Function()>>(
    'howl_native_host_observe',
  );
  process.lookup<ffi.NativeFunction<ffi.Void Function()>>(
    'howl_native_control_create',
  );
  process.lookup<ffi.NativeFunction<ffi.Void Function()>>(
    'howl_native_control_mouse',
  );
  final render = process.lookupFunction<_RenderNative, _RenderDart>(
    'howl_ios_native_render_hcr1',
  );
  final malloc = process.lookupFunction<_MallocNative, _MallocDart>('malloc');
  final free = process.lookupFunction<_FreeNative, _FreeDart>('free');

  ffi.Pointer<ffi.Uint8> allocateBytes(Uint8List bytes) {
    final pointer = malloc(bytes.length).cast<ffi.Uint8>();
    if (pointer.address == 0) throw StateError('native malloc failed');
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  final primaryBytes = Uint8List.fromList(utf8.encode(primaryPath));
  final fallbackBytes = Uint8List.fromList(utf8.encode(fallbackPath));
  final primary = allocateBytes(primaryBytes);
  final fallback = allocateBytes(fallbackBytes);
  final output = malloc(_outputCapacity).cast<ffi.Uint8>();
  final outputLength = malloc(ffi.sizeOf<ffi.IntPtr>()).cast<ffi.IntPtr>();
  if (output.address == 0 || outputLength.address == 0) {
    free(primary.cast<ffi.Void>());
    free(fallback.cast<ffi.Void>());
    if (output.address != 0) free(output.cast<ffi.Void>());
    if (outputLength.address != 0) free(outputLength.cast<ffi.Void>());
    throw StateError('native output allocation failed');
  }

  try {
    outputLength.value = 0;
    final result = render(
      primary,
      primaryBytes.length,
      fallback,
      fallbackBytes.length,
      output,
      _outputCapacity,
      outputLength,
    );
    if (result != 0) {
      throw StateError('native final Canvas render failed: $result');
    }
    final length = outputLength.value;
    if (length <= 0 || length > _outputCapacity) {
      throw StateError('native final Canvas length invalid: $length');
    }
    return NativeIosCanvasResult(
      canaryVersion: canaryVersion,
      hostVersion: hostVersion,
      bytes: Uint8List.fromList(output.asTypedList(length)),
    );
  } finally {
    free(outputLength.cast<ffi.Void>());
    free(output.cast<ffi.Void>());
    free(fallback.cast<ffi.Void>());
    free(primary.cast<ffi.Void>());
  }
}
