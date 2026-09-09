import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_selection.dart';
import 'package:howl_flutter/terminal_selection_chrome.dart';

void main() {
  testWidgets('floating toolbar returns after a selection handle drag', (
    tester,
  ) async {
    const viewport = TerminalSelectionViewport(
      historyOffset: 0,
      historyCount: 0,
      historyRowBase: 0,
      rows: 5,
      columns: 8,
      alternateScreen: false,
    );
    var range = const TerminalSelectionRange(
      anchor: TerminalSelectionPoint(row: 2, column: 3),
      focus: TerminalSelectionPoint(row: 2, column: 3),
      columns: 8,
      alternateScreen: false,
    );
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: StatefulBuilder(
              builder: (context, update) {
                setState = update;
                return TerminalSelectionChrome(
                  viewport: viewport,
                  range: range,
                  geometry: const TerminalSelectionGeometry(
                    viewportSize: Size(400, 400),
                    rows: 5,
                    columns: 8,
                    cellWidth: 10,
                    rowHeight: 20,
                  ),
                  onStartChanged: (point) {
                    setState(() => range = range.withOrderedStart(point));
                  },
                  onEndChanged: (point) {
                    setState(() => range = range.withOrderedEnd(point));
                  },
                  onCopy: () {},
                  onPaste: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    final panDetectors = find.byWidgetPredicate(
      (widget) =>
          widget is RawGestureDetector &&
          widget.gestures.keys.any((type) => type == PanGestureRecognizer),
    );
    expect(panDetectors, findsNWidgets(2));

    final gesture = await tester.startGesture(
      tester.getCenter(panDetectors.last),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(find.text('Copy'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
  });
}
