import 'dart:io';

import 'package:flutter/services.dart';

/// iOS-only tactile tick for synthetic terminal key repeat.
///
/// UIKit owns the haptic for native software-keyboard delete events. When iOS
/// coalesces those edits and Howl drains the semantic repeats itself, this
/// channel asks one persistent UISelectionFeedbackGenerator to mirror each
/// synthetic terminal tick. Other platforms are deliberately inert.
final class IosRepeatHaptic {
  const IosRepeatHaptic();

  static const MethodChannel _channel = MethodChannel(
    'howl.flutter/ios_repeat_haptic',
  );

  Future<void> tick() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('tick');
    } on MissingPluginException {
      // A stale debug build may not contain the canary channel. Haptics must
      // never make terminal input fail.
    } on PlatformException {
      // Tactile feedback is best-effort and not part of input correctness.
    }
  }
}
