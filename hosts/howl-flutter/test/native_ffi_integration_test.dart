import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/instance_target.dart';
import 'package:howl_flutter/native_host.dart';

// Opt in against a private candidate library; normal tests never open an
// installed library or construct a child merely because one is present.
void main() {
  final candidate = Platform.environment['HOWL_TEST_NATIVE_ABI'];
  test('old private library is rejected before constructor lookup', () {
    expect(
      NativeInterruptScope.create,
      throwsA(
        isA<NativeHostException>().having(
          (failure) => failure.code,
          'code',
          'native_host_version_6',
        ),
      ),
    );
  }, skip: !Platform.isLinux || candidate != '6');

  test(
    'real Local worker forwards owned interaction and selection to Dart',
    () async {
      final owner = NativeLocalInstance.create(
        shell: '/bin/sh',
        command: "printf 'A\\314\\201中'; printf '\\033[?1007h\\033[?1004h\\033[?1006h\\033[?1003h'; exec sleep 30",
        rows: 4,
        columns: 16,
        historyRows: 16,
      );
      NativeInterruptScope? interrupt;
      NativeHostControl? control;
      NativeInteractionState? copied;
      try {
        interrupt = NativeInterruptScope.create();
        control = await NativeHostControl.create(
          target: const LocalHowlInstanceTarget(),
          interrupt: interrupt,
          localInstanceAddress: owner.address,
        );
        final clock = Stopwatch()..start();
        while (clock.elapsed < const Duration(seconds: 2)) {
          final state = await control.interactionState();
          if (state.alternateScroll &&
              state.focusReporting &&
              state.mouseTracking == 4 &&
              state.mouseProtocol == 2) {
            copied = state;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(copied, isNotNull);
        expect(
          await control.selectedText(
            startRow: 0,
            startColumn: 0,
            endRow: 0,
            endColumn: 2,
            columns: 16,
            alternateScreen: false,
          ),
          'Á中',
        );
      } finally {
        try {
          await control?.close();
        } finally {
          try {
            await owner.close();
          } finally {
            interrupt?.destroy();
          }
        }
      }
      expect(copied!.mouseTrackingEnabled, isTrue);
      expect(copied.pointerMode, inInclusiveRange(0, 3));
    },
    skip: !Platform.isLinux || candidate != '7',
  );
}
