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

  test('software keyboard owner starts explicitly hidden and settled', () {
    final owner = TerminalSoftKeyboardOwner();
    expect(owner.requestedVisible, isFalse);
    expect(owner.observedVisible, isFalse);
    expect(owner.settled, isTrue);
    expect(
      owner.diagnosticSummary,
      'requested=false observed=false settled=true',
    );
  });

  test(
    'software keyboard owner asserts explicit show and hide observations',
    () async {
      final owner = TerminalSoftKeyboardOwner();
      final applied = <bool>[];

      final show = owner.request(
        true,
        apply: (visible) async => applied.add(visible),
      );
      expect(owner.requestedVisible, isTrue);
      expect(owner.observedVisible, isFalse);
      expect(owner.settled, isFalse);
      owner.observe(true);
      await show;
      expect(owner.settled, isTrue);

      final hide = owner.request(
        false,
        apply: (visible) async => applied.add(visible),
      );
      expect(owner.requestedVisible, isFalse);
      expect(owner.observedVisible, isTrue);
      expect(owner.settled, isFalse);
      owner.observe(false);
      await hide;
      expect(owner.settled, isTrue);
      expect(applied, <bool>[true, false]);
    },
  );

  test('software keyboard request fails closed when platform state does not settle', () async {
    final owner = TerminalSoftKeyboardOwner(
      settleTimeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      owner.request(true, apply: (_) async {}),
      throwsA(
        isA<TerminalSoftKeyboardVisibilityException>()
            .having((error) => error.requestedVisible, 'requested', isTrue)
            .having((error) => error.observedVisible, 'observed', isFalse),
      ),
    );
    expect(owner.requestedVisible, isTrue);
    expect(owner.observedVisible, isFalse);
    expect(owner.settled, isFalse);
  });
}
