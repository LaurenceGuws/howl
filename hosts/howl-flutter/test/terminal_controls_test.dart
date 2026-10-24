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
      var logs = 0;
      var leads = 0;
      final zooms = <TerminalZoomPreset>[];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalControlStrip(
              modifierLatch: HowlInput.modifierControl | HowlInput.modifierAlt,
              zoomPreset: TerminalZoomPreset.normal,
              geometryLeader: false,
              keyboardRequestedVisible: true,
              onModifier: modifiers.add,
              onKey: keys.add,
              onZoom: zooms.add,
              onLead: () => leads += 1,
              onKeyboard: () => keyboards += 1,
              onCopy: () => copies += 1,
              onPaste: () => pastes += 1,
              onLog: () => logs += 1,
            ),
          ),
        ),
      );

      for (final label in <String>[
        'Ctrl',
        'Esc',
        'Tab',
        '←',
        '↓',
        '↑',
        '→',
        'Kbd',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Ctrl'));
      await tester.tap(find.text('Esc'));
      await tester.tap(find.text('→'));
      await tester.tap(find.text('Kbd'));
      for (final label in <String>[
        'Alt',
        '16px',
        'Lead',
        'Copy',
        'Paste',
        'Log',
      ]) {
        await tester.tap(find.byTooltip('More terminal actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(modifiers, <int>[
        HowlInput.modifierControl,
        HowlInput.modifierAlt,
      ]);
      expect(keys, <int>[HowlInput.namedEscape, HowlInput.namedArrowRight]);
      expect(keyboards, 1);
      expect(zooms, <TerminalZoomPreset>[TerminalZoomPreset.small]);
      expect(leads, 1);
      expect(copies, 1);
      expect(pastes, 1);
      expect(logs, 1);
      expect(HowlInput.maximumPasteBytes, 65535);

      final toggled = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.toggled == true)
          .length;
      expect(toggled, greaterThanOrEqualTo(2));
    },
  );
}
