import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform_input.dart';
import 'history_viewport.dart';
import 'howl_endpoint.dart';
import 'howl_input.dart';
import 'launch_config.dart';
import 'native_canvas_surface.dart';
import 'native_host.dart';
import 'pointer_input.dart';
import 'text_input.dart';
import 'terminal_status.dart';
import 'touch_surface.dart';
import 'visible_viewport.dart';

const double terminalCellWidth = 10;
const double terminalLineHeight = 20;

Future<void> main(List<String> args) async {
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
  } on HowlEndpointException catch (error) {
    stderr.writeln('invalid Howl endpoint: ${error.code}');
    exitCode = 64;
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();

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
  late final TerminalTextInputClient _textInput;
  NativeHostObserver? _nativeObserver;
  NativeHostObserver? _nativeHistoryObserver;
  NativeHostControl? _nativeControl;
  NativeHostMetadata? _nativeLiveMetadata;
  NativeHostMetadata? _nativeHistoryMetadata;
  NativeCanvasLease? _nativeLiveLease;
  NativeCanvasLease? _nativeHistoryLease;
  Object? _failure;
  bool _stopping = false;
  bool _historyRequestRunning = false;
  bool _historyRequestPending = false;
  int _historyGeneration = 0;
  int _proposedRows = 0;
  int _proposedColumns = 0;
  int? _pendingResizeRows;
  int? _pendingResizeColumns;
  bool _resizeDrainRunning = false;
  Future<void> _controlTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _textInput = TerminalTextInputClient(
      inputType: _platformInput.inputType,
      onCommit: (text) {
        _returnToLiveForInput();
        _sendCommittedText(text);
      },
      onEditKey: (key) {
        _returnToLiveForInput();
        final keyName = switch (key) {
          TerminalEditKey.enter => HowlInput.namedEnter,
          TerminalEditKey.backspace => HowlInput.namedBackspace,
          TerminalEditKey.delete => HowlInput.namedDelete,
        };
        _sendNamedKey(keyName: keyName, action: HowlInput.keyPress);
      },
    );
    unawaited(_observe());
  }

  Future<void> _observe() => _observeNative();

  Future<void> _observeNative() async {
    try {
      final observer = await NativeHostObserver.createPlatform(
        endpoint: widget.endpoint.toString(),
        armNextLiveObservation: true,
      );
      final control = await NativeHostControl.create(
        endpoint: widget.endpoint.toString(),
      );
      if (!mounted || _stopping) {
        unawaited(observer.close());
        unawaited(control.close());
        return;
      }
      _nativeObserver = observer;
      _nativeControl = control;
      if (_focusNode.hasFocus) {
        _textInput.attach(viewId: View.of(context).viewId);
        _scheduleTextInputShow();
        _sendFocus(true);
      }
      var revision = 0;
      var pendingObservation = observer.observe(
        afterRevision: revision,
        historyOffset: 0,
        residency: encodeNativeHostResidency(_nativeLiveLease),
      );
      while (!_stopping) {
        final bytes = await pendingObservation;
        final packet = parseNativeHostPacket(bytes);
        revision = packet.metadata.revision;
        if (!mounted || _stopping) break;
        final prepared = await prepareNativeCanvasFrame(
          _nativeLiveLease,
          packet.canvas,
        );
        if (!mounted || _stopping) {
          disposeNativeCanvasLease(prepared.lease);
          break;
        }
        _nativeLiveMetadata = packet.metadata;
        _nativeLiveLease = prepared.lease;
        if (_history.active) {
          _history.followLive(
            historyCount: packet.metadata.historyCount,
            historyRowBase: packet.metadata.historyRowBase,
            alternateScreen: packet.metadata.alternateScreen,
          );
          _historyGeneration += 1;
          if (_history.active) {
            _scheduleHistorySnapshot();
            setState(() {});
          } else {
            _leaveHistory();
          }
        } else {
          setState(() {});
        }
        pendingObservation = observer.observe(
          afterRevision: revision,
          historyOffset: 0,
          residency: encodeNativeHostResidency(_nativeLiveLease),
        );
        await WidgetsBinding.instance.endOfFrame;
        for (final image in prepared.retired) {
          image.dispose();
        }
      }
    } catch (error) {
      _reportFailure(error);
    }
  }

  void _reportFailure(Object error) {
    if (!mounted || _stopping) return;
    setState(() => _failure = error);
  }

  bool get _hasControl => _nativeControl != null;

  Future<void> _queueControl(Future<void> Function(NativeHostControl) action) {
    if (_stopping) return Future<void>.value();
    final control = _nativeControl;
    if (control == null) return Future<void>.value();
    _controlTail = _controlTail.then((_) => action(control));
    _controlTail = _controlTail.catchError((Object error) {
      _reportFailure(error);
    });
    return _controlTail;
  }

  void _sendCommittedText(String text) {
    _queueControl((control) => control.committedText(text));
  }

  void _sendNamedKey({
    required int keyName,
    required int action,
    int modifiers = 0,
  }) {
    _queueControl(
      (control) => control.namedKey(
        keyName: keyName,
        action: action,
        modifiers: modifiers,
      ),
    );
  }

  void _sendFocus(bool focused) {
    _queueControl((control) => control.focus(focused));
  }

  void _sendMouse(HowlMouseInput input) {
    _queueControl(
      (control) => control.mouse(
        kind: input.kind,
        button: input.button,
        modifiers: input.modifiers,
        buttonsDown: input.buttonsDown,
        row: input.row,
        column: input.column,
        pixelX: input.pixelX,
        pixelY: input.pixelY,
      ),
    );
  }

  void _sendResize(int rows, int columns) {
    _pendingResizeRows = rows;
    _pendingResizeColumns = columns;
    if (_resizeDrainRunning || !_hasControl || _stopping) return;
    _resizeDrainRunning = true;
    unawaited(_drainResize());
  }

  Future<void> _drainResize() async {
    try {
      while (!_stopping && _pendingResizeRows != null) {
        final rows = _pendingResizeRows!;
        final columns = _pendingResizeColumns!;
        _pendingResizeRows = null;
        _pendingResizeColumns = null;
        await _queueControl((control) => control.resize(rows, columns));
      }
    } finally {
      _resizeDrainRunning = false;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyName = howlNamedKey(event.physicalKey);
    if (keyName == null) return KeyEventResult.ignored;
    _returnToLiveForInput();
    final action = switch (event) {
      KeyDownEvent() => HowlInput.keyPress,
      KeyRepeatEvent() => HowlInput.keyRepeat,
      KeyUpEvent() => HowlInput.keyRelease,
      _ => HowlInput.keyPress,
    };
    final modifiers = howlModifierBits();
    _sendNamedKey(keyName: keyName, action: action, modifiers: modifiers);
    return KeyEventResult.handled;
  }

  void _scheduleTextInputShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stopping || !_focusNode.hasFocus || !_hasControl) {
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
    if (!_hasControl) return;
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
    final metadata = _nativeLiveMetadata;
    final rows = metadata?.rows;
    final columns = metadata?.columns;
    if (rows == null || columns == null) return;
    final events = _pointerInput.translate(
      event,
      geometry: TerminalPointerGeometry(
        viewport: viewport,
        rows: rows,
        columns: columns,
        cellWidth: terminalCellWidth,
        rowHeight: terminalLineHeight,
      ),
      modifiers: howlModifierBits(),
    );
    if (events.isEmpty) return;
    _returnToLiveForInput();
    for (final input in events) {
      _sendMouse(input);
    }
  }

  void _beginHistoryDrag(DragStartDetails _) {
    _history.beginDrag();
  }

  void _updateHistoryDrag(DragUpdateDetails details) {
    final metadata = _nativeLiveMetadata;
    final deltaY = details.primaryDelta;
    final historyCount = metadata?.historyCount;
    final historyRowBase = metadata?.historyRowBase;
    final alternateScreen = metadata?.alternateScreen;
    if (deltaY == null ||
        historyCount == null ||
        historyRowBase == null ||
        alternateScreen == null) {
      return;
    }
    final changed = _history.drag(
      deltaY: deltaY,
      rowHeight: terminalLineHeight,
      historyCount: historyCount,
      historyRowBase: historyRowBase,
      alternateScreen: alternateScreen,
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
        var observer = _nativeHistoryObserver;
        if (observer == null) {
          observer = await NativeHostObserver.createPlatform(
            endpoint: widget.endpoint.toString(),
          );
          if (!mounted || _stopping || !_history.active) {
            unawaited(observer.close());
            return;
          }
          _nativeHistoryObserver = observer;
        }
        final bytes = await observer.observe(
          afterRevision: 0,
          historyOffset: _history.targetOffset,
          residency: encodeNativeHostResidency(_nativeHistoryLease),
        );
        final packet = parseNativeHostPacket(bytes);
        if (!mounted || _stopping || !_history.active) return;
        if (generation != _historyGeneration) continue;
        _history.acceptSnapshot(
          historyOffset: packet.metadata.historyOffset,
          historyCount: packet.metadata.historyCount,
          historyRowBase: packet.metadata.historyRowBase,
          alternateScreen: packet.metadata.alternateScreen,
        );
        if (!_history.active) {
          _leaveHistory();
          return;
        }
        final prepared = await prepareNativeCanvasFrame(
          _nativeHistoryLease,
          packet.canvas,
        );
        if (!mounted || _stopping || !_history.active) return;
        if (generation != _historyGeneration) {
          for (final image in prepared.retired) {
            image.dispose();
          }
          continue;
        }
        _nativeHistoryMetadata = packet.metadata;
        _nativeHistoryLease = prepared.lease;
        setState(() {});
        await WidgetsBinding.instance.endOfFrame;
        for (final image in prepared.retired) {
          image.dispose();
        }
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
    final nativeHistoryObserver = _nativeHistoryObserver;
    _nativeHistoryObserver = null;
    if (nativeHistoryObserver != null) {
      unawaited(nativeHistoryObserver.close());
    }
    final oldNativeHistory = _nativeHistoryLease;
    _nativeHistoryLease = null;
    _nativeHistoryMetadata = null;
    if (mounted && !_stopping && _nativeLiveLease != null) {
      setState(() {});
      if (oldNativeHistory != null) {
        unawaited(_disposeLeaseAfterFrame(oldNativeHistory));
      }
    }
  }

  Future<void> _disposeLeaseAfterFrame(NativeCanvasLease lease) async {
    await WidgetsBinding.instance.endOfFrame;
    disposeNativeCanvasLease(lease);
  }

  void _onFocusChange(bool focused) {
    if (focused && _hasControl) {
      _textInput.attach(viewId: View.of(context).viewId);
      _scheduleTextInputShow();
    } else {
      _textInput.detach();
    }
    _sendFocus(focused);
  }

  void _proposeGeometry(Size size) {
    if (!widget.geometryLeader ||
        !_hasControl ||
        !size.width.isFinite ||
        !size.height.isFinite) {
      return;
    }
    final rows = (size.height / terminalLineHeight)
        .floor()
        .clamp(1, HowlInput.maximumRows)
        .toInt();
    final columns = (size.width / terminalCellWidth)
        .floor()
        .clamp(1, HowlInput.maximumColumns)
        .toInt();
    if (rows == _proposedRows && columns == _proposedColumns) return;
    _proposedRows = rows;
    _proposedColumns = columns;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendResize(rows, columns);
    });
  }

  @override
  void dispose() {
    _stopping = true;
    _textInput.detach();
    _focusNode.dispose();
    final nativeObserver = _nativeObserver;
    final nativeHistoryObserver = _nativeHistoryObserver;
    final nativeControl = _nativeControl;
    if (nativeObserver != null) unawaited(nativeObserver.close());
    if (nativeHistoryObserver != null) {
      unawaited(nativeHistoryObserver.close());
    }
    if (nativeControl != null) unawaited(nativeControl.close());
    disposeNativeCanvasLease(_nativeLiveLease);
    disposeNativeCanvasLease(_nativeHistoryLease);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    final failure = _failure;
    final nativeMetadata = _history.active
        ? _nativeHistoryMetadata
        : _nativeLiveMetadata;
    final nativeLease = _history.active
        ? _nativeHistoryLease
        : _nativeLiveLease;
    if (failure != null) {
      content = ColoredBox(
        color: const Color(0xff090b0e),
        child: Center(
          child: TerminalStatusText('Howl attach failed\n$failure'),
        ),
      );
    } else {
      if (nativeMetadata == null || nativeLease == null) {
        content = const ColoredBox(
          color: Color(0xff090b0e),
          child: Center(child: TerminalStatusText('attaching to native Howl…')),
        );
      } else {
        content = LayoutBuilder(
          builder: (context, constraints) {
            _proposeGeometry(constraints.biggest);
            return ColoredBox(
              color: const Color(0xff090b0e),
              child: Center(
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(
                      nativeMetadata.columns * terminalCellWidth,
                      nativeMetadata.rows * terminalLineHeight,
                    ),
                    painter: NativeCanvasPainter(
                      lease: nativeLease,
                      logicalWidth: nativeMetadata.columns * terminalCellWidth,
                      logicalHeight: nativeMetadata.rows * terminalLineHeight,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }
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

final howlNamedKeys = <PhysicalKeyboardKey, int>{
  PhysicalKeyboardKey.enter: HowlInput.namedEnter,
  PhysicalKeyboardKey.tab: 2,
  PhysicalKeyboardKey.backspace: HowlInput.namedBackspace,
  PhysicalKeyboardKey.escape: 4,
  PhysicalKeyboardKey.arrowUp: 5,
  PhysicalKeyboardKey.arrowDown: 6,
  PhysicalKeyboardKey.arrowLeft: 7,
  PhysicalKeyboardKey.arrowRight: 8,
  PhysicalKeyboardKey.insert: 9,
  PhysicalKeyboardKey.delete: HowlInput.namedDelete,
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
