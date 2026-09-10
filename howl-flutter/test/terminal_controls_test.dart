import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_input.dart';
import 'package:howl_flutter/terminal_controls.dart';
import 'package:howl_flutter/terminal_presentation.dart';

void main() {
  testWidgets(
    'mobile control strip exposes exact modifier and named-key vocabulary',
    (tester) async {
      final modifiers = <int>[];
      final keys = <int>[];
      var keyboards = 0;
      var copies = 0;
      var pastes = 0;
      final zooms = <TerminalZoomPreset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalControlStrip(
              modifierLatch: HowlInput.modifierControl | HowlInput.modifierAlt,
              zoomPreset: TerminalZoomPreset.normal,
              onModifier: modifiers.add,
              onKey: keys.add,
              onZoom: zooms.add,
              onKeyboard: () => keyboards += 1,
              onCopy: () => copies += 1,
              onPaste: () => pastes += 1,
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
        'Kbd',
        '16px',
        'Copy',
        'Paste',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Ctrl'));
      await tester.tap(find.text('Alt'));
      await tester.tap(find.text('Esc'));
      await tester.tap(find.text('→'));
      await tester.tap(find.text('Kbd'));
      await tester.tap(find.text('16px'));
      await tester.tap(find.text('Copy'));
      await tester.tap(find.text('Paste'));
      expect(modifiers, <int>[
        HowlInput.modifierControl,
        HowlInput.modifierAlt,
      ]);
      expect(keys, <int>[HowlInput.namedEscape, HowlInput.namedArrowRight]);
      expect(keyboards, 1);
      expect(zooms, <TerminalZoomPreset>[TerminalZoomPreset.small]);
      expect(copies, 1);
      expect(pastes, 1);
      expect(HowlInput.maximumPasteBytes, 65535);

      final toggled = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.toggled == true)
          .length;
      expect(toggled, greaterThanOrEqualTo(2));
    },
  );
}
