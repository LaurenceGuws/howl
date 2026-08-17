import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/touch_surface.dart';

void main() {
  testWidgets('touch tap and vertical drag stay semantically distinct', (
    tester,
  ) async {
    var taps = 0;
    var starts = 0;
    var updates = 0;
    var ends = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 300,
          child: TerminalTouchSurface(
            onTap: () => taps += 1,
            onVerticalDragStart: (_) => starts += 1,
            onVerticalDragUpdate: (_) => updates += 1,
            onVerticalDragEnd: (_) => ends += 1,
            child: const ColoredBox(color: Color(0xff000000)),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    expect(taps, 1);
    expect(starts, 0);

    await tester.dragFrom(const Offset(150, 220), const Offset(0, -120));
    await tester.pump();
    expect(taps, 1);
    expect(starts, 1);
    expect(updates, greaterThan(0));
    expect(ends, 1);
  });
}
