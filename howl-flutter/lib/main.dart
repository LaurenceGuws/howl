import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_selection.dart';
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
import 'terminal_controls.dart';
import 'terminal_presentation.dart';
import 'terminal_selection.dart';
import 'terminal_selection_chrome.dart';
import 'terminal_semantics.dart';
import 'touch_surface.dart';
import 'transport_recovery.dart';
import 'visible_viewport.dart';

const int _nativeImageSnapshotSupersessionLimit = 8;

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

final class _PresentationRestart implements Exception {
  const _PresentationRestart();
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
  String _nativeLiveSemanticText = '';
  String _nativeHistorySemanticText = '';
  bool _nativeLiveSemanticTruncated = false;
  bool _nativeHistorySemanticTruncated = false;
  NativeCanvasLease? _nativeLiveLease;
  NativeCanvasLease? _nativeHistoryLease;
  Object? _failure;
  bool _reconnecting = false;
  bool _stopping = false;
  int _transportGeneration = 0;
  Completer<Object>? _transportFault;
  final TransportRecovery _transportRecovery = TransportRecovery();
  bool _historyRequestRunning = false;
  bool _historyRequestPending = false;
  int _historyGeneration = 0;
  Timer? _historyWheelTimer;
  NativeInteractionState? _interactionStateCache;
  DateTime? _interactionStateCachedAt;
  int _proposedRows = 0;
  int _proposedColumns = 0;
  int? _presentationMaximumRows;
  int? _presentationMaximumColumns;
  int _nativeRasterScale = 1;
  int? _scheduledRasterScale;
  int? _pendingResizeRows;
  int? _pendingResizeColumns;
  bool _resizeDrainRunning = false;
  int _modifierLatch = 0;
  TerminalZoomPreset _zoomPreset = TerminalZoomPreset.normal;
  late bool _geometryLeader;
  bool? _restoreImeAfterPresentationRestart;
  Size? _terminalViewportSize;
  TerminalSelectionRange? _selection;
  final DesktopSelectionController _desktopSelection =
      DesktopSelectionController();
  bool _selectionUsesTouchChrome = false;
  int? _pointerDecisionPointer;
  Future<void> _controlTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _geometryLeader = widget.geometryLeader;
    _textInput = TerminalTextInputClient(
      inputType: _platformInput.inputType,
      onCommit: (text) {
        _returnToLiveForInput();
        final modifiers = _takeModifierLatch();
        final runes = text.runes.toList(growable: false);
        if (modifiers != 0 && runes.length == 1) {
          _sendUnicodeKeyCycle(runes.single, modifiers: modifiers);
        } else {
          _sendCommittedText(text);
        }
      },
      onEditKey: (key) {
        _returnToLiveForInput();
        final modifiers = _takeModifierLatch();
        final keyName = switch (key) {
          TerminalEditKey.enter => HowlInput.namedEnter,
          TerminalEditKey.backspace => HowlInput.namedBackspace,
          TerminalEditKey.delete => HowlInput.namedDelete,
        };
        _sendNamedKey(
          keyName: keyName,
          action: HowlInput.keyPress,
          modifiers: modifiers,
        );
      },
    );
    unawaited(_observe());
  }

  Future<void> _observe() => _observeNative();

  Future<void> _observeNative() async {
    while (!_stopping) {
      final generation = ++_transportGeneration;
      var attached = false;
      try {
        await _observeNativeLifetime(generation, () => attached = true);
        return;
      } catch (error) {
        if (_stopping || !mounted) return;
        _dropTransport(generation);
        if (error is _PresentationRestart) {
          _transportRecovery.succeeded();
          final oldLive = _nativeLiveLease;
          _proposedRows = 0;
          _proposedColumns = 0;
          setState(() {
            _nativeLiveLease = null;
            _nativeLiveMetadata = null;
            _nativeLiveSemanticText = '';
            _nativeLiveSemanticTruncated = false;
            _failure = null;
            _reconnecting = false;
          });
          if (oldLive != null) unawaited(_disposeLeaseAfterFrame(oldLive));
          continue;
        }
        if (!retriableTransportFailure(error, attached: attached)) {
          _reportFailure(error);
          return;
        }
        _leaveHistory();
        _proposedRows = 0;
        _proposedColumns = 0;
        final delay = _transportRecovery.failed();
        setState(() {
          _failure = error;
          _reconnecting = true;
        });
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<void> _observeNativeLifetime(
    int generation,
    void Function() markAttached,
  ) async {
    NativeHostObserver? observer;
    NativeHostControl? control;
    final zoomPreset = _zoomPreset;
    final presentation = zoomPreset.presentation;
    final rasterScale = terminalRasterScale(View.of(context).devicePixelRatio);
    final nativePresentation = presentation.rasterized(rasterScale);
    bool presentationChanged() =>
        zoomPreset != _zoomPreset ||
        rasterScale != terminalRasterScale(View.of(context).devicePixelRatio);
    try {
      control = await NativeHostControl.create(
        endpoint: widget.endpoint.toString(),
      );
      if (presentationChanged()) throw const _PresentationRestart();
      if (!mounted || _stopping || generation != _transportGeneration) return;
      markAttached();

      observer = await NativeHostObserver.createPlatform(
        endpoint: widget.endpoint.toString(),
        presentation: nativePresentation,
      );
      if (presentationChanged()) throw const _PresentationRestart();
      _presentationMaximumRows = observer.maximumRows;
      _presentationMaximumColumns = observer.maximumColumns;
      _nativeRasterScale = rasterScale;
      _scheduledRasterScale = null;

      if (_geometryLeader) {
        if (_terminalViewportSize == null) {
          await WidgetsBinding.instance.endOfFrame;
        }
        if (presentationChanged()) throw const _PresentationRestart();
        final viewport = _terminalViewportSize;
        final geometry = viewport == null
            ? null
            : _geometryFor(viewport, presentation);
        if (geometry != null) {
          await control.resize(geometry.rows, geometry.columns);
          _proposedRows = geometry.rows;
          _proposedColumns = geometry.columns;
        }
      }
      if (presentationChanged()) throw const _PresentationRestart();
      if (!mounted || _stopping || generation != _transportGeneration) return;
      _nativeObserver = observer;
      _nativeControl = control;
      _interactionStateCache = null;
      _interactionStateCachedAt = null;
      _transportFault = Completer<Object>();
      final restoreIme = _restoreImeAfterPresentationRestart;
      if (_focusNode.hasFocus && _selection == null) {
        _textInput.attach(viewId: View.of(context).viewId);
        if (restoreIme ?? true) _scheduleTextInputShow();
        _sendFocus(true);
      }
      if (zoomPreset == _zoomPreset) {
        _restoreImeAfterPresentationRestart = null;
      }
      var revision = 0;
      while (!_stopping && generation == _transportGeneration) {
        // Match Web's latest-frame policy: only ask Session for the next live
        // observation after the previous frame reached the display boundary.
        // Session materializes the newest eligible canonical revision, so PTY
        // bursts collapse before native rich decode / Canvas projection.
        final observed = await _observeNativeFrame(
          observer: observer,
          afterRevision: revision,
          historyOffset: 0,
          lease: _nativeLiveLease,
          transportGeneration: generation,
        );
        if (presentationChanged()) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          throw const _PresentationRestart();
        }
        if (!mounted || _stopping || generation != _transportGeneration) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          break;
        }
        final NativeHostFrame packet;
        try {
          packet = parseNativeHostPacket(observed.bytes, nativePresentation);
        } catch (_) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          rethrow;
        }
        final prepared = await prepareNativeCanvasFrame(
          _nativeLiveLease,
          packet.canvas,
          preloaded: observed.preloaded,
        );
        revision = packet.metadata.revision;
        if (presentationChanged()) {
          disposeNativeCanvasLeaseCandidate(prepared);
          throw const _PresentationRestart();
        }
        if (!mounted || _stopping || generation != _transportGeneration) {
          disposeNativeCanvasLeaseCandidate(prepared);
          break;
        }
        _nativeLiveMetadata = packet.metadata;
        _validateSelection(packet.metadata);
        _nativeLiveSemanticText = packet.semanticText;
        _nativeLiveSemanticTruncated = packet.semanticTruncated;
        _nativeLiveLease = prepared.lease;
        _transportRecovery.succeeded();
        _failure = null;
        _reconnecting = false;
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
        await WidgetsBinding.instance.endOfFrame;
        for (final image in prepared.retired) {
          image.dispose();
        }
      }
    } finally {
      if (identical(_nativeObserver, observer)) _nativeObserver = null;
      if (identical(_nativeControl, control)) _nativeControl = null;
      if (generation == _transportGeneration) _transportFault = null;
      if (observer != null) unawaited(observer.close().catchError((_) {}));
      if (control != null) unawaited(control.close().catchError((_) {}));
    }
  }

  Future<T> _observeOrTransportFault<T>(Future<T> observation, int generation) {
    final fault = _transportFault;
    if (fault == null || generation != _transportGeneration) return observation;
    return Future.any<T>(<Future<T>>[
      observation,
      fault.future.then<T>((error) => throw error),
    ]);
  }

  Future<({Uint8List bytes, List<NativeCanvasPreloadedResource> preloaded})>
  _observeNativeFrame({
    required NativeHostObserver observer,
    required int afterRevision,
    required int historyOffset,
    required NativeCanvasLease? lease,
    int? transportGeneration,
  }) async {
    final preloaded = <(int, int), NativeCanvasPreloadedResource>{};
    var supersessions = 0;
    try {
      while (true) {
        final future = observer.observe(
          afterRevision: afterRevision,
          historyOffset: historyOffset,
          residency: encodeNativeHostResidency(
            lease,
            preloaded: preloaded.values,
          ),
        );
        final observation = transportGeneration == null
            ? await future
            : await _observeOrTransportFault(future, transportGeneration);
        if (observation is NativeHostFrameObservation) {
          return (
            bytes: observation.bytes,
            preloaded: preloaded.values.toList(growable: false),
          );
        }
        if (observation is NativeHostImageSupersededObservation) {
          disposeNativeCanvasPreloadedResources(preloaded.values);
          preloaded.clear();
          supersessions += 1;
          if (supersessions > _nativeImageSnapshotSupersessionLimit) {
            throw const NativeHostException('image_refill_supersession_limit');
          }
          continue;
        }
        if (observation is! NativeHostImageRefillObservation) {
          throw const NativeHostException('observe_kind');
        }
        final decoded = await prepareNativeCanvasExternalUpload(
          observation.upload,
        );
        final logical = (
          decoded.resource.key.source,
          decoded.resource.key.resource,
        );
        final replaced = preloaded[logical];
        if (replaced != null && replaced.image != decoded.image) {
          replaced.image.dispose();
        }
        preloaded[logical] = decoded;
      }
    } catch (_) {
      disposeNativeCanvasPreloadedResources(preloaded.values);
      rethrow;
    }
  }

  void _dropTransport(int generation) {
    if (generation != _transportGeneration) return;
    _transportGeneration += 1;
    final observer = _nativeObserver;
    final control = _nativeControl;
    _nativeObserver = null;
    _nativeControl = null;
    _interactionStateCache = null;
    _interactionStateCachedAt = null;
    _transportFault = null;
    if (observer != null) unawaited(observer.close().catchError((_) {}));
    if (control != null) unawaited(control.close().catchError((_) {}));
  }

  void _signalTransportFault(Object error, int generation) {
    if (generation != _transportGeneration || _stopping) return;
    final fault = _transportFault;
    if (fault == null || fault.isCompleted) return;
    fault.complete(error);
  }

  void _reportFailure(Object error) {
    if (!mounted || _stopping) return;
    setState(() {
      _failure = error;
      _reconnecting = false;
    });
  }

  bool get _hasControl => _nativeControl != null;
  TerminalPresentation get _presentation => _zoomPreset.presentation;
  double get _cellWidth => _presentation.cellWidth.toDouble();
  double get _lineHeight => _presentation.lineHeight.toDouble();

  Future<void> _queueControl(Future<void> Function(NativeHostControl) action) {
    if (_stopping) return Future<void>.value();
    final control = _nativeControl;
    if (control == null) return Future<void>.value();
    final generation = _transportGeneration;
    _controlTail = _controlTail.then((_) async {
      if (_stopping ||
          generation != _transportGeneration ||
          !identical(control, _nativeControl)) {
        return;
      }
      try {
        await action(control);
      } catch (error) {
        if (retriableTransportFailure(error, attached: true)) {
          _signalTransportFault(error, generation);
        } else {
          _reportFailure(error);
        }
        rethrow;
      }
    });
    _controlTail = _controlTail.catchError((Object _) {});
    return _controlTail;
  }

  Future<T?> _queueControlResult<T>(
    Future<T> Function(NativeHostControl) action,
  ) {
    if (_stopping) return Future<T?>.value();
    final control = _nativeControl;
    if (control == null) return Future<T?>.value();
    final generation = _transportGeneration;
    final task = _controlTail.then<T?>((_) async {
      if (_stopping ||
          generation != _transportGeneration ||
          !identical(control, _nativeControl)) {
        return null;
      }
      try {
        return await action(control);
      } catch (error) {
        if (retriableTransportFailure(error, attached: true)) {
          _signalTransportFault(error, generation);
        } else {
          _reportFailure(error);
        }
        rethrow;
      }
    });
    _controlTail = task.then<void>((_) {}).catchError((Object _) {});
    return task;
  }

  Future<NativeInteractionState?> _currentInteractionState() async {
    final cached = _interactionStateCache;
    final cachedAt = _interactionStateCachedAt;
    final now = DateTime.now();
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) <= const Duration(milliseconds: 120)) {
      return cached;
    }
    final state = await _queueControlResult(
      (control) => control.interactionState(),
    );
    if (state != null) {
      _interactionStateCache = state;
      _interactionStateCachedAt = DateTime.now();
    }
    return state;
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

  void _sendUnicodeKey({
    required int scalar,
    required int action,
    int modifiers = 0,
  }) {
    _queueControl(
      (control) => control.unicodeKey(
        scalar: scalar,
        action: action,
        modifiers: modifiers,
      ),
    );
  }

  void _sendNamedKeyCycle(int keyName, {int modifiers = 0}) {
    _returnToLiveForInput();
    _sendNamedKey(
      keyName: keyName,
      action: HowlInput.keyPress,
      modifiers: modifiers,
    );
    _sendNamedKey(
      keyName: keyName,
      action: HowlInput.keyRelease,
      modifiers: modifiers,
    );
  }

  void _sendUnicodeKeyCycle(int scalar, {int modifiers = 0}) {
    _sendUnicodeKey(
      scalar: scalar,
      action: HowlInput.keyPress,
      modifiers: modifiers,
    );
    _sendUnicodeKey(
      scalar: scalar,
      action: HowlInput.keyRelease,
      modifiers: modifiers,
    );
  }

  void _toggleModifier(int bit) {
    setState(() => _modifierLatch ^= bit);
    _activateTextInput();
  }

  int _takeModifierLatch() {
    final value = _modifierLatch;
    if (value != 0) setState(() => _modifierLatch = 0);
    return value;
  }

  void _sendToolbarKey(int keyName) {
    final modifiers = _takeModifierLatch();
    _sendNamedKeyCycle(keyName, modifiers: modifiers);
    _activateTextInput();
  }

  void _pasteClipboard() {
    _returnToLiveForInput();
    _takeModifierLatch();
    unawaited(_pasteClipboardAsync());
  }

  void _copyVisibleText() {
    final selection = _selection;
    if (selection != null) {
      unawaited(_copySelectionAsync(selection));
      return;
    }
    final text = _history.active
        ? _nativeHistorySemanticText
        : _nativeLiveSemanticText;
    if (text.isEmpty) return;
    unawaited(_copyVisibleTextAsync(text));
  }

  Future<void> _copySelectionAsync(TerminalSelectionRange selection) async {
    final control = _nativeControl;
    if (control == null) return;
    try {
      final text = await control.selectedText(
        startRow: selection.anchor.row,
        startColumn: selection.anchor.column,
        endRow: selection.focus.row,
        endColumn: selection.focus.column,
        columns: selection.columns,
        alternateScreen: selection.alternateScreen,
      );
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted && identical(_selection, selection)) {
        setState(() {
          _selection = null;
          _selectionUsesTouchChrome = false;
          _desktopSelection.clear();
        });
      }
    } catch (_) {
      // A stale/evicted selection or unavailable clipboard is presentation
      // state, not a reason to fail the terminal attachment.
    } finally {
      if (mounted && !_stopping) _activateTextInput();
    }
  }

  Future<void> _copyVisibleTextAsync(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // Clipboard availability is platform/UI state, not terminal failure.
    } finally {
      if (mounted && !_stopping) _activateTextInput();
    }
  }

  Future<void> _pasteClipboardAsync() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _stopping) return;
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      if (utf8.encode(text).length > HowlInput.maximumPasteBytes) return;
      await _queueControl((control) => control.paste(text));
    } catch (_) {
      // Clipboard availability is platform/UI state, not a terminal failure.
      // Empty or unavailable clipboard is intentionally a no-op.
    } finally {
      if (mounted && !_stopping) _activateTextInput();
    }
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

  void _takeGeometryLeadership() {
    if (_stopping || !_hasControl) return;
    final viewport = _terminalViewportSize;
    if (viewport == null) return;
    final geometry = _geometryFor(viewport, _presentation);
    if (geometry == null) return;
    final rows = geometry.rows;
    final columns = geometry.columns;
    unawaited(
      _queueControl((control) async {
        await control.resize(rows, columns);
        if (!mounted || _stopping) return;
        setState(() {
          _geometryLeader = true;
          _proposedRows = rows;
          _proposedColumns = columns;
        });
      }),
    );
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
    final modifiers = howlModifierBits();
    final keyName = howlNamedKey(event.physicalKey);
    final unicodeScalar = keyName == null
        ? howlControlUnicodeScalar(event.logicalKey, modifiers)
        : null;
    if (keyName == null && unicodeScalar == null) {
      return KeyEventResult.ignored;
    }
    _returnToLiveForInput();
    final action = switch (event) {
      KeyDownEvent() => HowlInput.keyPress,
      KeyRepeatEvent() => HowlInput.keyRepeat,
      KeyUpEvent() => HowlInput.keyRelease,
      _ => HowlInput.keyPress,
    };
    if (keyName != null) {
      _sendNamedKey(keyName: keyName, action: action, modifiers: modifiers);
    } else {
      _sendUnicodeKey(
        scalar: unicodeScalar!,
        action: action,
        modifiers: modifiers,
      );
    }
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
    if (_selection != null) return;
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
    if (!_hasControl) return;
    _textInput.attach(viewId: View.of(context).viewId);
    _scheduleTextInputShow();
  }

  void _showSoftKeyboard() {
    _returnToLiveForInput();
    _activateTextInput();
  }

  NativeHostMetadata? get _displayedMetadata =>
      _history.active ? _nativeHistoryMetadata : _nativeLiveMetadata;

  void _onPointerDown(PointerDownEvent event, Size viewport) {
    if (event.kind == PointerDeviceKind.touch) return;
    if (!_focusNode.hasFocus) _focusNode.requestFocus();

    final primary = event.buttons & kPrimaryMouseButton != 0;
    if (!primary) {
      if (_history.active || _selection != null) return;
      _activateTextInput();
      _sendPointer(event, viewport);
      return;
    }

    final route = routeDesktopPrimaryPointer(
      historyActive: _history.active,
      forceSelection: HardwareKeyboard.instance.isShiftPressed,
      mouseTrackingEnabled: null,
    );
    if (route == DesktopPrimaryPointerRoute.localSelection) {
      _beginMouseSelection(event, viewport);
      return;
    }

    _pointerDecisionPointer = event.pointer;
    unawaited(_routePrimaryPointerDown(event, viewport));
  }

  Future<void> _routePrimaryPointerDown(
    PointerDownEvent event,
    Size viewport,
  ) async {
    final state = await _currentInteractionState();
    if (!mounted ||
        _stopping ||
        _pointerDecisionPointer != event.pointer ||
        state == null) {
      return;
    }
    _pointerDecisionPointer = null;
    final route = routeDesktopPrimaryPointer(
      historyActive: _history.active,
      forceSelection: HardwareKeyboard.instance.isShiftPressed,
      mouseTrackingEnabled: state.mouseTrackingEnabled,
    );
    switch (route) {
      case DesktopPrimaryPointerRoute.localSelection:
        _beginMouseSelection(event, viewport);
      case DesktopPrimaryPointerRoute.terminalMouse:
        _activateTextInput();
        _sendPointer(event, viewport);
      case DesktopPrimaryPointerRoute.interactionState:
        throw StateError(
          'resolved primary pointer route requested interaction state',
        );
    }
  }

  TerminalSelectionPoint? _mouseSelectionPoint(
    Offset position,
    Size viewportSize, {
    bool clamped = false,
  }) {
    final metadata = _displayedMetadata;
    if (metadata == null) return null;
    final geometry = TerminalSelectionGeometry(
      viewportSize: viewportSize,
      rows: metadata.rows,
      columns: metadata.columns,
      cellWidth: _cellWidth,
      rowHeight: _lineHeight,
    );
    final cell = clamped
        ? geometry.clampedCellAt(position)
        : geometry.cellAt(position);
    if (cell == null) return null;
    return _selectionViewport(metadata).pointAt(cell.row, cell.column);
  }

  void _beginMouseSelection(PointerDownEvent event, Size viewportSize) {
    final metadata = _displayedMetadata;
    final point = _mouseSelectionPoint(event.localPosition, viewportSize);
    if (metadata == null || point == null || _stopping) return;
    _textInput.detach();
    _pointerInput.clear();
    final range = _desktopSelection.start(
      pointer: event.pointer,
      point: point,
      columns: metadata.columns,
      alternateScreen: metadata.alternateScreen,
    );
    setState(() {
      _selectionUsesTouchChrome = false;
      _selection = range;
    });
  }

  void _onPointerMove(PointerMoveEvent event, Size viewport) {
    if (_desktopSelection.pointer == event.pointer) {
      _updateMouseSelection(event.localPosition, viewport, event.pointer);
      return;
    }
    if (_pointerDecisionPointer == event.pointer ||
        _history.active ||
        _selection != null) {
      return;
    }
    _sendPointer(event, viewport);
  }

  void _onPointerHover(PointerHoverEvent event, Size viewport) {
    if (_history.active || _selection != null) return;
    _sendPointer(event, viewport);
  }

  void _onPointerUp(PointerUpEvent event, Size viewport) {
    if (_desktopSelection.pointer == event.pointer) {
      _updateMouseSelection(event.localPosition, viewport, event.pointer);
      _finishMouseSelection(event.pointer);
      return;
    }
    if (_pointerDecisionPointer == event.pointer) {
      _pointerDecisionPointer = null;
      return;
    }
    if (_history.active || _selection != null) return;
    _sendPointer(event, viewport);
  }

  void _onPointerCancel(PointerCancelEvent event, Size viewport) {
    if (_desktopSelection.pointer == event.pointer) {
      _clearMouseSelection();
      return;
    }
    if (_pointerDecisionPointer == event.pointer) {
      _pointerDecisionPointer = null;
      return;
    }
    if (_history.active || _selection != null) return;
    _sendPointer(event, viewport);
  }

  void _updateMouseSelection(Offset position, Size viewportSize, int pointer) {
    final point = _mouseSelectionPoint(position, viewportSize, clamped: true);
    if (point == null) return;
    final next = _desktopSelection.update(pointer, point);
    if (next == null || identical(next, _selection)) return;
    setState(() => _selection = next);
  }

  void _finishMouseSelection(int pointer) {
    final result = _desktopSelection.finish(pointer);
    setState(() {
      _selection = result.keep ? result.range : null;
      if (!result.keep) _selectionUsesTouchChrome = false;
    });
    if (!result.keep) _activateTextInput();
  }

  void _clearMouseSelection() {
    if (_selection == null && !_desktopSelection.active) return;
    _desktopSelection.clear();
    setState(() {
      _selection = null;
      _selectionUsesTouchChrome = false;
    });
    _activateTextInput();
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
        cellWidth: _cellWidth,
        rowHeight: _lineHeight,
      ),
      modifiers: howlModifierBits(),
    );
    if (events.isEmpty) return;
    for (final input in events) {
      _sendMouse(input);
    }
  }

  void _onPointerSignal(PointerSignalEvent event, Size viewport) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta.dy == 0) {
      return;
    }
    unawaited(_routePointerScroll(event, viewport));
  }

  bool _scrollHistoryWheel(double deltaY) {
    final metadata = _nativeLiveMetadata;
    if (metadata == null ||
        metadata.alternateScreen ||
        metadata.historyCount == 0) {
      return false;
    }
    if (_historyWheelTimer == null) _history.beginDrag();
    _historyWheelTimer?.cancel();
    _historyWheelTimer = Timer(const Duration(milliseconds: 160), () {
      _historyWheelTimer = null;
      _history.endDrag();
    });
    final changed = _history.drag(
      deltaY: deltaY,
      rowHeight: _lineHeight,
      historyCount: metadata.historyCount,
      historyRowBase: metadata.historyRowBase,
      alternateScreen: metadata.alternateScreen,
    );
    if (!changed) return false;
    _historyGeneration += 1;
    if (_history.active) {
      _pointerInput.clear();
      _scheduleHistorySnapshot();
    } else {
      _leaveHistory();
    }
    return true;
  }

  Future<void> _routePointerScroll(
    PointerScrollEvent event,
    Size viewport,
  ) async {
    final metadata = _nativeLiveMetadata;
    if (metadata == null) return;
    var route = routeDesktopWheel(
      historyActive: _history.active,
      mouseTrackingEnabled: null,
      alternateScreen: metadata.alternateScreen,
      alternateScroll: null,
    );
    if (route == DesktopWheelRoute.history) {
      _scrollHistoryWheel(event.scrollDelta.dy);
      return;
    }

    final wheel = _pointerInput.wheel(
      event,
      geometry: TerminalPointerGeometry(
        viewport: viewport,
        rows: metadata.rows,
        columns: metadata.columns,
        cellWidth: _cellWidth,
        rowHeight: _lineHeight,
      ),
      modifiers: howlModifierBits(),
    );
    final state = await _currentInteractionState();
    if (!mounted || _stopping || state == null) return;
    final currentMetadata = _nativeLiveMetadata;
    if (currentMetadata == null) return;
    route = routeDesktopWheel(
      historyActive: _history.active,
      mouseTrackingEnabled: state.mouseTrackingEnabled,
      alternateScreen: currentMetadata.alternateScreen,
      alternateScroll: state.alternateScroll,
    );
    switch (route) {
      case DesktopWheelRoute.history:
        _scrollHistoryWheel(event.scrollDelta.dy);
      case DesktopWheelRoute.terminalMouse:
        if (wheel != null) _sendMouse(wheel);
      case DesktopWheelRoute.alternateScroll:
        _sendNamedKeyCycle(
          event.scrollDelta.dy < 0
              ? HowlInput.namedArrowUp
              : HowlInput.namedArrowDown,
        );
      case DesktopWheelRoute.ignore:
        return;
      case DesktopWheelRoute.interactionState:
        throw StateError('resolved wheel route requested interaction state');
    }
  }

  void _beginHistoryDrag(DragStartDetails _) {
    if (_selection != null) return;
    _pointerInput.clear();
    _history.beginDrag();
  }

  void _updateHistoryDrag(DragUpdateDetails details) {
    if (_selection != null) return;
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
      rowHeight: _lineHeight,
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
    if (_selection != null) return;
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
          final nativePresentation = _presentation.rasterized(
            _nativeRasterScale,
          );
          observer = await NativeHostObserver.createPlatform(
            endpoint: widget.endpoint.toString(),
            presentation: nativePresentation,
          );
          if (!mounted || _stopping || !_history.active) {
            unawaited(observer.close());
            return;
          }
          _nativeHistoryObserver = observer;
        }
        final observed = await _observeNativeFrame(
          observer: observer,
          afterRevision: 0,
          historyOffset: _history.targetOffset,
          lease: _nativeHistoryLease,
        );
        if (!mounted || _stopping || !_history.active) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          return;
        }
        if (generation != _historyGeneration) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          continue;
        }
        final NativeHostFrame packet;
        try {
          packet = parseNativeHostPacket(
            observed.bytes,
            _presentation.rasterized(_nativeRasterScale),
          );
        } catch (_) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          rethrow;
        }
        _history.acceptSnapshot(
          historyOffset: packet.metadata.historyOffset,
          historyCount: packet.metadata.historyCount,
          historyRowBase: packet.metadata.historyRowBase,
          alternateScreen: packet.metadata.alternateScreen,
        );
        if (!_history.active) {
          disposeNativeCanvasPreloadedResources(observed.preloaded);
          _leaveHistory();
          return;
        }
        final NativeCanvasLeaseUpdate prepared;
        prepared = await prepareNativeCanvasFrame(
          _nativeHistoryLease,
          packet.canvas,
          preloaded: observed.preloaded,
        );
        if (!mounted || _stopping || !_history.active) {
          disposeNativeCanvasLeaseCandidate(prepared);
          return;
        }
        if (generation != _historyGeneration) {
          disposeNativeCanvasLeaseCandidate(prepared);
          continue;
        }
        _nativeHistoryMetadata = packet.metadata;
        _validateSelection(packet.metadata);
        _nativeHistorySemanticText = packet.semanticText;
        _nativeHistorySemanticTruncated = packet.semanticTruncated;
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
    _pointerDecisionPointer = null;
    if (_selection != null || _desktopSelection.active) {
      setState(() {
        _selection = null;
        _selectionUsesTouchChrome = false;
        _desktopSelection.clear();
      });
    }
    if (_history.active) _leaveHistory();
  }

  TerminalSelectionViewport _selectionViewport(NativeHostMetadata metadata) =>
      TerminalSelectionViewport(
        historyOffset: metadata.historyOffset,
        historyCount: metadata.historyCount,
        historyRowBase: metadata.historyRowBase,
        rows: metadata.rows,
        columns: metadata.columns,
        alternateScreen: metadata.alternateScreen,
        selectionRows: metadata.selectionRows,
      );

  void _validateSelection(NativeHostMetadata metadata) {
    final selection = _selection;
    if (selection == null) return;
    if (_selectionViewport(metadata).validity(selection) !=
        TerminalSelectionValidity.valid) {
      _selection = null;
      _selectionUsesTouchChrome = false;
      _desktopSelection.clear();
    }
  }

  void _onTerminalTap() {
    if (_selection != null) {
      setState(() {
        _selection = null;
        _selectionUsesTouchChrome = false;
        _desktopSelection.clear();
      });
      return;
    }
    _activateTextInput();
  }

  void _startSelection(
    LongPressStartDetails details,
    Size viewportSize,
    NativeHostMetadata? metadata,
  ) {
    if (metadata == null || _stopping) return;
    final viewport = _selectionViewport(metadata);
    final geometry = TerminalSelectionGeometry(
      viewportSize: viewportSize,
      rows: metadata.rows,
      columns: metadata.columns,
      cellWidth: _cellWidth,
      rowHeight: _lineHeight,
    );
    final cell = geometry.cellAt(details.localPosition);
    if (cell == null) return;
    final point = viewport.pointAt(cell.row, cell.column);
    if (point == null) return;
    _textInput.detach();
    setState(() {
      _selectionUsesTouchChrome = true;
      _desktopSelection.clear();
      _selection = TerminalSelectionRange(
        anchor: point,
        focus: point,
        columns: metadata.columns,
        alternateScreen: metadata.alternateScreen,
      );
    });
  }

  void _changeSelectionStart(TerminalSelectionPoint point) {
    final selection = _selection;
    if (selection == null) return;
    setState(() => _selection = selection.withOrderedStart(point));
  }

  void _changeSelectionEnd(TerminalSelectionPoint point) {
    final selection = _selection;
    if (selection == null) return;
    setState(() => _selection = selection.withOrderedEnd(point));
  }

  void _autoScrollSelection(int rows) {
    if (_selection == null || rows == 0) return;
    final metadata = _nativeLiveMetadata;
    if (metadata == null) return;
    final changed = _history.scrollRows(
      rows,
      historyCount: metadata.historyCount,
      historyRowBase: metadata.historyRowBase,
      alternateScreen: metadata.alternateScreen,
    );
    if (!changed) return;
    _historyGeneration += 1;
    if (_history.active) {
      _scheduleHistorySnapshot();
    } else {
      _leaveHistory();
    }
  }

  void _leaveHistory() {
    _historyWheelTimer?.cancel();
    _historyWheelTimer = null;
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
    _nativeHistorySemanticText = '';
    _nativeHistorySemanticTruncated = false;
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

  void _changeZoom(TerminalZoomPreset preset) {
    if (_stopping || preset == _zoomPreset) return;
    _scheduledRasterScale = null;
    _restoreImeAfterPresentationRestart =
        MediaQuery.viewInsetsOf(context).bottom > 0;
    _leaveHistory();
    setState(() {
      _zoomPreset = preset;
      _selection = null;
      // The old observer may already be preparing a frame that references this
      // residency. Hide its metadata immediately, but retain the lease until the
      // old presentation lifetime has unwound.
      _nativeLiveMetadata = null;
      _nativeLiveSemanticText = '';
      _nativeLiveSemanticTruncated = false;
      _proposedRows = 0;
      _proposedColumns = 0;
      _pendingResizeRows = null;
      _pendingResizeColumns = null;
      _failure = null;
      _reconnecting = false;
    });
    final fault = _transportFault;
    if (fault != null && !fault.isCompleted) {
      fault.complete(const _PresentationRestart());
    }
  }

  void _onFocusChange(bool focused) {
    if (focused && _hasControl && _selection == null) {
      _textInput.attach(viewId: View.of(context).viewId);
      _scheduleTextInputShow();
    } else {
      _textInput.detach();
    }
    _sendFocus(focused);
  }

  void _scheduleRasterPresentationRestart(int rasterScale) {
    if (_scheduledRasterScale == rasterScale) return;
    _scheduledRasterScale = rasterScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stopping || _scheduledRasterScale != rasterScale) return;
      _scheduledRasterScale = null;
      final currentScale = terminalRasterScale(
        View.of(context).devicePixelRatio,
      );
      if (currentScale != rasterScale || currentScale == _nativeRasterScale) {
        return;
      }
      _restoreImeAfterPresentationRestart =
          MediaQuery.viewInsetsOf(context).bottom > 0;
      _leaveHistory();
      setState(() {
        _selection = null;
        _nativeLiveMetadata = null;
        _nativeLiveSemanticText = '';
        _nativeLiveSemanticTruncated = false;
        _proposedRows = 0;
        _proposedColumns = 0;
        _pendingResizeRows = null;
        _pendingResizeColumns = null;
        _failure = null;
        _reconnecting = false;
      });
      final fault = _transportFault;
      if (fault != null && !fault.isCompleted) {
        fault.complete(const _PresentationRestart());
      }
    });
  }

  void _proposeGeometry(Size size) {
    _terminalViewportSize = size;
    final rasterScale = terminalRasterScale(View.of(context).devicePixelRatio);
    if (_nativeObserver != null && rasterScale != _nativeRasterScale) {
      _scheduleRasterPresentationRestart(rasterScale);
      return;
    }
    if (!_geometryLeader || !_hasControl) return;
    final geometry = _geometryFor(size, _presentation);
    if (geometry == null) return;
    final rows = geometry.rows;
    final columns = geometry.columns;
    if (rows == _proposedRows && columns == _proposedColumns) return;
    _proposedRows = rows;
    _proposedColumns = columns;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendResize(rows, columns);
    });
  }

  ({int rows, int columns})? _geometryFor(
    Size size,
    TerminalPresentation presentation,
  ) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return null;
    }
    final maximumRows = _presentationMaximumRows;
    final maximumColumns = _presentationMaximumColumns;
    if (maximumRows == null || maximumColumns == null) return null;
    return (
      rows: (size.height / presentation.lineHeight)
          .floor()
          .clamp(1, maximumRows)
          .toInt(),
      columns: (size.width / presentation.cellWidth)
          .floor()
          .clamp(1, maximumColumns)
          .toInt(),
    );
  }

  @override
  void dispose() {
    _stopping = true;
    _historyWheelTimer?.cancel();
    _historyWheelTimer = null;
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
    final semanticText = _history.active
        ? _nativeHistorySemanticText
        : _nativeLiveSemanticText;
    final semanticTruncated = _history.active
        ? _nativeHistorySemanticTruncated
        : _nativeLiveSemanticTruncated;
    if (failure != null) {
      content = ColoredBox(
        color: const Color(0xff090b0e),
        child: Center(
          child: TerminalStatusText(
            '${_reconnecting ? 'Howl reconnecting…' : 'Howl attach failed'}\n$failure',
          ),
        ),
      );
    } else {
      if (nativeMetadata == null || nativeLease == null) {
        content = const ColoredBox(
          color: Color(0xff090b0e),
          child: Center(child: TerminalStatusText('attaching to native Howl…')),
        );
      } else {
        content = ColoredBox(
          color: const Color(0xff090b0e),
          child: Center(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(
                  nativeMetadata.columns * _cellWidth,
                  nativeMetadata.rows * _lineHeight,
                ),
                painter: NativeCanvasPainter(
                  lease: nativeLease,
                  logicalWidth: nativeMetadata.columns * _cellWidth,
                  logicalHeight: nativeMetadata.rows * _lineHeight,
                ),
              ),
            ),
          ),
        );
      }
    }
    return TerminalVisibleViewport(
      child: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _proposeGeometry(constraints.biggest);
                return TerminalSemanticSurface(
                  value: semanticText,
                  truncated: semanticTruncated,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: TerminalTouchSurface(
                          onTap: _onTerminalTap,
                          onLongPressStart: (details) => _startSelection(
                            details,
                            constraints.biggest,
                            nativeMetadata,
                          ),
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
                            onPointerUp: (event) =>
                                _onPointerUp(event, constraints.biggest),
                            onPointerCancel: (event) =>
                                _onPointerCancel(event, constraints.biggest),
                            onPointerSignal: (event) =>
                                _onPointerSignal(event, constraints.biggest),
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
                      if (_selection case final selection?)
                        Positioned.fill(
                          child: TerminalSelectionHighlight(
                            viewport: _selectionViewport(nativeMetadata!),
                            range: selection,
                            geometry: TerminalSelectionGeometry(
                              viewportSize: constraints.biggest,
                              rows: nativeMetadata.rows,
                              columns: nativeMetadata.columns,
                              cellWidth: _cellWidth,
                              rowHeight: _lineHeight,
                            ),
                          ),
                        ),
                      if (_selectionUsesTouchChrome)
                        if (_selection case final selection?)
                          Positioned.fill(
                            child: TerminalSelectionChrome(
                              viewport: _selectionViewport(nativeMetadata!),
                              range: selection,
                              geometry: TerminalSelectionGeometry(
                                viewportSize: constraints.biggest,
                                rows: nativeMetadata.rows,
                                columns: nativeMetadata.columns,
                                cellWidth: _cellWidth,
                                rowHeight: _lineHeight,
                              ),
                              onStartChanged: _changeSelectionStart,
                              onEndChanged: _changeSelectionEnd,
                              onAutoScrollRows: _autoScrollSelection,
                              onCopy: _copyVisibleText,
                              onPaste: _pasteClipboard,
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
          TerminalControlStrip(
            modifierLatch: _modifierLatch,
            zoomPreset: _zoomPreset,
            geometryLeader: _geometryLeader,
            onModifier: _toggleModifier,
            onKey: _sendToolbarKey,
            onZoom: _changeZoom,
            onLead: _takeGeometryLeadership,
            onKeyboard: _showSoftKeyboard,
            onCopy: _copyVisibleText,
            onPaste: _pasteClipboard,
          ),
        ],
      ),
    );
  }
}

final howlNamedKeys = <PhysicalKeyboardKey, int>{
  PhysicalKeyboardKey.enter: HowlInput.namedEnter,
  PhysicalKeyboardKey.tab: HowlInput.namedTab,
  PhysicalKeyboardKey.backspace: HowlInput.namedBackspace,
  PhysicalKeyboardKey.escape: HowlInput.namedEscape,
  PhysicalKeyboardKey.arrowUp: HowlInput.namedArrowUp,
  PhysicalKeyboardKey.arrowDown: HowlInput.namedArrowDown,
  PhysicalKeyboardKey.arrowLeft: HowlInput.namedArrowLeft,
  PhysicalKeyboardKey.arrowRight: HowlInput.namedArrowRight,
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

/// Projects a printable physical Ctrl chord into Howl's Unicode-key vocabulary.
///
/// Unmodified printable keys deliberately stay on Flutter's text/IME path. Ctrl
/// chords do not produce a text commit on desktop, so they need this key-event
/// seam to preserve terminal shortcuts such as Ctrl-F, Ctrl-R and Ctrl-C.
int? howlControlUnicodeScalar(LogicalKeyboardKey key, int modifiers) {
  if (modifiers & HowlInput.modifierControl == 0) return null;
  final runes = key.keyLabel.runes.toList(growable: false);
  if (runes.length != 1) return null;
  var scalar = runes.single;
  if (scalar >= 0x41 && scalar <= 0x5a) {
    final shifted = modifiers & (1 << 0) != 0;
    final capsLocked = modifiers & (1 << 6) != 0;
    if (!(shifted ^ capsLocked)) scalar += 0x20;
  }
  return scalar;
}

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
