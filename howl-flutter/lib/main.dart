import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform_input.dart';
import 'history_viewport.dart';
import 'launch_config.dart';
import 'pointer_input.dart';
import 'protocol.dart';
import 'text_input.dart';
import 'terminal_glyph_cache.dart';
import 'touch_surface.dart';
import 'visible_viewport.dart';

void main(List<String> args) {
  const compiledEndpoint = String.fromEnvironment('HOWL_ENDPOINT');
  final endpointText = args.isNotEmpty
      ? args.first
      : compiledEndpoint.isNotEmpty
      ? compiledEndpoint
      : Platform.environment['HOWL_ENDPOINT'] ??
            Platform.environment['HOWL_SOCKET'];
  if (endpointText == null || endpointText.isEmpty) {
    stderr.writeln(
      'usage: howl_flutter ENDPOINT   (or set HOWL_ENDPOINT / --dart-define)',
    );
    exitCode = 64;
    return;
  }
  final HowlEndpoint endpoint;
  try {
    endpoint = HowlEndpoint.parse(endpointText);
  } on HowlProtocolException catch (error) {
    stderr.writeln('invalid Howl endpoint: ${error.code}');
    exitCode = 64;
    return;
  }
  const compiledGeometryLeader = String.fromEnvironment('HOWL_GEOMETRY_LEADER');
  runApp(
    HowlApp(
      endpoint: endpoint,
      geometryLeader: geometryLeaderEnabled(
        compiledValue: compiledGeometryLeader,
        environmentValue: Platform.environment['HOWL_GEOMETRY_LEADER'],
      ),
    ),
  );
}

final class HowlApp extends StatelessWidget {
  const HowlApp({
    super.key,
    required this.endpoint,
    required this.geometryLeader,
  });
  final HowlEndpoint endpoint;
  final bool geometryLeader;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Howl',
    theme: ThemeData.dark(useMaterial3: false),
    home: HowlTerminal(endpoint: endpoint, geometryLeader: geometryLeader),
  );
}

final class HowlTerminal extends StatefulWidget {
  const HowlTerminal({
    super.key,
    required this.endpoint,
    required this.geometryLeader,
  });
  final HowlEndpoint endpoint;
  final bool geometryLeader;

  @override
  State<HowlTerminal> createState() => _HowlTerminalState();
}

final class _HowlTerminalState extends State<HowlTerminal> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Howl terminal');
  final TerminalPlatformInput _platformInput = const TerminalPlatformInput();
  final TerminalPointerAdapter _pointerInput = TerminalPointerAdapter();
  final HistoryViewport _history = HistoryViewport();
  final TerminalGlyphCache _glyphCache = TerminalGlyphCache();
  late final TerminalTextInputClient _textInput;
  HowlConnection? _observer;
  HowlConnection? _historyObserver;
  HowlConnection? _control;
  HowlSnapshot? _liveSnapshot;
  HowlSnapshot? _snapshot;
  Object? _failure;
  bool _stopping = false;
  bool _historyRequestRunning = false;
  bool _historyRequestPending = false;
  int _historyGeneration = 0;
  bool _leaderAssigned = false;
  int _proposedRows = 0;
  int _proposedColumns = 0;
  Future<void> _controlTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _textInput = TerminalTextInputClient(
      inputType: _platformInput.inputType,
      onCommit: (text) {
        _returnToLiveForInput();
        _queueControl((control) => control.sendCommittedText(text));
      },
      onEditKey: (key) {
        _returnToLiveForInput();
        final keyName = switch (key) {
          TerminalEditKey.enter => HowlWire.namedEnter,
          TerminalEditKey.backspace => HowlWire.namedBackspace,
          TerminalEditKey.delete => HowlWire.namedDelete,
        };
        _queueControl(
          (control) =>
              control.sendNamedKey(keyName: keyName, action: HowlWire.keyPress),
        );
      },
    );
    unawaited(_observe());
  }

  Future<void> _observe() async {
    try {
      final observer = await HowlConnection.connect(widget.endpoint);
      final control = await HowlConnection.connect(widget.endpoint);
      if (!mounted || _stopping) {
        observer.close();
        control.close();
        return;
      }
      _observer = observer;
      _control = control;
      if (_focusNode.hasFocus) {
        _textInput.attach(viewId: View.of(context).viewId);
        _scheduleTextInputShow();
        _queueControl((control) => control.sendFocus(true));
      }
      var revision = 0;
      while (!_stopping) {
        final next = await observer.observeText(revision);
        revision = next.revision;
        if (!mounted || _stopping) break;
        _liveSnapshot = next;
        if (_history.active) {
          _history.followLive(
            historyCount: next.begin.historyCount,
            historyRowBase: next.begin.historyRowBase,
            alternateScreen: next.begin.alternateScreen,
          );
          _historyGeneration += 1;
          if (_history.active) {
            _scheduleHistorySnapshot();
          } else {
            _leaveHistory();
          }
        } else {
          setState(() => _snapshot = next);
        }
        // PTY/VT progress is independent of observers. Do not request and decode
        // terminal revisions faster than Flutter can present them.
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (error) {
      _reportFailure(error);
    }
  }

  void _reportFailure(Object error) {
    if (!mounted || _stopping) return;
    setState(() => _failure = error);
  }

  void _queueControl(Future<void> Function(HowlConnection) action) {
    final control = _control;
    if (control == null || _stopping) return;
    _controlTail = _controlTail.then((_) => action(control));
    _controlTail = _controlTail.catchError((Object error) {
      _reportFailure(error);
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyName = howlNamedKey(event.physicalKey);
    if (keyName == null) return KeyEventResult.ignored;
    _returnToLiveForInput();
    final action = switch (event) {
      KeyDownEvent() => HowlWire.keyPress,
      KeyRepeatEvent() => HowlWire.keyRepeat,
      KeyUpEvent() => HowlWire.keyRelease,
      _ => HowlWire.keyPress,
    };
    final modifiers = howlModifierBits();
    _queueControl(
      (control) => control.sendNamedKey(
        keyName: keyName,
        action: action,
        modifiers: modifiers,
      ),
    );
    return KeyEventResult.handled;
  }

  void _scheduleTextInputShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stopping || !_focusNode.hasFocus || _control == null) {
        return;
      }
      unawaited(_showTextInput());
    });
  }

  Future<void> _showTextInput() async {
    try {
      await _textInput.show(_platformInput);
    } catch (error) {
      _reportFailure(error);
    }
  }

  void _activateTextInput() {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    if (_control == null) return;
    _textInput.attach(viewId: View.of(context).viewId);
    _scheduleTextInputShow();
  }

  void _onPointerDown(PointerDownEvent event, Size viewport) {
    if (event.kind == PointerDeviceKind.touch) return;
    _activateTextInput();
    _sendPointer(event, viewport);
  }

  void _onPointerMove(PointerMoveEvent event, Size viewport) {
    if (_history.active) return;
    _sendPointer(event, viewport);
  }

  void _onPointerHover(PointerHoverEvent event, Size viewport) {
    if (_history.active) return;
    _sendPointer(event, viewport);
  }

  void _onPointerUp(PointerUpEvent event, Size viewport) {
    _sendPointer(event, viewport);
  }

  void _onPointerCancel(PointerCancelEvent event, Size viewport) {
    _sendPointer(event, viewport);
  }

  void _sendPointer(PointerEvent event, Size viewport) {
    final snapshot = _liveSnapshot;
    if (snapshot == null) return;
    final events = _pointerInput.translate(
      event,
      geometry: TerminalPointerGeometry(
        viewport: viewport,
        rows: snapshot.begin.rows,
        columns: snapshot.begin.columns,
        cellWidth: TerminalPainter.cellWidth,
        rowHeight: TerminalPainter.lineHeight,
      ),
      modifiers: howlModifierBits(),
    );
    if (events.isEmpty) return;
    _returnToLiveForInput();
    for (final input in events) {
      _queueControl((control) => control.sendMouse(input));
    }
  }

  void _beginHistoryDrag(DragStartDetails _) {
    _history.beginDrag();
  }

  void _updateHistoryDrag(DragUpdateDetails details) {
    final live = _liveSnapshot;
    final deltaY = details.primaryDelta;
    if (live == null || deltaY == null) return;
    final changed = _history.drag(
      deltaY: deltaY,
      rowHeight: TerminalPainter.lineHeight,
      historyCount: live.begin.historyCount,
      historyRowBase: live.begin.historyRowBase,
      alternateScreen: live.begin.alternateScreen,
    );
    if (!changed) return;
    _historyGeneration += 1;
    if (_history.active) {
      _scheduleHistorySnapshot();
    } else {
      _leaveHistory();
    }
  }

  void _endHistoryDrag(DragEndDetails _) {
    _history.endDrag();
  }

  void _scheduleHistorySnapshot() {
    if (_stopping || !_history.active) return;
    if (_historyRequestRunning) {
      _historyRequestPending = true;
      return;
    }
    unawaited(_drainHistorySnapshots());
  }

  Future<void> _drainHistorySnapshots() async {
    if (_historyRequestRunning || _stopping || !_history.active) return;
    _historyRequestRunning = true;
    try {
      while (!_stopping && _history.active) {
        _historyRequestPending = false;
        final generation = _historyGeneration;
        var historyObserver = _historyObserver;
        if (historyObserver == null) {
          final connected = await HowlConnection.connect(widget.endpoint);
          if (!mounted || _stopping || !_history.active) {
            connected.close();
            return;
          }
          _historyObserver = connected;
          historyObserver = connected;
        }

        final next = await historyObserver.observeText(
          0,
          historyOffset: _history.targetOffset,
        );
        if (!mounted || _stopping || !_history.active) return;
        if (generation != _historyGeneration) continue;

        _history.acceptSnapshot(
          historyOffset: next.begin.historyOffset,
          historyCount: next.begin.historyCount,
          historyRowBase: next.begin.historyRowBase,
          alternateScreen: next.begin.alternateScreen,
        );
        if (!_history.active) {
          _leaveHistory();
          return;
        }
        setState(() => _snapshot = next);
        if (generation == _historyGeneration) return;
      }
    } catch (error) {
      if (!_stopping && _history.active) {
        _leaveHistory();
        _reportFailure(error);
      }
    } finally {
      _historyRequestRunning = false;
      if (_historyRequestPending && !_stopping && _history.active) {
        _historyRequestPending = false;
        _scheduleHistorySnapshot();
      }
    }
  }

  void _returnToLiveForInput() {
    if (_history.active) _leaveHistory();
  }

  void _leaveHistory() {
    _history.reset();
    _historyGeneration += 1;
    _historyRequestPending = false;
    final historyObserver = _historyObserver;
    _historyObserver = null;
    historyObserver?.close();
    final live = _liveSnapshot;
    if (mounted && !_stopping && live != null) {
      setState(() => _snapshot = live);
    }
  }

  void _onFocusChange(bool focused) {
    if (focused && _control != null) {
      _textInput.attach(viewId: View.of(context).viewId);
      _scheduleTextInputShow();
    } else {
      _textInput.detach();
    }
    _queueControl((control) => control.sendFocus(focused));
  }

  void _proposeGeometry(Size size) {
    if (!widget.geometryLeader ||
        !size.width.isFinite ||
        !size.height.isFinite) {
      return;
    }
    final rows = (size.height / TerminalPainter.lineHeight)
        .floor()
        .clamp(1, HowlWire.maximumRows)
        .toInt();
    final columns = (size.width / TerminalPainter.cellWidth)
        .floor()
        .clamp(1, HowlWire.maximumColumns)
        .toInt();
    if (rows == _proposedRows && columns == _proposedColumns) return;
    _proposedRows = rows;
    _proposedColumns = columns;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queueControl((control) async {
        if (!_leaderAssigned) {
          await control.assignLeader(control.welcome.clientId);
          _leaderAssigned = true;
        }
        await control.resize(rows, columns);
      });
    });
  }

  @override
  void dispose() {
    _stopping = true;
    _textInput.detach();
    _focusNode.dispose();
    _glyphCache.dispose();
    _observer?.close();
    _historyObserver?.close();
    _control?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    final failure = _failure;
    final snapshot = _snapshot;
    if (failure != null) {
      content = ColoredBox(
        color: const Color(0xff090b0e),
        child: Center(
          child: Text(
            'Howl attach failed\n$failure',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      );
    } else if (snapshot == null) {
      content = const ColoredBox(
        color: Color(0xff090b0e),
        child: Center(child: Text('attaching to Howl…')),
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          _proposeGeometry(constraints.biggest);
          return ColoredBox(
            color: rgbaColor(snapshot.presentation.background),
            child: Center(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(
                    snapshot.begin.columns * TerminalPainter.cellWidth,
                    snapshot.begin.rows * TerminalPainter.lineHeight,
                  ),
                  painter: TerminalPainter(snapshot, _glyphCache),
                ),
              ),
            ),
          );
        },
      );
    }
    return TerminalVisibleViewport(
      child: LayoutBuilder(
        builder: (context, constraints) => TerminalTouchSurface(
          onTap: _activateTextInput,
          onVerticalDragStart: _beginHistoryDrag,
          onVerticalDragUpdate: _updateHistoryDrag,
          onVerticalDragEnd: _endHistoryDrag,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) =>
                _onPointerDown(event, constraints.biggest),
            onPointerMove: (event) =>
                _onPointerMove(event, constraints.biggest),
            onPointerHover: (event) =>
                _onPointerHover(event, constraints.biggest),
            onPointerUp: (event) => _onPointerUp(event, constraints.biggest),
            onPointerCancel: (event) =>
                _onPointerCancel(event, constraints.biggest),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onFocusChange: _onFocusChange,
              onKeyEvent: _onKeyEvent,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

final class TerminalPainter extends CustomPainter {
  TerminalPainter(this.snapshot, this.glyphCache);

  static const cellWidth = 10.0;
  static const lineHeight = 20.0;
  static const fontSize = 16.0;

  final HowlSnapshot snapshot;
  final TerminalGlyphCache glyphCache;

  @override
  void paint(Canvas canvas, Size size) {
    final presentation = snapshot.presentation;
    final defaultBackground = rgbaColor(presentation.background);
    canvas.drawRect(Offset.zero & size, Paint()..color = defaultBackground);

    for (var rowIndex = 0; rowIndex < snapshot.rows.length; rowIndex++) {
      final row = snapshot.rows[rowIndex];
      for (var column = 0; column < row.cells.length; column++) {
        final cell = row.cells[column];
        var foreground = semanticColor(
          cell.foreground,
          presentation,
          foreground: true,
        );
        var background = semanticColor(
          cell.background,
          presentation,
          foreground: false,
        );
        if (cell.style & (1 << 5) != 0) {
          final swap = foreground;
          foreground = background;
          background = swap;
        }
        if (presentation.reverseScreen) {
          final swap = foreground;
          foreground = background;
          background = swap;
        }
        if (cell.style & (1 << 1) != 0) {
          foreground = foreground.withValues(alpha: foreground.a * 0.55);
        }

        final rect = Rect.fromLTWH(
          column * cellWidth,
          rowIndex * lineHeight,
          cellWidth,
          lineHeight,
        );
        if (background != defaultBackground) {
          canvas.drawRect(rect, Paint()..color = background);
        }
        if (!cell.isLead ||
            cell.scalars.isEmpty ||
            cell.style & (1 << 6) != 0) {
          continue;
        }

        final painter = glyphCache.resolve(
          text: String.fromCharCodes(cell.scalars),
          foreground: foreground,
          style: cell.style,
          underlineStyle: cell.underlineStyle,
          underlineColor: semanticColor(
            cell.underlineColor,
            presentation,
            foreground: true,
          ),
          maxWidth: cellWidth * cell.width,
          fontSize: fontSize,
        );
        painter.paint(
          canvas,
          Offset(
            column * cellWidth,
            rowIndex * lineHeight + (lineHeight - painter.height) / 2,
          ),
        );
      }
    }
    paintCursor(canvas);
  }

  void paintCursor(Canvas canvas) {
    final begin = snapshot.begin;
    if (!begin.cursorVisible || begin.cursorShape == 3) return;
    if (begin.cursorRow >= begin.rows || begin.cursorColumn >= begin.columns) {
      return;
    }
    final color = rgbaColor(
      snapshot.presentation.cursor ?? snapshot.presentation.foreground,
    );
    final left = begin.cursorColumn * cellWidth;
    final top = begin.cursorRow * lineHeight;
    final paint = Paint()..color = color;
    switch (begin.cursorShape) {
      case 1:
        canvas.drawRect(
          Rect.fromLTWH(left, top + lineHeight - 2, cellWidth, 2),
          paint,
        );
      case 2:
        canvas.drawRect(Rect.fromLTWH(left, top, 2, lineHeight), paint);
      default:
        canvas.drawRect(
          Rect.fromLTWH(left, top, cellWidth, lineHeight),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) =>
      oldDelegate.snapshot.revision != snapshot.revision ||
      oldDelegate.snapshot.terminalRevision != snapshot.terminalRevision;
}

Color semanticColor(
  HowlSemanticColor value,
  HowlPresentation presentation, {
  required bool foreground,
}) => switch (value.kind) {
  0 => rgbaColor(
    foreground ? presentation.foreground : presentation.background,
  ),
  1 => rgbaColor(presentation.palette[value.value]),
  2 => Color.fromARGB(
    0xff,
    (value.value >> 16) & 0xff,
    (value.value >> 8) & 0xff,
    value.value & 0xff,
  ),
  _ => const Color(0xffff00ff),
};

Color rgbaColor(HowlRgba value) =>
    Color.fromARGB(value.a, value.r, value.g, value.b);

final howlNamedKeys = <PhysicalKeyboardKey, int>{
  PhysicalKeyboardKey.enter: HowlWire.namedEnter,
  PhysicalKeyboardKey.tab: 2,
  PhysicalKeyboardKey.backspace: HowlWire.namedBackspace,
  PhysicalKeyboardKey.escape: 4,
  PhysicalKeyboardKey.arrowUp: 5,
  PhysicalKeyboardKey.arrowDown: 6,
  PhysicalKeyboardKey.arrowLeft: 7,
  PhysicalKeyboardKey.arrowRight: 8,
  PhysicalKeyboardKey.insert: 9,
  PhysicalKeyboardKey.delete: HowlWire.namedDelete,
  PhysicalKeyboardKey.home: 11,
  PhysicalKeyboardKey.end: 12,
  PhysicalKeyboardKey.pageUp: 13,
  PhysicalKeyboardKey.pageDown: 14,
  PhysicalKeyboardKey.shiftLeft: 15,
  PhysicalKeyboardKey.shiftRight: 16,
  PhysicalKeyboardKey.controlLeft: 17,
  PhysicalKeyboardKey.controlRight: 18,
  PhysicalKeyboardKey.altLeft: 19,
  PhysicalKeyboardKey.altRight: 20,
  PhysicalKeyboardKey.metaLeft: 21,
  PhysicalKeyboardKey.metaRight: 22,
  PhysicalKeyboardKey.capsLock: 27,
  PhysicalKeyboardKey.numLock: 28,
  PhysicalKeyboardKey.f1: 29,
  PhysicalKeyboardKey.f2: 30,
  PhysicalKeyboardKey.f3: 31,
  PhysicalKeyboardKey.f4: 32,
  PhysicalKeyboardKey.f5: 33,
  PhysicalKeyboardKey.f6: 34,
  PhysicalKeyboardKey.f7: 35,
  PhysicalKeyboardKey.f8: 36,
  PhysicalKeyboardKey.f9: 37,
  PhysicalKeyboardKey.f10: 38,
  PhysicalKeyboardKey.f11: 39,
  PhysicalKeyboardKey.f12: 40,
  PhysicalKeyboardKey.numpad0: 41,
  PhysicalKeyboardKey.numpad1: 42,
  PhysicalKeyboardKey.numpad2: 43,
  PhysicalKeyboardKey.numpad3: 44,
  PhysicalKeyboardKey.numpad4: 45,
  PhysicalKeyboardKey.numpad5: 46,
  PhysicalKeyboardKey.numpad6: 47,
  PhysicalKeyboardKey.numpad7: 48,
  PhysicalKeyboardKey.numpad8: 49,
  PhysicalKeyboardKey.numpad9: 50,
  PhysicalKeyboardKey.numpadDecimal: 51,
  PhysicalKeyboardKey.numpadAdd: 52,
  PhysicalKeyboardKey.numpadSubtract: 53,
  PhysicalKeyboardKey.numpadMultiply: 54,
  PhysicalKeyboardKey.numpadDivide: 55,
  PhysicalKeyboardKey.numpadComma: 56,
  PhysicalKeyboardKey.numpadEqual: 57,
  PhysicalKeyboardKey.numpadEnter: 58,
};

int? howlNamedKey(PhysicalKeyboardKey key) => howlNamedKeys[key];

int howlModifierBits() {
  final keyboard = HardwareKeyboard.instance;
  var result = 0;
  if (keyboard.isShiftPressed) result |= 1 << 0;
  if (keyboard.isAltPressed) result |= 1 << 1;
  if (keyboard.isControlPressed) result |= 1 << 2;
  if (keyboard.isMetaPressed) result |= 1 << 3;
  if (keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock)) {
    result |= 1 << 6;
  }
  if (keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock)) {
    result |= 1 << 7;
  }
  return result;
}
