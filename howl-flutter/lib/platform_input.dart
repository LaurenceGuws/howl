import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host-only policy for exposing the terminal's platform text editor.
///
/// Android uses a character editor so Flutter's editable state can expose IME
/// deletion as semantic terminal actions. This mirrors Termux's optional
/// character-based input strategy. The Android activity still owns only the
/// delayed native show/restart operation; composition and committed text remain
/// in Flutter's TextInputClient in Dart.
final class TerminalPlatformInput {
  const TerminalPlatformInput({this.platformOverride});

  final TargetPlatform? platformOverride;

  static const MethodChannel _androidIme = MethodChannel(
    'howl.flutter/android_ime',
  );

  TargetPlatform get platform => platformOverride ?? defaultTargetPlatform;

  bool get usesAndroidImeHost => platform == TargetPlatform.android;

  /// Android keeps terminal focus and the TextInput connection ready without
  /// consuming viewport space. Its software keyboard is an explicit Kbd action.
  /// iOS preserves the established eager text-input behavior.
  bool get showsSoftKeyboardImplicitly => !usesAndroidImeHost;

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
    if (!usesAndroidImeHost) return;
    await _androidIme.invokeMethod<void>('hide');
  }
}
