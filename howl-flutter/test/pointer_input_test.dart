import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/pointer_input.dart';
import 'package:howl_flutter/howl_input.dart';

void main() {
  const geometry = TerminalPointerGeometry(
    viewport: Size(1000, 600),
    rows: 20,
    columns: 80,
    cellWidth: 10,
    rowHeight: 20,
  );

  test('centered terminal geometry maps cells and logical pixels exactly', () {
    final topLeft = geometry.locate(const Offset(100, 100));
    expect(topLeft?.row, 0);
    expect(topLeft?.column, 0);
    expect(topLeft?.pixelX, 0);
    expect(topLeft?.pixelY, 0);

    final middle = geometry.locate(const Offset(505, 310));
    expect(middle?.row, 10);
    expect(middle?.column, 40);
    expect(middle?.pixelX, 405);
    expect(middle?.pixelY, 210);

    expect(geometry.locate(const Offset(99, 100)), isNull);
    expect(geometry.locate(const Offset(900, 100)), isNull);
  });

  test('clipped terminal geometry refuses guessed coordinates', () {
    const clipped = TerminalPointerGeometry(
      viewport: Size(700, 300),
      rows: 20,
      columns: 80,
      cellWidth: 10,
      rowHeight: 20,
    );
    expect(clipped.locate(const Offset(350, 150)), isNull);
  });

  test('mouse press drag and release preserve canonical held-button mask', () {
    final adapter = TerminalPointerAdapter();
    final press = adapter.translate(
      const PointerDownEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        position: Offset(505, 310),
        buttons: kSecondaryMouseButton,
      ),
      geometry: geometry,
      modifiers: 5,
    );
    expect(press, hasLength(1));
    expect(press.single.kind, HowlInput.mousePress);
    expect(press.single.button, HowlInput.mouseRight);
    expect(press.single.buttonsDown, 4);
    expect(press.single.modifiers, 5);

    final move = adapter.translate(
      const PointerMoveEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        position: Offset(515, 330),
        buttons: kSecondaryMouseButton,
      ),
      geometry: geometry,
      modifiers: 0,
    );
    expect(move.single.kind, HowlInput.mouseMove);
    expect(move.single.button, HowlInput.mouseNone);
    expect(move.single.buttonsDown, 4);
    expect(move.single.row, 11);
    expect(move.single.column, 41);

    final release = adapter.translate(
      const PointerUpEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        position: Offset(1200, 900),
      ),
      geometry: geometry,
      modifiers: 0,
    );
    expect(release, hasLength(1));
    expect(release.single.kind, HowlInput.mouseRelease);
    expect(release.single.button, HowlInput.mouseRight);
    expect(release.single.buttonsDown, 0);
    expect(release.single.row, 11);
    expect(release.single.column, 41);
  });

  test('mouse hover emits an unheld semantic move', () {
    final adapter = TerminalPointerAdapter();
    final hover = adapter.translate(
      const PointerHoverEvent(
        pointer: 8,
        kind: PointerDeviceKind.mouse,
        position: Offset(505, 310),
      ),
      geometry: geometry,
      modifiers: 2,
    );
    expect(hover, hasLength(1));
    expect(hover.single.kind, HowlInput.mouseMove);
    expect(hover.single.button, HowlInput.mouseNone);
    expect(hover.single.buttonsDown, 0);
    expect(hover.single.modifiers, 2);
    expect(hover.single.row, 10);
    expect(hover.single.column, 40);
  });

  test('stylus semantic operations map without device-specific invention', () {
    final adapter = TerminalPointerAdapter();
    final inputs = adapter.translate(
      const PointerDownEvent(
        pointer: 9,
        kind: PointerDeviceKind.stylus,
        position: Offset(200, 200),
        buttons: kStylusContact | kPrimaryStylusButton,
      ),
      geometry: geometry,
      modifiers: 0,
    );
    expect(inputs.map((input) => input.button), <int>[
      HowlInput.mouseLeft,
      HowlInput.mouseRight,
    ]);
    expect(inputs.map((input) => input.buttonsDown), <int>[1, 5]);
  });

  test('touch, wheel signals, and unsupported side buttons stay local', () {
    final adapter = TerminalPointerAdapter();
    expect(
      adapter.translate(
        const PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          position: Offset(500, 300),
        ),
        geometry: geometry,
        modifiers: 0,
      ),
      isEmpty,
    );
    expect(
      adapter.translate(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(500, 300),
          scrollDelta: Offset(0, 10),
        ),
        geometry: geometry,
        modifiers: 0,
      ),
      isEmpty,
    );
    expect(
      adapter.translate(
        const PointerDownEvent(
          pointer: 3,
          kind: PointerDeviceKind.mouse,
          position: Offset(500, 300),
          buttons: kBackMouseButton,
        ),
        geometry: geometry,
        modifiers: 0,
      ),
      isEmpty,
    );
  });

  test('cancel releases every represented button at last valid location', () {
    final adapter = TerminalPointerAdapter();
    adapter.translate(
      const PointerDownEvent(
        pointer: 4,
        kind: PointerDeviceKind.mouse,
        position: Offset(500, 300),
        buttons: kPrimaryMouseButton | kMiddleMouseButton,
      ),
      geometry: geometry,
      modifiers: 0,
    );
    final releases = adapter.translate(
      const PointerCancelEvent(
        pointer: 4,
        kind: PointerDeviceKind.mouse,
        position: Offset(1500, 900),
      ),
      geometry: geometry,
      modifiers: 0,
    );
    expect(releases.map((input) => input.button), <int>[
      HowlInput.mouseLeft,
      HowlInput.mouseMiddle,
    ]);
    expect(releases.map((input) => input.buttonsDown), <int>[2, 0]);
  });
}
