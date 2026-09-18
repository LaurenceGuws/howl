import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/platform_input.dart';
import 'package:howl_flutter/text_input.dart';

TextEditingValue guardedValue(
  String text, {
  TextRange composing = TextRange.empty,
}) {
  final value =
      '${TerminalInputStager.leftGuard}$text${TerminalInputStager.rightGuard}';
  return TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(
      offset: TerminalInputStager.leftGuard.length + text.length,
    ),
    composing: composing,
  );
}

List<Object> actionValues(List<TerminalInputAction> actions) {
  final values = <Object>[];
  for (final action in actions) {
    switch (action) {
      case TerminalCommittedText(:final text):
        values.add(text);
      case TerminalEditKeyAction(:final key, :final count):
        values.addAll(List<Object>.filled(count, key));
    }
  }
  return values;
}

TextEditingDelta factoryDelta({
  required String oldText,
  required int start,
  required int end,
  required String text,
  required int caret,
  int composingStart = -1,
  int composingEnd = -1,
}) => TextEditingDelta.fromJSON(<String, dynamic>{
  'oldText': oldText,
  'deltaStart': start,
  'deltaEnd': end,
  'deltaText': text,
  'selectionBase': caret,
  'selectionExtent': caret,
  'selectionAffinity': 'TextAffinity.downstream',
  'selectionIsDirectional': false,
  'composingBase': composingStart,
  'composingExtent': composingEnd,
});

String guardedText(String text) =>
    '${TerminalInputStager.leftGuard}$text${TerminalInputStager.rightGuard}';

void main() {
  test('active IME composition stays local until final guarded commit', () {
    final staging = TerminalInputStager();

    expect(
      staging.update(
        guardedValue('e', composing: const TextRange(start: 1, end: 2)),
      ),
      isEmpty,
    );
    expect(
      staging.value.text,
      '${TerminalInputStager.leftGuard}e${TerminalInputStager.rightGuard}',
    );

    expect(
      staging.update(
        guardedValue('é', composing: const TextRange(start: 1, end: 2)),
      ),
      isEmpty,
    );

    expect(actionValues(staging.update(guardedValue('é'))), <Object>['é']);
    expect(staging.value, TerminalInputStager.canonicalValue);
  });

  test('combining and non-ASCII commits remain exact Unicode text', () {
    final staging = TerminalInputStager();
    const committed = 'e\u0301 中 🐺';
    expect(actionValues(staging.update(guardedValue(committed))), <Object>[
      committed,
    ]);
    expect(staging.value, TerminalInputStager.canonicalValue);
  });

  test('guard deletion becomes semantic Backspace or Delete', () {
    final staging = TerminalInputStager();

    expect(
      actionValues(
        staging.update(
          const TextEditingValue(
            text: TerminalInputStager.rightGuard,
            selection: TextSelection.collapsed(offset: 0),
          ),
        ),
      ),
      <Object>[TerminalEditKey.backspace],
    );
    expect(staging.value, TerminalInputStager.canonicalValue);

    expect(
      actionValues(
        staging.update(
          const TextEditingValue(
            text: TerminalInputStager.leftGuard,
            selection: TextSelection.collapsed(offset: 1),
          ),
        ),
      ),
      <Object>[TerminalEditKey.delete],
    );
    expect(staging.value, TerminalInputStager.canonicalValue);
  });

  test(
    'backspace runway preserves native repeat without per-key restaging',
    () {
      final staging = TerminalInputStager(backspaceRunway: 64);

      TextEditingValue runway(int remaining) {
        final left = List<String>.filled(
          remaining,
          TerminalInputStager.leftGuard,
        ).join();
        return TextEditingValue(
          text: '$left${TerminalInputStager.rightGuard}',
          selection: TextSelection.collapsed(offset: left.length),
        );
      }

      expect(actionValues(staging.update(runway(63))), <Object>[
        TerminalEditKey.backspace,
      ]);
      expect(staging.value, runway(63));

      expect(actionValues(staging.update(runway(58))), <Object>[
        for (var i = 0; i < 5; i += 1) TerminalEditKey.backspace,
      ]);
      final batch = staging.update(runway(53));
      expect(batch, hasLength(1));
      expect((batch.single as TerminalEditKeyAction).count, 5);
      expect(staging.value, runway(53));

      // Reset the expected runway for the remaining exact-count checks.
      staging.reset();
      expect(actionValues(staging.update(runway(38))), <Object>[
        for (var i = 0; i < 26; i += 1) TerminalEditKey.backspace,
      ]);
      expect(staging.value, runway(38));

      expect(actionValues(staging.update(runway(16))), <Object>[
        for (var i = 0; i < 22; i += 1) TerminalEditKey.backspace,
      ]);
      expect(staging.value.text.length, 65);
      expect(staging.value.selection.baseOffset, 64);
    },
  );

  test('committed newline forms become ordered semantic Enter actions', () {
    final staging = TerminalInputStager();
    expect(actionValues(staging.update(guardedValue('a\r\nb\n\rz'))), <Object>[
      'a',
      TerminalEditKey.enter,
      'b',
      TerminalEditKey.enter,
      TerminalEditKey.enter,
      'z',
    ]);
    expect(staging.value, TerminalInputStager.canonicalValue);
  });

  test(
    'ambiguous empty editor replacement emits nothing and resets guards',
    () {
      final staging = TerminalInputStager();
      expect(staging.update(TextEditingValue.empty), isEmpty);
      expect(staging.value, TerminalInputStager.canonicalValue);
    },
  );

  testWidgets('delta input belongs only to the native Linux editor', (
    tester,
  ) async {
    for (final platform in TargetPlatform.values) {
      final client = TerminalTextInputClient(
        platformOverride: platform,
        onCommit: (_) => fail('Configuration must not commit text'),
        onEditKey: (_, _) => fail('Configuration must not emit keys'),
      );
      client.attach(viewId: tester.view.viewId);
      expect(
        tester.testTextInput.setClientArgs?['enableDeltaModel'],
        !kIsWeb && platform == TargetPlatform.linux,
        reason: platform.name,
      );
      client.detach();
    }
  });

  testWidgets(
    'Linux delta input consumes queued commits once without prefix heuristics',
    (tester) async {
      final committed = <String>[];
      final client = TerminalTextInputClient(
        platformOverride: TargetPlatform.linux,
        onCommit: committed.add,
        onEditKey: (_, _) => fail('Unexpected semantic edit key'),
      );
      client.attach(viewId: tester.view.viewId);
      addTearDown(client.detach);

      expect(tester.testTextInput.setClientArgs?['enableDeltaModel'], !kIsWeb);

      const left = TerminalInputStager.leftGuard;
      const right = TerminalInputStager.rightGuard;
      void sendQueued(String text) {
        var oldText = TerminalInputStager.guardText;
        var insertionOffset = 1;
        for (final character in text.split('')) {
          client.updateEditingValueWithDeltas(<TextEditingDelta>[
            TextEditingDeltaInsertion(
              oldText: oldText,
              textInserted: character,
              insertionOffset: insertionOffset,
              selection: TextSelection.collapsed(offset: insertionOffset + 1),
              composing: TextRange.empty,
            ),
          ]);
          oldText =
              '$left${oldText.substring(1, insertionOffset)}$character$right';
          insertionOffset += 1;
        }
      }

      sendQueued('/bar');
      sendQueued('abc');

      expect(committed, <String>['/', 'b', 'a', 'r', 'a', 'b', 'c']);
      expect(committed.join(), '/barabc');
      expect(
        client.currentTextEditingValue,
        TerminalInputStager.canonicalValue,
      );
    },
  );

  test('Linux factory composition commits its final owned region', () {
    List<Object> compose({
      required String preedit,
      required String committed,
      required Matcher normalizedAs,
    }) {
      final staging = TerminalInputStager();
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: TerminalInputStager.guardText,
            start: 1,
            end: 1,
            text: preedit,
            caret: 1 + preedit.length,
            composingStart: 1,
            composingEnd: 1 + preedit.length,
          ),
        ),
        isEmpty,
      );
      final end = factoryDelta(
        oldText: guardedText(preedit),
        start: 1,
        end: 1 + preedit.length,
        text: committed,
        caret: 1 + committed.length,
      );
      expect(end, normalizedAs);
      return actionValues(staging.updateDelta(end));
    }

    expect(
      compose(
        preedit: 'é',
        committed: 'é',
        normalizedAs: isA<TextEditingDeltaNonTextUpdate>(),
      ),
      <Object>['é'],
    );
    expect(
      compose(
        preedit: 'Flutter ',
        committed: 'Flutter engine',
        normalizedAs: isA<TextEditingDeltaInsertion>(),
      ),
      <Object>['Flutter engine'],
    );
    expect(
      compose(
        preedit: 'teh',
        committed: 'the',
        normalizedAs: isA<TextEditingDeltaReplacement>(),
      ),
      <Object>['the'],
    );
    expect(
      compose(
        preedit: 'ab',
        committed: 'a',
        normalizedAs: isA<TextEditingDeltaDeletion>(),
      ),
      <Object>['a'],
    );
  });

  test(
    'Linux composition excludes older commits and ignores cancellation and end',
    () {
      final staging = TerminalInputStager();
      expect(
        actionValues(
          staging.updateDelta(
            factoryDelta(
              oldText: TerminalInputStager.guardText,
              start: 1,
              end: 1,
              text: 'A',
              caret: 2,
            ),
          ),
        ),
        <Object>['A'],
      );
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: guardedText('A'),
            start: 2,
            end: 2,
            text: 'Flutter ',
            caret: 10,
            composingStart: 2,
            composingEnd: 10,
          ),
        ),
        isEmpty,
      );
      expect(
        actionValues(
          staging.updateDelta(
            factoryDelta(
              oldText: guardedText('AFlutter '),
              start: 2,
              end: 10,
              text: 'Flutter engine',
              caret: 16,
            ),
          ),
        ),
        <Object>['Flutter engine'],
      );
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: guardedText('AFlutter engine'),
            start: -1,
            end: -1,
            text: '',
            caret: 16,
          ),
        ),
        isEmpty,
      );

      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: TerminalInputStager.guardText,
            start: 1,
            end: 1,
            text: 'cancel',
            caret: 7,
            composingStart: 1,
            composingEnd: 7,
          ),
        ),
        isEmpty,
      );
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: guardedText('cancel'),
            start: 1,
            end: 7,
            text: '',
            caret: 1,
          ),
        ),
        isEmpty,
      );
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: TerminalInputStager.guardText,
            start: -1,
            end: -1,
            text: '',
            caret: 1,
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'Linux exact deltas preserve real repeats and reject private guards',
    () {
      final staging = TerminalInputStager();
      TextEditingDelta insertion(String text) => factoryDelta(
        oldText: TerminalInputStager.guardText,
        start: 1,
        end: 1,
        text: text,
        caret: 1 + text.length,
      );

      expect(
        actionValues(
          staging.updateDelta(
            factoryDelta(
              oldText: TerminalInputStager.guardText,
              start: 0,
              end: 2,
              text: '/bar',
              caret: 4,
            ),
          ),
        ),
        <Object>['/bar'],
      );
      expect(actionValues(staging.updateDelta(insertion('a'))), <Object>['a']);
      expect(actionValues(staging.updateDelta(insertion('a'))), <Object>['a']);
      expect(
        staging.updateDelta(
          insertion(
            'x${TerminalInputStager.leftGuard}'
            'y${TerminalInputStager.rightGuard}z',
          ),
        ),
        isEmpty,
      );

      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: TerminalInputStager.guardText,
            start: 1,
            end: 1,
            text: 'safe',
            caret: 5,
            composingStart: 1,
            composingEnd: 5,
          ),
        ),
        isEmpty,
      );
      expect(
        staging.updateDelta(
          factoryDelta(
            oldText: guardedText('safe'),
            start: 1,
            end: 5,
            text: 'x${TerminalInputStager.leftGuard}y',
            caret: 4,
          ),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Flutter text input channel withholds preedit and emits one commit',
    (tester) async {
      final committed = <String>[];
      final editKeys = <TerminalEditKey>[];
      final client = TerminalTextInputClient(
        onCommit: committed.add,
        onEditKey: (key, count) {
          editKeys.addAll(List<TerminalEditKey>.filled(count, key));
        },
      );
      client.attach(viewId: tester.view.viewId);
      addTearDown(client.detach);
      expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
      expect(
        tester.testTextInput.editingState?['text'],
        TerminalInputStager.guardText,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await client.show(
        const TerminalPlatformInput(platformOverride: TargetPlatform.linux),
      );
      expect(tester.testTextInput.isVisible, isTrue);

      tester.testTextInput.updateEditingValue(
        guardedValue('é', composing: const TextRange(start: 1, end: 2)),
      );
      await tester.idle();
      expect(committed, isEmpty);
      expect(editKeys, isEmpty);
      expect(client.currentTextEditingValue.text, guardedValue('é').text);

      tester.testTextInput.updateEditingValue(guardedValue('é'));
      await tester.idle();
      expect(committed, <String>['é']);
      expect(editKeys, isEmpty);
      expect(
        client.currentTextEditingValue,
        TerminalInputStager.canonicalValue,
      );
      expect(
        tester.testTextInput.editingState?['text'],
        TerminalInputStager.guardText,
      );
    },
  );

  testWidgets('editor action newline becomes semantic Enter', (tester) async {
    final editKeys = <TerminalEditKey>[];
    final client = TerminalTextInputClient(
      onCommit: (_) {},
      onEditKey: (key, count) {
        editKeys.addAll(List<TerminalEditKey>.filled(count, key));
      },
    );
    client.attach(viewId: tester.view.viewId);
    addTearDown(client.detach);

    client.performAction(TextInputAction.newline);
    expect(editKeys, <TerminalEditKey>[TerminalEditKey.enter]);
  });

  testWidgets(
    'Android terminal editor uses character input and native IME show',
    (tester) async {
      const channel = MethodChannel('howl.flutter/android_ime');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      const platformInput = TerminalPlatformInput(
        platformOverride: TargetPlatform.android,
      );
      expect(platformInput.inputType, TextInputType.visiblePassword);

      final client = TerminalTextInputClient(
        platformOverride: TargetPlatform.android,
        inputType: platformInput.inputType,
        onCommit: (_) {},
        onEditKey: (_, _) {},
      );
      client.attach(viewId: tester.view.viewId);
      addTearDown(client.detach);

      final inputType =
          tester.testTextInput.setClientArgs?['inputType']
              as Map<String, dynamic>?;
      expect(inputType?['name'], 'TextInputType.visiblePassword');
      expect(tester.testTextInput.setClientArgs?['enableDeltaModel'], isFalse);
      expect(
        tester.testTextInput.editingState?['text'],
        TerminalInputStager.guardText,
      );
      expect(tester.testTextInput.isVisible, isFalse);

      await client.show(platformInput);
      expect(calls.map((call) => call.method), <String>['show']);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );
}
