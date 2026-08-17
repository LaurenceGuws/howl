import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/platform_input.dart';
import 'package:howl_flutter/text_input.dart';

void main() {
  test('active IME composition stays local until final commit', () {
    final staging = CommittedTextStager();

    expect(
      staging.update(
        const TextEditingValue(
          text: 'e',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      ),
      isNull,
    );
    expect(staging.value.text, 'e');

    expect(
      staging.update(
        const TextEditingValue(
          text: 'é',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      ),
      isNull,
    );
    expect(staging.value.text, 'é');

    expect(
      staging.update(
        const TextEditingValue(
          text: 'é',
          selection: TextSelection.collapsed(offset: 1),
        ),
      ),
      'é',
    );
    expect(staging.value, TextEditingValue.empty);
  });

  test('combining and non-ASCII commits remain exact Unicode text', () {
    final staging = CommittedTextStager();
    const committed = 'e\u0301 中 🐺';
    expect(
      staging.update(
        const TextEditingValue(
          text: committed,
          selection: TextSelection.collapsed(offset: committed.length),
        ),
      ),
      committed,
    );
    expect(staging.value, TextEditingValue.empty);
  });

  test('empty editing updates do not create terminal input', () {
    final staging = CommittedTextStager();
    expect(staging.update(TextEditingValue.empty), isNull);
    expect(staging.value, TextEditingValue.empty);
  });

  testWidgets(
    'Flutter text input channel withholds preedit and emits one commit',
    (tester) async {
      final committed = <String>[];
      final client = TerminalTextInputClient(onCommit: committed.add);
      client.attach(viewId: tester.view.viewId);
      addTearDown(client.detach);
      expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
      expect(tester.testTextInput.isVisible, isFalse);
      await client.show(
        const TerminalPlatformInput(platformOverride: TargetPlatform.linux),
      );
      expect(tester.testTextInput.isVisible, isTrue);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'é',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.idle();
      expect(committed, isEmpty);
      expect(client.currentTextEditingValue.text, 'é');

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'é',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.idle();
      expect(committed, <String>['é']);
      expect(client.currentTextEditingValue, TextEditingValue.empty);
    },
  );

  testWidgets('Android terminal editor uses TYPE_NULL and native IME show', (
    tester,
  ) async {
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
    expect(platformInput.inputType, TextInputType.none);

    final client = TerminalTextInputClient(
      inputType: platformInput.inputType,
      onCommit: (_) {},
    );
    client.attach(viewId: tester.view.viewId);
    addTearDown(client.detach);

    final inputType =
        tester.testTextInput.setClientArgs?['inputType']
            as Map<String, dynamic>?;
    expect(inputType?['name'], 'TextInputType.none');
    expect(tester.testTextInput.isVisible, isFalse);

    await client.show(platformInput);
    expect(calls.map((call) => call.method), <String>['show']);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
