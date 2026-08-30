import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/visible_viewport.dart';

void main() {
  testWidgets('terminal viewport excludes fully obscuring system insets', (
    tester,
  ) async {
    Size? visible;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 500,
            height: 400,
            child: MediaQuery(
              data: const MediaQueryData(
                viewInsets: EdgeInsets.fromLTRB(10, 20, 30, 120),
              ),
              child: TerminalVisibleViewport(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    visible = constraints.biggest;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(visible, const Size(460, 260));
  });

  testWidgets('terminal viewport is unchanged when nothing obscures it', (
    tester,
  ) async {
    Size? visible;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 500,
            height: 400,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: TerminalVisibleViewport(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    visible = constraints.biggest;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(visible, const Size(500, 400));
  });
}
