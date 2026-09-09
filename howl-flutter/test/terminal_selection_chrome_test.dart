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
                  onAutoScrollRows: (_) {},
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

  testWidgets('edge handle drag repeatedly asks for older history rows', (
    tester,
  ) async {
    var viewport = const TerminalSelectionViewport(
      historyOffset: 0,
      historyCount: 20,
      historyRowBase: 0,
      rows: 5,
      columns: 8,
      alternateScreen: false,
    );
    var range = const TerminalSelectionRange(
      anchor: TerminalSelectionPoint(row: 22, column: 3),
      focus: TerminalSelectionPoint(row: 22, column: 3),
      columns: 8,
      alternateScreen: false,
    );
    final scrollRows = <int>[];
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            height: 100,
            child: StatefulBuilder(
              builder: (context, update) {
                setState = update;
                return TerminalSelectionChrome(
                  viewport: viewport,
                  range: range,
                  geometry: const TerminalSelectionGeometry(
                    viewportSize: Size(80, 100),
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
                  onAutoScrollRows: (rows) {
                    scrollRows.add(rows);
                    final offset = (viewport.historyOffset + rows).clamp(
                      0,
                      viewport.historyCount,
                    );
                    if (offset == viewport.historyOffset) return;
                    setState(() {
                      viewport = TerminalSelectionViewport(
                        historyOffset: offset,
                        historyCount: viewport.historyCount,
                        historyRowBase: viewport.historyRowBase,
                        rows: viewport.rows,
                        columns: viewport.columns,
                        alternateScreen: viewport.alternateScreen,
                      );
                    });
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

    final panDetectors = find.byWidgetPredicate(
      (widget) =>
          widget is RawGestureDetector &&
          widget.gestures.keys.any((type) => type == PanGestureRecognizer),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(panDetectors.first),
    );
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(scrollRows.length, greaterThanOrEqualTo(3));
    expect(scrollRows, everyElement(1));
    expect(viewport.historyOffset, greaterThanOrEqualTo(3));
    expect(range.ordered.start.row, lessThan(20));

    await gesture.up();
    final countAtRelease = scrollRows.length;
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(scrollRows.length, countAtRelease);
    expect(find.text('Copy'), findsOneWidget);
  });
}
