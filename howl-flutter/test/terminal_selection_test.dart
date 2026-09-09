import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_selection.dart';

void main() {
  const live = TerminalSelectionViewport(
    historyOffset: 0,
    historyCount: 10,
    historyRowBase: 100,
    rows: 5,
    columns: 8,
    alternateScreen: false,
  );

  test(
    'stable points move with viewport history offset, not with selection',
    () {
      expect(
        live.pointAt(2, 3),
        const TerminalSelectionPoint(row: 112, column: 3),
      );
      const history = TerminalSelectionViewport(
        historyOffset: 4,
        historyCount: 10,
        historyRowBase: 100,
        rows: 5,
        columns: 8,
        alternateScreen: false,
      );
      expect(
        history.pointAt(2, 3),
        const TerminalSelectionPoint(row: 108, column: 3),
      );
    },
  );

  test('range spans intersect the currently displayed scrollback', () {
    const range = TerminalSelectionRange(
      anchor: TerminalSelectionPoint(row: 105, column: 3),
      focus: TerminalSelectionPoint(row: 112, column: 5),
      columns: 8,
      alternateScreen: false,
    );
    const history = TerminalSelectionViewport(
      historyOffset: 5,
      historyCount: 10,
      historyRowBase: 100,
      rows: 5,
      columns: 8,
      alternateScreen: false,
    );
    expect(range.spanFor(history, 0)?.startColumn, 3);
    expect(range.spanFor(history, 0)?.endColumn, 7);
    expect(range.spanFor(history, 4)?.startColumn, 0);
    expect(range.spanFor(history, 4)?.endColumn, 7);
    expect(range.spanFor(live, 2)?.endColumn, 5);
  });

  test('eviction bank and columns invalidate instead of retargeting', () {
    const range = TerminalSelectionRange(
      anchor: TerminalSelectionPoint(row: 100, column: 0),
      focus: TerminalSelectionPoint(row: 102, column: 2),
      columns: 8,
      alternateScreen: false,
    );
    expect(live.validity(range), TerminalSelectionValidity.valid);
    expect(
      const TerminalSelectionViewport(
        historyOffset: 0,
        historyCount: 9,
        historyRowBase: 101,
        rows: 5,
        columns: 8,
        alternateScreen: false,
      ).validity(range),
      TerminalSelectionValidity.evicted,
    );
    expect(
      const TerminalSelectionViewport(
        historyOffset: 0,
        historyCount: 0,
        historyRowBase: 0,
        rows: 5,
        columns: 8,
        alternateScreen: true,
      ).validity(range),
      TerminalSelectionValidity.contextChanged,
    );
  });

  test('centered geometry maps only actual terminal cells', () {
    const geometry = TerminalSelectionGeometry(
      viewportSize: Size(120, 140),
      rows: 5,
      columns: 8,
      cellWidth: 10,
      rowHeight: 20,
    );
    expect(geometry.scale, 1.0);
    expect(geometry.terminalRect, const Rect.fromLTWH(20, 20, 80, 100));
    expect(geometry.cellAt(const Offset(25, 25)), (row: 0, column: 0));
    expect(geometry.cellAt(const Offset(95, 115)), (row: 4, column: 7));
    expect(geometry.cellAt(const Offset(15, 25)), isNull);
    expect(
      geometry.handlePoint(row: 2, column: 3, end: false),
      const Offset(50, 80),
    );
    expect(
      geometry.handlePoint(row: 2, column: 3, end: true),
      const Offset(60, 80),
    );
  });

  test('selection geometry uses the same contain fit as Canvas painting', () {
    const geometry = TerminalSelectionGeometry(
      viewportSize: Size(80, 80),
      rows: 5,
      columns: 8,
      cellWidth: 10,
      rowHeight: 20,
    );
    expect(geometry.scale, 0.8);
    expect(geometry.terminalRect, const Rect.fromLTWH(8, 0, 64, 80));
    expect(geometry.cellAt(const Offset(12, 8)), (row: 0, column: 0));
    expect(geometry.cellAt(const Offset(68, 72)), (row: 4, column: 7));
    expect(
      geometry.handlePoint(row: 4, column: 7, end: true),
      const Offset(72, 80),
    );
  });

  test(
    'selection drag clamps outside cells and detects a two-row edge band',
    () {
      const geometry = TerminalSelectionGeometry(
        viewportSize: Size(80, 100),
        rows: 5,
        columns: 8,
        cellWidth: 10,
        rowHeight: 20,
      );
      expect(geometry.clampedCellAt(const Offset(-50, -50)), (
        row: 0,
        column: 0,
      ));
      expect(geometry.clampedCellAt(const Offset(500, 500)), (
        row: 4,
        column: 7,
      ));
      expect(geometry.selectionEdgeScrollRows(const Offset(40, 10)), 1);
      expect(geometry.selectionEdgeScrollRows(const Offset(40, 39)), 1);
      expect(geometry.selectionEdgeScrollRows(const Offset(40, 50)), 0);
      expect(geometry.selectionEdgeScrollRows(const Offset(40, 60)), -1);
      expect(geometry.selectionEdgeScrollRows(const Offset(40, 110)), -1);
    },
  );

  test('offscreen endpoint projects to nearest viewport edge', () {
    const history = TerminalSelectionViewport(
      historyOffset: 5,
      historyCount: 10,
      historyRowBase: 100,
      rows: 5,
      columns: 8,
      alternateScreen: false,
    );
    expect(
      history.viewportEdgeRowFor(
        const TerminalSelectionPoint(row: 102, column: 3),
      ),
      0,
    );
    expect(
      history.viewportEdgeRowFor(
        const TerminalSelectionPoint(row: 112, column: 3),
      ),
      4,
    );
  });
}
