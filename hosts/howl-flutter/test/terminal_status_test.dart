import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_status.dart';

void main() {
  testWidgets('status text is self-styled and clamps extreme host scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(4)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TerminalStatusText('Howl status'),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Howl status'));
    expect(text.style?.color, const Color(0xffc7ced9));
    expect(text.style?.fontFamily, 'monospace');
    expect(text.style?.fontSize, 16);
    expect(text.style?.decoration, TextDecoration.none);
    expect(text.textScaler?.scale(16), 24);
  });
}
