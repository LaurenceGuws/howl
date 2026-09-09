import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_semantics.dart';

void main() {
  testWidgets(
    'terminal semantics exposes canonical value without inventing text',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: TerminalSemanticSurface(
            value: 'one  two\nthree',
            truncated: false,
            child: SizedBox(width: 20, height: 20),
          ),
        ),
      );

      final semantics = tester.widget<Semantics>(find.byType(Semantics));
      expect(semantics.properties.label, 'Terminal');
      expect(semantics.properties.value, 'one  two\nthree');
      expect(semantics.properties.hint, isNull);
      expect(semantics.properties.readOnly, isTrue);
      expect(semantics.properties.multiline, isTrue);
    },
  );

  testWidgets('truncated projection is disclosed without modifying its value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalSemanticSurface(
          value: 'bounded tail',
          truncated: true,
          child: SizedBox(width: 20, height: 20),
        ),
      ),
    );

    final semantics = tester.widget<Semantics>(find.byType(Semantics));
    expect(semantics.properties.value, 'bounded tail');
    expect(semantics.properties.hint, 'Visible terminal text truncated');
  });
}
