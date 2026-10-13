import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/instance_target.dart';
import 'package:howl_flutter/native_host.dart';
import 'package:howl_flutter/terminal_presentation.dart';

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

  test(
    'real Local observer copies Render commands into unchanged Dart packets',
    () async {
      final owner = NativeLocalInstance.create(
        shell: '/bin/sh',
        command: "printf '\\033[31mRender!\\033[0m'; exec sleep 30",
        rows: 4,
        columns: 16,
        historyRows: 16,
      );
      const presentation = TerminalPresentation(
        fontPixels: 16,
        cellWidth: 10,
        lineHeight: 20,
      );
      NativeInterruptScope? interrupt;
      NativeHostObserver? observer;
      NativeHostFrame? copied;
      try {
        interrupt = NativeInterruptScope.create();
        final font = File('../../mods/howl-text/testdata/primary.ttf')
            .absolute
            .path;
        observer = await NativeHostObserver.create(
          target: const LocalHowlInstanceTarget(),
          primaryFontPath: font,
          fallbackFontPath: font,
          secondaryFallbackFontPath: font,
          presentation: presentation,
          interrupt: interrupt,
          localInstanceAddress: owner.address,
        );
        var revision = 0;
        final clock = Stopwatch()..start();
        while (clock.elapsed < const Duration(seconds: 3)) {
          final observation = await observer
              .observe(
                afterRevision: revision,
                historyOffset: 0,
                residency: Uint8List(0),
              )
              .timeout(const Duration(seconds: 3));
          expect(observation, isA<NativeHostFrameObservation>());
          final frame = parseNativeHostPacket(
            (observation as NativeHostFrameObservation).bytes,
            presentation,
          );
          revision = frame.metadata.revision;
          if (frame.semanticText.contains('Render!')) {
            copied = frame;
            break;
          }
        }
        expect(copied, isNotNull);
        final canvas = copied!.canvas;
        expect(canvas.surfaceWidth, 160);
        expect(canvas.surfaceHeight, 80);
        expect(canvas.pixelCount, greaterThan(0));
        final tags = [
          for (var i = 0; i < canvas.commandCount; i++) canvas.commandTag(i),
        ];
        expect(tags, containsAll([0, 1]));
        for (var i = 0; i < canvas.commandCount; i++) {
          if (canvas.commandTag(i) == 1) {
            expect(
              canvas.commandResourceIndex(i),
              lessThan(canvas.resourceCount),
            );
            expect(canvas.commandSourceWidth(i), greaterThan(0));
            expect(canvas.commandSourceHeight(i), greaterThan(0));
          }
        }
      } finally {
        try {
          await observer?.close();
        } finally {
          try {
            await owner.close();
          } finally {
            interrupt?.destroy();
          }
        }
      }
      // The packet remains ordinary Dart-owned storage after native teardown.
      expect(copied.semanticText, contains('Render!'));
      expect(copied.canvas.commandCount, greaterThan(0));
    },
    skip: !Platform.isLinux || candidate != '7',
  );
}
