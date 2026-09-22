import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/platform_input.dart';

void main() {
  test(
    'iOS keeps a software backspace runway while Android stays single-guard',
    () {
      expect(
        const TerminalPlatformInput(platformOverride: TargetPlatform.iOS)
            .backspaceRunway,
        64,
      );
      expect(
        const TerminalPlatformInput(platformOverride: TargetPlatform.android)
            .backspaceRunway,
        1,
      );
    },
  );

  test('iOS editing value owns newline action', () {
    expect(
      const TerminalPlatformInput(platformOverride: TargetPlatform.iOS)
          .newlineActionFallback,
      isFalse,
    );
    expect(
      const TerminalPlatformInput(platformOverride: TargetPlatform.android)
          .newlineActionFallback,
      isTrue,
    );
  });

  test('Android software keyboard is explicit while iOS remains implicit', () {
    expect(
      const TerminalPlatformInput(platformOverride: TargetPlatform.android)
          .showsSoftKeyboardImplicitly,
      isFalse,
    );
    expect(
      const TerminalPlatformInput(platformOverride: TargetPlatform.iOS)
          .showsSoftKeyboardImplicitly,
      isTrue,
    );
  });
}
