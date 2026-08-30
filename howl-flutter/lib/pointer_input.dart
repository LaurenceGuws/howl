import 'dart:ui';

import 'package:flutter/gestures.dart';

import 'protocol.dart';

final class TerminalPointerLocation {
  const TerminalPointerLocation({
    required this.row,
    required this.column,
    required this.pixelX,
    required this.pixelY,
  });

  final int row;
  final int column;
  final int pixelX;
  final int pixelY;
}

final class TerminalPointerGeometry {
  const TerminalPointerGeometry({
    required this.viewport,
    required this.rows,
    required this.columns,
    required this.cellWidth,
    required this.rowHeight,
  });

  final Size viewport;
  final int rows;
  final int columns;
  final double cellWidth;
  final double rowHeight;

  TerminalPointerLocation? locate(Offset position) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        rows <= 0 ||
        columns <= 0 ||
        cellWidth <= 0 ||
        rowHeight <= 0) {
      return null;
    }
    final terminalWidth = columns * cellWidth;
    final terminalHeight = rows * rowHeight;
    if (terminalWidth > viewport.width || terminalHeight > viewport.height) {
      return null;
    }
    final left = (viewport.width - terminalWidth) / 2;
    final top = (viewport.height - terminalHeight) / 2;
    final x = position.dx - left;
    final y = position.dy - top;
    if (x < 0 || y < 0 || x >= terminalWidth || y >= terminalHeight) {
      return null;
    }
    return TerminalPointerLocation(
      row: (y / rowHeight).floor(),
      column: (x / cellWidth).floor(),
      pixelX: x.floor(),
      pixelY: y.floor(),
    );
  }
}

final class TerminalPointerAdapter {
  final Map<int, _PointerState> _states = <int, _PointerState>{};

  List<HowlMouseInput> translate(
    PointerEvent event, {
    required TerminalPointerGeometry geometry,
    required int modifiers,
  }) {
    if (!_supportedKind(event.kind) || event is PointerSignalEvent) {
      return const <HowlMouseInput>[];
    }

    final previous = _states[event.pointer];
    final mapped = geometry.locate(event.localPosition);
    final location = mapped ?? previous?.location;
    final current = _howlButtons(event.buttons);
    final before = previous?.buttons ?? 0;

    if (event is PointerCancelEvent) {
      _states.remove(event.pointer);
      if (location == null) return const <HowlMouseInput>[];
      return _releaseTransitions(
        before,
        0,
        location: location,
        modifiers: modifiers,
      );
    }

    if (mapped != null || previous != null) {
      if (current == 0 && event is PointerUpEvent) {
        _states.remove(event.pointer);
      } else {
        _states[event.pointer] = _PointerState(
          buttons: current,
          location: mapped ?? previous!.location,
        );
      }
    }
    if (location == null) return const <HowlMouseInput>[];

    if (event is PointerDownEvent) {
      return _pressTransitions(
        before,
        current,
        location: location,
        modifiers: modifiers,
      );
    }
    if (event is PointerUpEvent) {
      return _releaseTransitions(
        before,
        current,
        location: location,
        modifiers: modifiers,
      );
    }
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      if (mapped == null) return const <HowlMouseInput>[];
      return <HowlMouseInput>[
        _input(
          kind: HowlWire.mouseMove,
          button: HowlWire.mouseNone,
          buttonsDown: current,
          location: location,
          modifiers: modifiers,
        ),
      ];
    }
    return const <HowlMouseInput>[];
  }

  List<HowlMouseInput> _pressTransitions(
    int before,
    int after, {
    required TerminalPointerLocation location,
    required int modifiers,
  }) {
    final changed = after & ~before;
    if (changed == 0) return const <HowlMouseInput>[];
    final output = <HowlMouseInput>[];
    var held = before;
    for (final bit in const <int>[1, 2, 4]) {
      if (changed & bit == 0) continue;
      held |= bit;
      output.add(
        _input(
          kind: HowlWire.mousePress,
          button: _buttonForBit(bit),
          buttonsDown: held,
          location: location,
          modifiers: modifiers,
        ),
      );
    }
    return output;
  }

  List<HowlMouseInput> _releaseTransitions(
    int before,
    int after, {
    required TerminalPointerLocation location,
    required int modifiers,
  }) {
    final changed = before & ~after;
    if (changed == 0) return const <HowlMouseInput>[];
    final output = <HowlMouseInput>[];
    var held = before;
    for (final bit in const <int>[1, 2, 4]) {
      if (changed & bit == 0) continue;
      held &= ~bit;
      output.add(
        _input(
          kind: HowlWire.mouseRelease,
          button: _buttonForBit(bit),
          buttonsDown: held,
          location: location,
          modifiers: modifiers,
        ),
      );
    }
    return output;
  }

  HowlMouseInput _input({
    required int kind,
    required int button,
    required int buttonsDown,
    required TerminalPointerLocation location,
    required int modifiers,
  }) => HowlMouseInput(
    kind: kind,
    button: button,
    modifiers: modifiers,
    buttonsDown: buttonsDown,
    row: location.row,
    column: location.column,
    pixelX: location.pixelX,
    pixelY: location.pixelY,
  );
}

final class _PointerState {
  const _PointerState({required this.buttons, required this.location});

  final int buttons;
  final TerminalPointerLocation location;
}

bool _supportedKind(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.mouse ||
    kind == PointerDeviceKind.stylus ||
    kind == PointerDeviceKind.invertedStylus;

int _howlButtons(int flutterButtons) {
  var result = 0;
  if (flutterButtons & kPrimaryButton != 0) result |= 1;
  if (flutterButtons & kTertiaryButton != 0) result |= 2;
  if (flutterButtons & kSecondaryButton != 0) result |= 4;
  return result;
}

int _buttonForBit(int bit) => switch (bit) {
  1 => HowlWire.mouseLeft,
  2 => HowlWire.mouseMiddle,
  4 => HowlWire.mouseRight,
  _ => HowlWire.mouseNone,
};
