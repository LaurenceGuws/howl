import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_input.dart';
import 'package:howl_flutter/terminal_controls.dart';

void main() {
  testWidgets(
    'mobile control strip exposes exact modifier and named-key vocabulary',
    (tester) async {
      final modifiers = <int>[];
      final keys = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalControlStrip(
              modifierLatch: HowlInput.modifierControl | HowlInput.modifierAlt,
              onModifier: modifiers.add,
              onKey: keys.add,
            ),
          ),
        ),
      );

      for (final label in <String>[
        'Ctrl',
        'Alt',
        'Esc',
        'Tab',
        '←',
        '↓',
        '↑',
        '→',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Ctrl'));
      await tester.tap(find.text('Alt'));
      await tester.tap(find.text('Esc'));
      await tester.tap(find.text('→'));
      expect(modifiers, <int>[
        HowlInput.modifierControl,
        HowlInput.modifierAlt,
      ]);
      expect(keys, <int>[HowlInput.namedEscape, HowlInput.namedArrowRight]);

      final toggled = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.toggled == true)
          .length;
      expect(toggled, greaterThanOrEqualTo(2));
    },
  );
}
