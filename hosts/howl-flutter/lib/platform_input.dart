import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host-only policy for exposing the terminal's platform text editor.
///
/// Android uses a character editor so Flutter's editable state can expose IME
/// deletion as semantic terminal actions. The Android activity owns only the
/// delayed native show/hide mechanics; visibility policy remains in Dart.
final class TerminalPlatformInput {
  const TerminalPlatformInput({this.platformOverride});

  final TargetPlatform? platformOverride;

  static const MethodChannel _androidIme = MethodChannel(
    'howl.flutter/android_ime',
  );

  TargetPlatform get platform => platformOverride ?? defaultTargetPlatform;

  bool get usesAndroidImeHost => platform == TargetPlatform.android;

  TextInputType get inputType =>
      usesAndroidImeHost ? TextInputType.visiblePassword : TextInputType.text;

  /// iOS repeats software-keyboard Backspace by repeatedly mutating the native
  /// editable. Keep enough private guard text to let that repeat run at native
  /// cadence instead of restaging the editor after every deletion.
  int get backspaceRunway => platform == TargetPlatform.iOS ? 64 : 1;

  /// iOS reports Return both through the editing value and performAction.
  /// The editing mutation is authoritative so one Return stays one Enter.
  bool get newlineActionFallback => platform != TargetPlatform.iOS;

  Future<void> show(VoidCallback flutterShow) async {
    if (usesAndroidImeHost) {
      await _androidIme.invokeMethod<void>('show');
      return;
    }
    flutterShow();
  }

  Future<void> hide() async {
    if (usesAndroidImeHost) {
      await _androidIme.invokeMethod<void>('hide');
      return;
    }
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }
}

final class TerminalSoftKeyboardVisibilityException implements Exception {
  const TerminalSoftKeyboardVisibilityException({
    required this.requestedVisible,
    required this.observedVisible,
  });

  final bool requestedVisible;
  final bool observedVisible;

  @override
  String toString() =>
      'TerminalSoftKeyboardVisibilityException('
      'requested=$requestedVisible observed=$observedVisible)';
}

/// Singular app-shell owner of software-keyboard visibility policy.
///
/// The platform owns only the visual keyboard mechanism. Howl owns whether that
/// keyboard is requested, observes the resulting viewport inset as platform
/// truth, and bounds every explicit show/hide request with a visibility
/// assertion. Text-input attachment is intentionally independent: hiding the
/// keyboard must not relinquish terminal text-input ownership.
final class TerminalSoftKeyboardOwner {
  TerminalSoftKeyboardOwner({this.settleTimeout = const Duration(seconds: 2)})
    : assert(settleTimeout > Duration.zero);

  final Duration settleTimeout;

  bool _requestedVisible = false;
  bool _observedVisible = false;
  int _generation = 0;
  Completer<void>? _pending;

  bool get requestedVisible => _requestedVisible;
  bool get observedVisible => _observedVisible;
  bool get settled => _pending == null && _requestedVisible == _observedVisible;

  String get diagnosticSummary =>
      'requested=$_requestedVisible observed=$_observedVisible settled=$settled';

  void observe(bool visible) {
    _observedVisible = visible;
    if (visible == _requestedVisible) {
      final pending = _pending;
      if (pending != null && !pending.isCompleted) pending.complete();
    }
  }

  Future<void> request(
    bool visible, {
    required Future<void> Function(bool visible) apply,
  }) async {
    _requestedVisible = visible;
    final generation = ++_generation;
    final previous = _pending;
    if (previous != null && !previous.isCompleted) previous.complete();
    final pending = Completer<void>();
    _pending = pending;

    try {
      await apply(visible);
      if (_observedVisible == visible && !pending.isCompleted) {
        pending.complete();
      }
      await pending.future.timeout(settleTimeout);
    } on TimeoutException {
      if (generation != _generation) return;
      throw TerminalSoftKeyboardVisibilityException(
        requestedVisible: visible,
        observedVisible: _observedVisible,
      );
    } finally {
      if (generation == _generation && identical(_pending, pending)) {
        _pending = null;
      }
    }
  }
}
