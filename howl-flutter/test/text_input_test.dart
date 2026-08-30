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

List<Object> actionValues(List<TerminalInputAction> actions) => [
  for (final action in actions)
    switch (action) {
      TerminalCommittedText(:final text) => text,
      TerminalEditKeyAction(:final key) => key,
    },
];

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

  testWidgets(
    'Flutter text input channel withholds preedit and emits one commit',
    (tester) async {
      final committed = <String>[];
      final editKeys = <TerminalEditKey>[];
      final client = TerminalTextInputClient(
        onCommit: committed.add,
        onEditKey: editKeys.add,
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
      onEditKey: editKeys.add,
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
        inputType: platformInput.inputType,
        onCommit: (_) {},
        onEditKey: (_) {},
      );
      client.attach(viewId: tester.view.viewId);
      addTearDown(client.detach);

      final inputType =
          tester.testTextInput.setClientArgs?['inputType']
              as Map<String, dynamic>?;
      expect(inputType?['name'], 'TextInputType.visiblePassword');
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
