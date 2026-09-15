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
}
