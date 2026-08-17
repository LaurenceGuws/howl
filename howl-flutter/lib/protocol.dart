import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final class HowlProtocolException implements Exception {
  const HowlProtocolException(this.code);
  final String code;
  @override
  String toString() => 'HowlProtocolException($code)';
}

Never _fail(String code) => throw HowlProtocolException(code);
void _require(bool condition, String code) {
  if (!condition) _fail(code);
}

final class HowlWire {
  static const framingVersion = 1;
  static const protocolVersion = 1;
  static const headerBytes = 12;
  static const maximumPayloadBytes = 1024 * 1024;
  static const maximumRequestPayloadBytes = 64 * 1024;
  static const maximumCommittedTextBytes = maximumRequestPayloadBytes - 1;
  static const maximumSnapshotBytes = 4 * 1024 * 1024;
  static const hello = 1;
  static const welcome = 2;
  static const observe = 3;
  static const snapshotBegin = 4;
  static const snapshotData = 5;
  static const snapshotEnd = 6;
  static const input = 7;
  static const assignLeader = 8;
  static const resize = 9;
  static const signal = 10;
  static const result = 11;
  static const gridSnapshot = 1 << 0;
  static const typedInput = 1 << 1;
  static const resizeLeader = 1 << 2;
  static const historyWindow = 1 << 3;
  static const textSnapshot = 1 << 4;
  static const inputBytes = 1;
  static const inputPaste = 2;
  static const inputKey = 3;
  static const inputMouse = 4;
  static const inputFocus = 5;
  static const keyNamed = 1;
  static const keyUnicode = 2;
  static const keyPress = 1;
  static const keyRepeat = 2;
  static const keyRelease = 3;
  static const allFeatures =
      gridSnapshot | typedInput | resizeLeader | historyWindow | textSnapshot;
  static const gridV1 = 1;
  static const textV1 = 2;
  static const textPresentation = 1;
  static const textRow = 2;
  static const textHyperlink = 3;
  static const textPresentationBytes = 1060;
  static const textRecordHeaderBytes = 8;
  static const textRowHeaderBytes = 4;
  static const textCellHeaderBytes = 35;
  static const maximumCellScalars = 24;
  static const maximumHyperlinks = 4096;
  static const maximumHyperlinkUriBytes = 2048;
  static const knownTextStyleBits = 0x01ff;
  static const knownPresentationPresenceBits = 0x0f;
  static const knownPresentationFlags = 0x01;
  static const maximumRows = 128;
  static const maximumColumns = 256;
  static const maximumCells = maximumRows * maximumColumns;
  static const _magic = <int>[0x48, 0x57, 0x4c, 0x53];
}

final class HowlFrame {
  const HowlFrame(this.kind, this.payload);
  final int kind;
  final Uint8List payload;
}

final class HowlHeader {
  const HowlHeader(this.kind, this.payloadLength);
  final int kind;
  final int payloadLength;
}

HowlHeader decodeHeader(Uint8List input) {
  _require(input.length == HowlWire.headerBytes, 'truncated_header');
  for (var i = 0; i < HowlWire._magic.length; i++) {
    if (input[i] != HowlWire._magic[i]) _fail('header_magic');
  }
  _require(input[4] == HowlWire.framingVersion, 'header_version');
  _require(input[6] == 0 && input[7] == 0, 'header_reserved');
  final kind = input[5];
  _require(kind >= HowlWire.hello && kind <= HowlWire.result, 'header_kind');
  final payloadLength = _u32(input, 8);
  _require(payloadLength <= HowlWire.maximumPayloadBytes, 'payload_limit');
  return HowlHeader(kind, payloadLength);
}

Uint8List encodeHeader(int kind, int payloadLength) {
  _require(kind >= HowlWire.hello && kind <= HowlWire.result, 'header_kind');
  _require(
    payloadLength >= 0 && payloadLength <= HowlWire.maximumPayloadBytes,
    'payload_limit',
  );
  final output = Uint8List(HowlWire.headerBytes);
  output.setRange(0, 4, HowlWire._magic);
  output[4] = HowlWire.framingVersion;
  output[5] = kind;
  _putU32(output, 8, payloadLength);
  return output;
}

List<HowlFrame> decodeFrames(Uint8List input) {
  final frames = <HowlFrame>[];
  var offset = 0;
  while (offset < input.length) {
    _require(input.length - offset >= HowlWire.headerBytes, 'truncated_header');
    final header = decodeHeader(
      Uint8List.sublistView(input, offset, offset + HowlWire.headerBytes),
    );
    offset += HowlWire.headerBytes;
    _require(input.length - offset >= header.payloadLength, 'truncated_frame');
    final payload = Uint8List.fromList(
      input.sublist(offset, offset + header.payloadLength),
    );
    offset += header.payloadLength;
    frames.add(HowlFrame(header.kind, payload));
  }
  return frames;
}

final class HowlWelcome {
  const HowlWelcome({
    required this.version,
    required this.features,
    required this.clientId,
  });
  final int version;
  final int features;
  final int clientId;
}

HowlWelcome decodeWelcome(Uint8List payload) {
  _require(payload.length == 18, 'welcome_size');
  return HowlWelcome(
    version: _u16(payload, 0),
    features: _u64(payload, 2),
    clientId: _u64(payload, 10),
  );
}

Uint8List encodeHello({int features = HowlWire.allFeatures}) {
  final payload = Uint8List(12);
  _putU16(payload, 0, HowlWire.protocolVersion);
  _putU16(payload, 2, HowlWire.protocolVersion);
  _putU64(payload, 4, features);
  return payload;
}

Uint8List encodeObserve(int afterRevision, {int historyOffset = 0}) {
  _require(afterRevision >= 0, 'observe_revision');
  _require(
    historyOffset >= 0 && historyOffset <= 0xffffffff,
    'observe_history',
  );
  final payload = Uint8List(12);
  _putU64(payload, 0, afterRevision);
  _putU32(payload, 8, historyOffset);
  return payload;
}

Uint8List encodeCommittedTextInput(String text) {
  _require(text.isNotEmpty, 'committed_text_empty');
  _require(_wellFormedUtf16(text), 'committed_text_unicode');
  final encoded = utf8.encode(text);
  _require(
    encoded.length <= HowlWire.maximumCommittedTextBytes,
    'committed_text_limit',
  );
  final payload = Uint8List(encoded.length + 1);
  payload[0] = HowlWire.inputBytes;
  payload.setRange(1, payload.length, encoded);
  return payload;
}

final class HowlSnapshotBegin {
  const HowlSnapshotBegin({
    required this.revision,
    required this.terminalRevision,
    required this.format,
    required this.historyOffset,
    required this.historyCount,
    required this.historyRowBase,
    required this.rows,
    required this.columns,
    required this.cursorRow,
    required this.cursorColumn,
    required this.cursorShape,
    required this.cursorVisible,
    required this.cursorBlink,
    required this.alternateScreen,
    required this.streamClosed,
    required this.childExited,
    required this.leaderPresent,
    required this.youAreLeader,
  });
  final int revision;
  final int terminalRevision;
  final int format;
  final int historyOffset;
  final int historyCount;
  final int historyRowBase;
  final int rows;
  final int columns;
  final int cursorRow;
  final int cursorColumn;
  final int cursorShape;
  final bool cursorVisible;
  final bool cursorBlink;
  final bool alternateScreen;
  final bool streamClosed;
  final bool childExited;
  final bool leaderPresent;
  final bool youAreLeader;
}

HowlSnapshotBegin decodeSnapshotBegin(Uint8List payload) {
  _require(payload.length == 40, 'snapshot_begin_size');
  final format = _u16(payload, 16);
  _require(
    format == HowlWire.gridV1 || format == HowlWire.textV1,
    'snapshot_format',
  );
  final flags = payload[39];
  _require(flags & 0x80 == 0, 'snapshot_flags');
  final rows = _u16(payload, 30);
  final columns = _u16(payload, 32);
  return HowlSnapshotBegin(
    revision: _u64(payload, 0),
    terminalRevision: _u64(payload, 8),
    format: format,
    historyOffset: _u32(payload, 18),
    historyCount: _u32(payload, 22),
    historyRowBase: _u32(payload, 26),
    rows: rows,
    columns: columns,
    cursorRow: _u16(payload, 34),
    cursorColumn: _u16(payload, 36),
    cursorShape: payload[38],
    cursorVisible: flags & 1 != 0,
    cursorBlink: flags & 2 != 0,
    alternateScreen: flags & 4 != 0,
    streamClosed: flags & 8 != 0,
    childExited: flags & 16 != 0,
    leaderPresent: flags & 32 != 0,
    youAreLeader: flags & 64 != 0,
  );
}

void validateClientDimensions(int rows, int columns) {
  _require(rows > 0 && columns > 0, 'snapshot_dimensions');
  _require(
    rows <= HowlWire.maximumRows && columns <= HowlWire.maximumColumns,
    'snapshot_dimensions',
  );
  _require(rows * columns <= HowlWire.maximumCells, 'snapshot_dimensions');
}

final class HowlRgba {
  const HowlRgba(this.r, this.g, this.b, this.a);
  final int r;
  final int g;
  final int b;
  final int a;
}

final class HowlPresentation {
  const HowlPresentation({
    required this.cursorAgeNanoseconds,
    required this.reverseScreen,
    required this.palette,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.cursorText,
    required this.selectionBackground,
    required this.selectionForeground,
  });
  final int cursorAgeNanoseconds;
  final bool reverseScreen;
  final List<HowlRgba> palette;
  final HowlRgba foreground;
  final HowlRgba background;
  final HowlRgba? cursor;
  final HowlRgba? cursorText;
  final HowlRgba? selectionBackground;
  final HowlRgba? selectionForeground;
}

final class HowlSemanticColor {
  const HowlSemanticColor(this.kind, this.value);
  final int kind;
  final int value;
}

final class HowlCell {
  const HowlCell({
    required this.scalars,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.subscaleNumerator,
    required this.subscaleDenominator,
    required this.verticalAlign,
    required this.horizontalAlign,
    required this.semanticWidth,
    required this.font,
    required this.baseline,
    required this.underlineStyle,
    required this.protection,
    required this.style,
    required this.foreground,
    required this.background,
    required this.underlineColor,
    required this.linkId,
  });
  final List<int> scalars;
  final int width;
  final int height;
  final int x;
  final int y;
  final int subscaleNumerator;
  final int subscaleDenominator;
  final int verticalAlign;
  final int horizontalAlign;
  final bool semanticWidth;
  final int font;
  final int baseline;
  final int underlineStyle;
  final int protection;
  final int style;
  final HowlSemanticColor foreground;
  final HowlSemanticColor background;
  final HowlSemanticColor underlineColor;
  final int linkId;
  bool get isLead => x == 0 && y == 0;
}

final class HowlRow {
  const HowlRow({
    required this.wrapped,
    required this.lineGeometry,
    required this.cells,
  });
  final bool wrapped;
  final int lineGeometry;
  final List<HowlCell> cells;
}

final class HowlSnapshot {
  const HowlSnapshot({
    required this.begin,
    required this.presentation,
    required this.rows,
    required this.hyperlinks,
  });
  final HowlSnapshotBegin begin;
  final HowlPresentation presentation;
  final List<HowlRow> rows;
  final Map<int, Uint8List> hyperlinks;
  int get revision => begin.revision;
  int get terminalRevision => begin.terminalRevision;
}

final class _TextSnapshotBuilder {
  _TextSnapshotBuilder(this.begin) {
    _require(begin.format == HowlWire.textV1, 'snapshot_format');
  }

  final HowlSnapshotBegin begin;
  HowlPresentation? presentation;
  final rows = <HowlRow>[];
  final hyperlinks = <int, Uint8List>{};
  final referencedLinks = <int>{};
  var phase = 0;

  void addData(Uint8List payload) {
    _require(
      payload.length >= HowlWire.textRecordHeaderBytes,
      'text_record_size',
    );
    _require(
      payload[1] == 0 && payload[2] == 0 && payload[3] == 0,
      'text_record_reserved',
    );
    final kind = payload[0];
    _require(
      kind >= HowlWire.textPresentation && kind <= HowlWire.textHyperlink,
      'text_record_kind',
    );
    final recordLength = _u32(payload, 4);
    _require(recordLength <= HowlWire.maximumPayloadBytes, 'payload_limit');
    _require(
      payload.length == HowlWire.textRecordHeaderBytes + recordLength,
      'text_record_count',
    );
    final body = Uint8List.sublistView(payload, HowlWire.textRecordHeaderBytes);
    switch (kind) {
      case HowlWire.textPresentation:
        _require(phase == 0 && presentation == null, 'text_record_order');
        presentation = _decodePresentation(body);
        phase = begin.rows == 0 ? 2 : 1;
      case HowlWire.textRow:
        _require(phase == 1 && rows.length < begin.rows, 'text_record_order');
        rows.add(_decodeRow(body, begin.columns, referencedLinks));
        if (rows.length == begin.rows) phase = 2;
      case HowlWire.textHyperlink:
        _require(phase == 2, 'text_record_order');
        final entry = _decodeHyperlink(body, hyperlinks);
        hyperlinks[entry.$1] = entry.$2;
    }
  }

  HowlSnapshot finish(int revision) {
    _require(revision == begin.revision, 'snapshot_revision');
    _require(presentation != null, 'text_presentation_missing');
    _require(rows.length == begin.rows, 'text_row_count');
    _require(
      referencedLinks.length == hyperlinks.length &&
          referencedLinks.every(hyperlinks.containsKey),
      'text_unresolved_hyperlink',
    );
    return HowlSnapshot(
      begin: begin,
      presentation: presentation!,
      rows: List.unmodifiable(rows),
      hyperlinks: Map.unmodifiable(hyperlinks),
    );
  }
}

HowlPresentation _decodePresentation(Uint8List payload) {
  _require(
    payload.length == HowlWire.textPresentationBytes,
    'text_presentation_size',
  );
  final presence = payload[8];
  final flags = payload[9];
  _require(
    presence & ~HowlWire.knownPresentationPresenceBits == 0,
    'text_presentation_presence',
  );
  _require(
    flags & ~HowlWire.knownPresentationFlags == 0,
    'text_presentation_flags',
  );
  _require(payload[10] == 0 && payload[11] == 0, 'text_presentation_reserved');
  final palette = List<HowlRgba>.generate(
    256,
    (index) => _rgba(payload, 12 + index * 4),
    growable: false,
  );
  return HowlPresentation(
    cursorAgeNanoseconds: _u64(payload, 0),
    reverseScreen: flags & 1 != 0,
    palette: palette,
    foreground: _rgba(payload, 1036),
    background: _rgba(payload, 1040),
    cursor: presence & 1 != 0 ? _rgba(payload, 1044) : null,
    cursorText: presence & 2 != 0 ? _rgba(payload, 1048) : null,
    selectionBackground: presence & 4 != 0 ? _rgba(payload, 1052) : null,
    selectionForeground: presence & 8 != 0 ? _rgba(payload, 1056) : null,
  );
}

HowlRow _decodeRow(Uint8List payload, int columns, Set<int> referencedLinks) {
  _require(payload.length >= HowlWire.textRowHeaderBytes, 'text_row_size');
  _require(payload[0] <= 1, 'text_row_wrapped');
  _require(payload[1] <= 3, 'text_row_geometry');
  _require(_u16(payload, 2) == columns, 'text_row_columns');
  final cells = <HowlCell>[];
  var offset = HowlWire.textRowHeaderBytes;
  for (var column = 0; column < columns; column++) {
    _require(
      payload.length - offset >= HowlWire.textCellHeaderBytes,
      'text_cell_size',
    );
    final base = offset;
    final scalarCount = payload[base];
    final width = payload[base + 1];
    final height = payload[base + 2];
    final x = payload[base + 3];
    final y = payload[base + 4];
    _require(scalarCount <= HowlWire.maximumCellScalars, 'text_scalar_count');
    _require(
      width > 0 && height > 0 && x < width && y < height,
      'text_cell_geometry',
    );
    _require(
      payload[base + 5] <= 15 && payload[base + 6] <= 15,
      'text_cell_subscale',
    );
    _require(
      payload[base + 7] <= 3 && payload[base + 8] <= 3,
      'text_cell_alignment',
    );
    _require(payload[base + 9] <= 1, 'text_cell_semantic_width');
    _require(payload[base + 10] <= 15, 'text_cell_font');
    _require(payload[base + 11] <= 2, 'text_cell_baseline');
    _require(payload[base + 12] <= 4, 'text_cell_underline');
    _require(payload[base + 13] <= 2, 'text_cell_protection');
    final style = _u16(payload, base + 14);
    _require(style & ~HowlWire.knownTextStyleBits == 0, 'text_style_bits');
    final foreground = _decodeSemanticColor(payload, base + 16);
    final background = _decodeSemanticColor(payload, base + 21);
    final underline = _decodeSemanticColor(payload, base + 26);
    final linkId = _u32(payload, base + 31);
    _require(linkId <= HowlWire.maximumHyperlinks, 'text_link_id');
    if (linkId != 0) referencedLinks.add(linkId);
    offset += HowlWire.textCellHeaderBytes;

    final scalarBytes = scalarCount * 4;
    _require(payload.length - offset >= scalarBytes, 'text_scalar_bytes');
    final scalars = <int>[];
    for (var i = 0; i < scalarCount; i++) {
      final scalar = _u32(payload, offset + i * 4);
      _require(_validScalar(scalar), 'text_scalar_unicode');
      scalars.add(scalar);
    }
    _require(
      (x == 0 && y == 0) || scalars.isEmpty,
      'text_continuation_scalars',
    );
    offset += scalarBytes;
    cells.add(
      HowlCell(
        scalars: List.unmodifiable(scalars),
        width: width,
        height: height,
        x: x,
        y: y,
        subscaleNumerator: payload[base + 5],
        subscaleDenominator: payload[base + 6],
        verticalAlign: payload[base + 7],
        horizontalAlign: payload[base + 8],
        semanticWidth: payload[base + 9] != 0,
        font: payload[base + 10],
        baseline: payload[base + 11],
        underlineStyle: payload[base + 12],
        protection: payload[base + 13],
        style: style,
        foreground: foreground,
        background: background,
        underlineColor: underline,
        linkId: linkId,
      ),
    );
  }
  _require(offset == payload.length, 'text_row_trailing');
  return HowlRow(
    wrapped: payload[0] != 0,
    lineGeometry: payload[1],
    cells: List.unmodifiable(cells),
  );
}

HowlSemanticColor _decodeSemanticColor(Uint8List payload, int offset) {
  final kind = payload[offset];
  final value = _u32(payload, offset + 1);
  _require(kind <= 2, 'text_color_kind');
  switch (kind) {
    case 0:
      _require(value == 0, 'text_color_default');
    case 1:
      _require(value <= 255, 'text_color_indexed');
    case 2:
      _require(value <= 0x00ffffff, 'text_color_rgb');
  }
  return HowlSemanticColor(kind, value);
}

(int, Uint8List) _decodeHyperlink(
  Uint8List payload,
  Map<int, Uint8List> resolved,
) {
  _require(payload.length >= 6, 'text_hyperlink_size');
  final id = _u32(payload, 0);
  final uriLength = _u16(payload, 4);
  _require(id >= 1 && id <= HowlWire.maximumHyperlinks, 'text_hyperlink_id');
  _require(
    uriLength >= 1 && uriLength <= HowlWire.maximumHyperlinkUriBytes,
    'text_hyperlink_uri_limit',
  );
  _require(payload.length == 6 + uriLength, 'text_hyperlink_size');
  _require(!resolved.containsKey(id), 'text_hyperlink_duplicate');
  return (id, Uint8List.fromList(payload.sublist(6)));
}

HowlRgba _rgba(Uint8List payload, int offset) => HowlRgba(
  payload[offset],
  payload[offset + 1],
  payload[offset + 2],
  payload[offset + 3],
);

List<HowlSnapshot> decodeTextSnapshots(Uint8List stream) {
  final frames = decodeFrames(stream);
  final snapshots = <HowlSnapshot>[];
  _TextSnapshotBuilder? builder;
  for (final frame in frames) {
    switch (frame.kind) {
      case HowlWire.snapshotBegin:
        _require(builder == null, 'snapshot_nested');
        builder = _TextSnapshotBuilder(decodeSnapshotBegin(frame.payload));
      case HowlWire.snapshotData:
        final active = builder;
        if (active == null) _fail('snapshot_data_without_begin');
        active.addData(frame.payload);
      case HowlWire.snapshotEnd:
        final active = builder;
        if (active == null) _fail('snapshot_end_without_begin');
        _require(frame.payload.length == 8, 'snapshot_end_size');
        snapshots.add(active.finish(_u64(frame.payload, 0)));
        builder = null;
      default:
        _require(builder == null, 'snapshot_interleaved');
    }
  }
  _require(builder == null, 'snapshot_unterminated');
  return snapshots;
}

final class HowlEndpoint {
  const HowlEndpoint._({this.unixPath, this.tcpPort});

  final String? unixPath;
  final int? tcpPort;

  static HowlEndpoint parse(String text) {
    if (text.startsWith('tcp://')) {
      final uri = Uri.tryParse(text);
      _require(uri != null, 'endpoint_uri');
      _require(uri!.scheme == 'tcp', 'endpoint_scheme');
      _require(uri.userInfo.isEmpty, 'endpoint_userinfo');
      _require(uri.host == '127.0.0.1', 'endpoint_host');
      _require(
        uri.hasPort && uri.port >= 1 && uri.port <= 65535,
        'endpoint_port',
      );
      _require(uri.path.isEmpty, 'endpoint_path');
      _require(!uri.hasQuery && !uri.hasFragment, 'endpoint_suffix');
      return HowlEndpoint._(tcpPort: uri.port);
    }
    _require(!text.contains('://'), 'endpoint_scheme');
    final path = text.startsWith('unix:')
        ? text.substring('unix:'.length)
        : text;
    _require(path.isNotEmpty, 'endpoint_path');
    return HowlEndpoint._(unixPath: path);
  }

  Future<Socket> connect() {
    final port = tcpPort;
    if (port != null) return Socket.connect(InternetAddress.loopbackIPv4, port);
    final path = unixPath;
    _require(path != null && path.isNotEmpty, 'endpoint_path');
    return Socket.connect(
      InternetAddress(path!, type: InternetAddressType.unix),
      0,
    );
  }

  @override
  String toString() {
    final port = tcpPort;
    if (port != null) return 'tcp://127.0.0.1:$port';
    return 'unix:${unixPath!}';
  }
}

final class HowlConnection {
  HowlConnection._(this._socket, this._reader, this.welcome);

  final Socket _socket;
  final _SocketByteReader _reader;
  final HowlWelcome welcome;
  bool _closed = false;

  static Future<HowlConnection> connect(
    HowlEndpoint endpoint, {
    int features = HowlWire.allFeatures,
  }) async {
    final socket = await endpoint.connect();
    final reader = _SocketByteReader(socket);
    try {
      await _writeFrame(
        socket,
        HowlWire.hello,
        encodeHello(features: features),
      );
      final frame = await reader.readFrame();
      _require(frame.kind == HowlWire.welcome, 'unexpected_frame');
      final welcome = decodeWelcome(frame.payload);
      _require(welcome.version == HowlWire.protocolVersion, 'protocol_version');
      _require(
        welcome.features & HowlWire.gridSnapshot != 0,
        'grid_feature_missing',
      );
      return HowlConnection._(socket, reader, welcome);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }

  Future<HowlSnapshot> observeText(
    int afterRevision, {
    int historyOffset = 0,
  }) async {
    _require(!_closed, 'connection_closed');
    _require(
      welcome.features & HowlWire.textSnapshot != 0,
      'text_feature_missing',
    );
    await _writeFrame(
      _socket,
      HowlWire.observe,
      encodeObserve(afterRevision, historyOffset: historyOffset),
    );
    var totalBytes = 0;
    final beginFrame = await _reader.readFrame();
    totalBytes += HowlWire.headerBytes + beginFrame.payload.length;
    if (beginFrame.kind == HowlWire.result) _fail('observe_rejected');
    _require(beginFrame.kind == HowlWire.snapshotBegin, 'unexpected_frame');
    final begin = decodeSnapshotBegin(beginFrame.payload);
    validateClientDimensions(begin.rows, begin.columns);
    final builder = _TextSnapshotBuilder(begin);
    while (true) {
      final frame = await _reader.readFrame();
      totalBytes += HowlWire.headerBytes + frame.payload.length;
      _require(totalBytes <= HowlWire.maximumSnapshotBytes, 'snapshot_limit');
      switch (frame.kind) {
        case HowlWire.snapshotData:
          builder.addData(frame.payload);
        case HowlWire.snapshotEnd:
          _require(frame.payload.length == 8, 'snapshot_end_size');
          return builder.finish(_u64(frame.payload, 0));
        default:
          _fail('unexpected_frame');
      }
    }
  }

  Future<void> sendNamedKey({
    required int keyName,
    required int action,
    int modifiers = 0,
  }) async {
    _require(
      welcome.features & HowlWire.typedInput != 0,
      'typed_input_feature_missing',
    );
    _require(keyName >= 1 && keyName <= 58, 'key_name');
    _require(
      action >= HowlWire.keyPress && action <= HowlWire.keyRelease,
      'key_action',
    );
    _require(modifiers >= 0 && modifiers <= 0xff, 'key_modifiers');
    final payload = Uint8List(1 + 20);
    payload[0] = HowlWire.inputKey;
    payload[1] = HowlWire.keyNamed;
    payload[2] = action;
    payload[3] = modifiers;
    _putU32(payload, 5, keyName);
    await _command(HowlWire.input, payload);
  }

  Future<void> sendCommittedText(String text) async {
    await _command(HowlWire.input, encodeCommittedTextInput(text));
  }

  Future<void> sendFocus(bool focused) async {
    _require(
      welcome.features & HowlWire.typedInput != 0,
      'typed_input_feature_missing',
    );
    await _command(
      HowlWire.input,
      Uint8List.fromList(<int>[HowlWire.inputFocus, focused ? 1 : 2]),
    );
  }

  Future<void> assignLeader(int clientId) async {
    _require(
      welcome.features & HowlWire.resizeLeader != 0,
      'resize_feature_missing',
    );
    _require(clientId >= 0, 'client_id');
    final payload = Uint8List(8);
    _putU64(payload, 0, clientId);
    await _command(HowlWire.assignLeader, payload);
  }

  Future<void> resize(int rows, int columns) async {
    _require(
      welcome.features & HowlWire.resizeLeader != 0,
      'resize_feature_missing',
    );
    validateClientDimensions(rows, columns);
    final payload = Uint8List(4);
    _putU16(payload, 0, rows);
    _putU16(payload, 2, columns);
    await _command(HowlWire.resize, payload);
  }

  Future<void> _command(int kind, Uint8List payload) async {
    _require(!_closed, 'connection_closed');
    await _writeFrame(_socket, kind, payload);
    final frame = await _reader.readFrame();
    _require(frame.kind == HowlWire.result, 'unexpected_frame');
    _require(frame.payload.length == 2, 'result_size');
    _require(frame.payload[0] == kind, 'result_request_kind');
    if (frame.payload[1] != 0) _fail('result_${frame.payload[1]}');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }
}

final class _SocketByteReader {
  _SocketByteReader(Socket socket) : _iterator = StreamIterator(socket);

  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<HowlFrame> readFrame() async {
    final headerBytes = await _readExact(HowlWire.headerBytes);
    final header = decodeHeader(headerBytes);
    final payload = await _readExact(header.payloadLength);
    return HowlFrame(header.kind, payload);
  }

  Future<Uint8List> _readExact(int length) async {
    _require(
      length >= 0 && length <= HowlWire.maximumPayloadBytes,
      'payload_limit',
    );
    if (length == 0) return Uint8List(0);
    final output = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_offset == _chunk.length) {
        final moved = await _iterator.moveNext();
        _require(moved, 'socket_closed');
        _chunk = _iterator.current;
        _offset = 0;
        if (_chunk.isEmpty) continue;
      }
      final available = _chunk.length - _offset;
      final needed = length - written;
      final count = available < needed ? available : needed;
      output.setRange(written, written + count, _chunk, _offset);
      written += count;
      _offset += count;
    }
    return output;
  }
}

Future<void> _writeFrame(Socket socket, int kind, Uint8List payload) async {
  _require(
    payload.length <= HowlWire.maximumRequestPayloadBytes,
    'request_payload_limit',
  );
  socket.add(encodeHeader(kind, payload.length));
  socket.add(payload);
  await socket.flush();
}

bool _wellFormedUtf16(String text) {
  final units = text.codeUnits;
  var index = 0;
  while (index < units.length) {
    final unit = units[index++];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index == units.length) return false;
      final low = units[index++];
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _validScalar(int value) =>
    value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);
int _u16(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];
int _u32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
int _u64(Uint8List bytes, int offset) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

void _putU16(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

void _putU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

void _putU64(Uint8List bytes, int offset, int value) {
  for (var i = 7; i >= 0; i--) {
    bytes[offset + i] = value & 0xff;
    value >>= 8;
  }
}

Uint8List hexBytes(String value) {
  _require(value.length.isEven, 'hex');
  final output = Uint8List(value.length ~/ 2);
  for (var i = 0; i < output.length; i++) {
    final parsed = int.tryParse(value.substring(i * 2, i * 2 + 2), radix: 16);
    _require(parsed != null, 'hex');
    output[i] = parsed!;
  }
  return output;
}

String hyperlinkText(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true);
