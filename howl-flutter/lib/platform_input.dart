import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host-only policy for exposing the terminal's platform text editor.
///
/// Android terminals use TYPE_NULL, matching Termux's default editor contract.
/// Flutter intentionally refuses to show an IME for TextInputType.none, so the
/// Android activity owns only the native show/restart operation. Composition
/// and committed text still flow through Flutter's TextInputClient in Dart.
final class TerminalPlatformInput {
  const TerminalPlatformInput({this.platformOverride});

  final TargetPlatform? platformOverride;

  static const MethodChannel _androidIme = MethodChannel(
    'howl.flutter/android_ime',
  );

  TargetPlatform get platform => platformOverride ?? defaultTargetPlatform;

  bool get usesAndroidTerminalEditor => platform == TargetPlatform.android;

  TextInputType get inputType =>
      usesAndroidTerminalEditor ? TextInputType.none : TextInputType.text;

  Future<void> show(VoidCallback flutterShow) async {
    if (usesAndroidTerminalEditor) {
      await _androidIme.invokeMethod<void>('show');
      return;
    }
    flutterShow();
  }
}
