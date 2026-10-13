// VT-owned version-1 native interaction schema. This is a copied C record,
// not a wire packet. Library selection and runtime belong to the embedder.
import 'dart:ffi' as ffi;
import 'dart:typed_data';

const int nativeVersion = 1;
const int interactionBytes = 16;
const int alternateScrollFlag = 1;
const int focusReportingFlag = 2;

final class InteractionRecord extends ffi.Struct {
  @ffi.Uint64()
  external int terminalRevision;
  @ffi.Uint32()
  external int flags;
  @ffi.Uint8()
  external int mouseTracking;
  @ffi.Uint8()
  external int mouseProtocol;
  @ffi.Uint8()
  external int pointerMode;
  @ffi.Uint8()
  external int reserved;
}

// Values are copied out of borrowed bytes; retaining them never retains memory.
final class Interaction {
  const Interaction({
    required this.terminalRevision,
    required this.alternateScroll,
    required this.mouseTracking,
    required this.mouseProtocol,
    required this.pointerMode,
    this.focusReporting = false,
  });
  final int terminalRevision;
  final bool alternateScroll;
  final int mouseTracking;
  final int mouseProtocol;
  final int pointerMode;
  final bool focusReporting;
  bool get mouseTrackingEnabled => mouseTracking != 0;
}

Interaction decodeInteraction(Uint8List bytes) {
  if (bytes.length != interactionBytes) {
    throw const FormatException('native_interaction_size');
  }
  final data = ByteData.sublistView(bytes);
  final flags = data.getUint32(8, Endian.host);
  final tracking = data.getUint8(12);
  final protocol = data.getUint8(13);
  final pointer = data.getUint8(14);
  if ((flags & ~(alternateScrollFlag | focusReportingFlag)) != 0 ||
      tracking > 4 ||
      protocol > 4 ||
      pointer > 3 ||
      data.getUint8(15) != 0) {
    throw const FormatException('native_interaction_layout');
  }
  return Interaction(
    terminalRevision: data.getUint64(0, Endian.host),
    alternateScroll: (flags & alternateScrollFlag) != 0,
    focusReporting: (flags & focusReportingFlag) != 0,
    mouseTracking: tracking,
    mouseProtocol: protocol,
    pointerMode: pointer,
  );
}
