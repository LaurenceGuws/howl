// Standalone, dependency-free Dart consumer of an actual owner-header C record.
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import '../bindings/dart/lib/native.dart' as native;

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

void malformed(Uint8List bytes) {
  try {
    native.decodeInteraction(bytes);
  } on FormatException {
    return;
  }
  throw StateError('malformed record accepted');
}

void main(List<String> args) {
  require(args.length == 1, 'C fixture executable required');
  final result = Process.runSync(args.single, [], stdoutEncoding: null);
  require(result.exitCode == 0, 'C fixture failed: ${result.stderr}');
  final bytes = Uint8List.fromList(result.stdout as List<int>);
  require(
    ffi.sizeOf<native.InteractionRecord>() == native.interactionBytes,
    'Dart C record layout changed',
  );
  final libc = ffi.DynamicLibrary.process();
  final calloc = libc
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Size, ffi.Size),
        ffi.Pointer<ffi.Void> Function(int, int)
      >('calloc');
  final free = libc
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)
      >('free');
  final storage = calloc(1, native.interactionBytes);
  require(storage != ffi.nullptr, 'foreign allocation failed');
  try {
    storage
        .cast<ffi.Uint8>()
        .asTypedList(native.interactionBytes)
        .setAll(0, bytes);
    final record = storage.cast<native.InteractionRecord>().ref;
    require(
      record.terminalRevision == 0x1122334455667788,
      'C/Dart revision offset',
    );
    require(
      record.flags == 3 &&
          record.mouseTracking == 4 &&
          record.mouseProtocol == 3 &&
          record.pointerMode == 2 &&
          record.reserved == 0,
      'C/Dart field identity',
    );
  } finally {
    free(storage);
  }
  final value = native.decodeInteraction(bytes);
  require(
    value.terminalRevision == 0x1122334455667788 &&
        value.alternateScroll &&
        value.focusReporting &&
        value.mouseTrackingEnabled &&
        value.mouseTracking == 4 &&
        value.mouseProtocol == 3 &&
        value.pointerMode == 2,
    'copied native facts',
  );
  malformed(Uint8List(native.interactionBytes - 1));
  malformed(Uint8List(native.interactionBytes + 1));
  for (final entry in <int, int>{8: 4, 12: 5, 13: 5, 14: 4, 15: 1}.entries) {
    final bad = Uint8List.fromList(bytes);
    if (entry.key == 8) {
      ByteData.sublistView(bad).setUint32(8, entry.value, Endian.host);
    } else {
      bad[entry.key] = entry.value;
    }
    malformed(bad);
  }
  bytes.fillRange(0, bytes.length, 0);
  require(
    value.terminalRevision == 0x1122334455667788 && value.mouseTracking == 4,
    'copied facts retained a byte borrow',
  );
  print(
    'Dart native interaction: actual C layout, native endian, tags, bounds and independent lifetime passed',
  );
}
