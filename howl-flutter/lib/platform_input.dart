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

  TextInputType get inputType =>
      usesAndroidImeHost ? TextInputType.visiblePassword : TextInputType.text;

  Future<void> show(VoidCallback flutterShow) async {
    if (usesAndroidImeHost) {
      await _androidIme.invokeMethod<void>('show');
      return;
    }
    flutterShow();
  }
}
