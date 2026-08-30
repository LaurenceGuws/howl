import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/protocol.dart';

final Map<String, dynamic> vectors = jsonDecode(
  File('../howl-session/protocol/v1-vectors.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> vector(String id) => (vectors['cases'] as List<dynamic>)
    .cast<Map<String, dynamic>>()
    .singleWhere((value) => value['id'] == id);

void main() {
  test('client endpoint keeps Unix oracle and exact TCP loopback', () {
    final bareUnix = HowlEndpoint.parse('/tmp/howl.sock');
    expect(bareUnix.unixPath, '/tmp/howl.sock');
    expect(bareUnix.tcpPort, isNull);
    expect(bareUnix.toString(), 'unix:/tmp/howl.sock');

    final explicitUnix = HowlEndpoint.parse('unix:/tmp/howl.sock');
    expect(explicitUnix.unixPath, '/tmp/howl.sock');

    final tcp = HowlEndpoint.parse('tcp://127.0.0.1:43127');
    expect(tcp.unixPath, isNull);
    expect(tcp.tcpPort, 43127);
    expect(tcp.toString(), 'tcp://127.0.0.1:43127');

    for (final value in <String>[
      '',
      'tcp://localhost:43127',
      'http://127.0.0.1:43127',
      'unix:',
      'tcp://0.0.0.0:43127',
      'tcp://127.0.0.1',
      'tcp://127.0.0.1:0',
      'tcp://127.0.0.1:43127/',
      'tcp://127.0.0.1:43127?x=1',
    ]) {
      expect(
        () => HowlEndpoint.parse(value),
        throwsA(isA<HowlProtocolException>()),
        reason: value,
      );
    }
  });

  test('frozen hello and welcome vectors decode independently', () {
    final hello = decodeFrames(
      hexBytes(vector('hello_all_features')['hex'] as String),
    );
    expect(hello, hasLength(1));
    expect(hello.single.kind, HowlWire.hello);
    expect(hello.single.payload, hasLength(12));

    final welcomeFrames = decodeFrames(
      hexBytes(vector('welcome_all_features')['hex'] as String),
    );
    final welcome = decodeWelcome(welcomeFrames.single.payload);
    expect(welcome.version, 1);
    expect(welcome.features, 31);
    expect(welcome.clientId, 0x0102030405060708);
  });

  test('frozen text_v1 vector preserves rich semantic state', () {
    final snapshots = decodeTextSnapshots(
      hexBytes(vector('snapshot_text_v1_complete')['hex'] as String),
    );
    expect(snapshots, hasLength(1));
    final snapshot = snapshots.single;
    expect(snapshot.revision, 10);
    expect(snapshot.terminalRevision, 23);
    expect(snapshot.begin.rows, 1);
    expect(snapshot.begin.columns, 3);
    expect(snapshot.presentation.reverseScreen, isTrue);
    expect(snapshot.presentation.cursor?.r, 7);
    expect(snapshot.rows.single.wrapped, isTrue);

    final combining = snapshot.rows.single.cells[0];
    expect(combining.scalars, <int>[101, 769]);
    expect(combining.style, 133);
    expect(combining.foreground.kind, 2);
    expect(combining.foreground.value, 0x112233);
    expect(combining.background.kind, 1);
    expect(combining.background.value, 4);
    expect(combining.linkId, 1);

    final wideLead = snapshot.rows.single.cells[1];
    final wideContinuation = snapshot.rows.single.cells[2];
    expect(wideLead.scalars, <int>[0x4e2d]);
    expect(wideLead.width, 2);
    expect(wideLead.semanticWidth, isTrue);
    expect(wideContinuation.scalars, isEmpty);
    expect(wideContinuation.x, 1);
    expect(hyperlinkText(snapshot.hyperlinks[1]!), 'https://howl.example');
  });

  for (final id in <String>[
    'bad_magic',
    'payload_over_limit',
    'text_record_reserved_bit',
    'text_unknown_style_bit',
    'text_unresolved_hyperlink',
    'text_multiple_records_one_frame',
  ]) {
    test('hostile frozen vector $id keeps its contract error', () {
      final item = vector(id);
      final bytes = hexBytes(item['hex'] as String);
      final expected = item['error'] as String;
      try {
        if (id == 'bad_magic' || id == 'payload_over_limit') {
          decodeFrames(bytes);
        } else {
          decodeTextSnapshots(bytes);
        }
        fail('expected $expected');
      } on HowlProtocolException catch (error) {
        expect(error.code, expected);
      }
    });
  }

  test('committed text uses the bounded raw text input family', () {
    const text = 'café e\u0301 中 🐺';
    final payload = encodeCommittedTextInput(text);
    expect(payload.first, HowlWire.inputBytes);
    expect(utf8.decode(payload.sublist(1)), text);

    expect(
      () => encodeCommittedTextInput(''),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'committed_text_empty',
        ),
      ),
    );
    expect(
      () => encodeCommittedTextInput(String.fromCharCode(0xd800)),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'committed_text_unicode',
        ),
      ),
    );

    final maximum = List<String>.filled(
      HowlWire.maximumCommittedTextBytes,
      'x',
    ).join();
    expect(
      encodeCommittedTextInput(maximum),
      hasLength(HowlWire.maximumRequestPayloadBytes),
    );
    expect(
      () => encodeCommittedTextInput(
        '$maximum'
        'x',
      ),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'committed_text_limit',
        ),
      ),
    );
  });

  test('semantic mouse encoding matches the frozen pixel vector', () {
    final payload = encodeMouseInput(
      const HowlMouseInput(
        kind: HowlWire.mouseMove,
        button: HowlWire.mouseNone,
        modifiers: 2,
        buttonsDown: 5,
        row: -2,
        column: 0x1234,
        pixelX: 0x01020304,
        pixelY: 0xa1a2a3a4,
      ),
    );
    expect(payload, hexBytes('0403000205fffffffe12340101020304a1a2a3a4'));
    expect(
      () => encodeMouseInput(
        const HowlMouseInput(
          kind: HowlWire.mousePress,
          button: HowlWire.mouseLeft,
          modifiers: 0,
          buttonsDown: 8,
          row: 0,
          column: 0,
        ),
      ),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'mouse_buttons_down',
        ),
      ),
    );
    expect(
      () => encodeMouseInput(
        const HowlMouseInput(
          kind: HowlWire.mousePress,
          button: HowlWire.mouseLeft,
          modifiers: 0,
          buttonsDown: 1,
          row: 0,
          column: 0,
          pixelX: 1,
        ),
      ),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'mouse_pixels',
        ),
      ),
    );
  });

  test('live client dimensions are explicitly bounded', () {
    validateClientDimensions(1, 1);
    validateClientDimensions(HowlWire.maximumRows, HowlWire.maximumColumns);
    expect(
      () => validateClientDimensions(HowlWire.maximumRows + 1, 80),
      throwsA(
        isA<HowlProtocolException>().having(
          (error) => error.code,
          'code',
          'snapshot_dimensions',
        ),
      ),
    );
  });
}
