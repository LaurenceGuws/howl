import 'dart:math' as math;

import 'package:flutter/widgets.dart';

final class TerminalSelectionPoint {
  const TerminalSelectionPoint({required this.row, required this.column});

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is TerminalSelectionPoint &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}

enum TerminalSelectionValidity { valid, contextChanged, evicted }

final class TerminalSelectionSpan {
  const TerminalSelectionSpan({
    required this.row,
    required this.startColumn,
    required this.endColumn,
  });

  final int row;
  final int startColumn;
  final int endColumn;
}

/// Presentation copy of the canonical snapshot coordinates needed to place a
/// client-local selection. Selected UTF-8 is still extracted by the session.
final class TerminalSelectionViewport {
  const TerminalSelectionViewport({
    required this.historyOffset,
    required this.historyCount,
    required this.historyRowBase,
    required this.rows,
    required this.columns,
    required this.alternateScreen,
  });

  final int historyOffset;
  final int historyCount;
  final int historyRowBase;
  final int rows;
  final int columns;
  final bool alternateScreen;

  TerminalSelectionPoint? pointAt(int viewportRow, int column) {
    if (viewportRow < 0 ||
        viewportRow >= rows ||
        column < 0 ||
        column >= columns ||
        historyOffset < 0 ||
        historyOffset > historyCount) {
      return null;
    }
    final row = alternateScreen
        ? viewportRow
        : historyRowBase + historyCount - historyOffset + viewportRow;
    if (row < -0x80000000 || row > 0x7fffffff) return null;
    return TerminalSelectionPoint(row: row, column: column);
  }

  int? viewportRowFor(TerminalSelectionPoint point) {
    if (point.column < 0 || point.column >= columns) return null;
    final row = alternateScreen
        ? point.row
        : point.row - (historyRowBase + historyCount - historyOffset);
    if (row < 0 || row >= rows) return null;
    return row;
  }

  /// Projects a retained endpoint onto the nearest visible row so Flutter can
  /// keep the opposite, visible selection handle alive while one endpoint is
  /// outside the viewport. Handle visibility remains caller-owned.
  int? viewportEdgeRowFor(TerminalSelectionPoint point) {
    if (rows <= 0 || point.column < 0 || point.column >= columns) return null;
    final row = alternateScreen
        ? point.row
        : point.row - (historyRowBase + historyCount - historyOffset);
    return row.clamp(0, rows - 1);
  }

  TerminalSelectionValidity validity(TerminalSelectionRange range) {
    if (range.columns != columns || range.alternateScreen != alternateScreen) {
      return TerminalSelectionValidity.contextChanged;
    }
    final first = alternateScreen ? 0 : historyRowBase;
    final last = alternateScreen
        ? rows - 1
        : historyRowBase + historyCount + rows - 1;
    bool retained(TerminalSelectionPoint point) =>
        point.column >= 0 &&
        point.column < columns &&
        point.row >= first &&
        point.row <= last;
    if (!retained(range.anchor) || !retained(range.focus)) {
      return TerminalSelectionValidity.evicted;
    }
    return TerminalSelectionValidity.valid;
  }
}

final class TerminalSelectionRange {
  const TerminalSelectionRange({
    required this.anchor,
    required this.focus,
    required this.columns,
    required this.alternateScreen,
  });

  final TerminalSelectionPoint anchor;
  final TerminalSelectionPoint focus;
  final int columns;
  final bool alternateScreen;

  TerminalSelectionRange withFocus(TerminalSelectionPoint value) =>
      TerminalSelectionRange(
        anchor: anchor,
        focus: value,
        columns: columns,
        alternateScreen: alternateScreen,
      );

  TerminalSelectionRange withOrderedStart(TerminalSelectionPoint value) {
    final bounds = ordered;
    final start = _beforeOrEqual(value, bounds.end) ? value : bounds.end;
    return TerminalSelectionRange(
      anchor: start,
      focus: bounds.end,
      columns: columns,
      alternateScreen: alternateScreen,
    );
  }

  TerminalSelectionRange withOrderedEnd(TerminalSelectionPoint value) {
    final bounds = ordered;
    final end = _beforeOrEqual(bounds.start, value) ? value : bounds.start;
    return TerminalSelectionRange(
      anchor: bounds.start,
      focus: end,
      columns: columns,
      alternateScreen: alternateScreen,
    );
  }

  ({TerminalSelectionPoint start, TerminalSelectionPoint end}) get ordered {
    if (_beforeOrEqual(anchor, focus)) return (start: anchor, end: focus);
    return (start: focus, end: anchor);
  }

  TerminalSelectionSpan? spanFor(
    TerminalSelectionViewport viewport,
    int viewportRow,
  ) {
    if (viewport.validity(this) != TerminalSelectionValidity.valid) {
      return null;
    }
    final rowPoint = viewport.pointAt(viewportRow, 0);
    if (rowPoint == null) return null;
    final bounds = ordered;
    final row = rowPoint.row;
    if (row < bounds.start.row || row > bounds.end.row) return null;
    return TerminalSelectionSpan(
      row: viewportRow,
      startColumn: row == bounds.start.row ? bounds.start.column : 0,
      endColumn: row == bounds.end.row ? bounds.end.column : columns - 1,
    );
  }

  static bool _beforeOrEqual(
    TerminalSelectionPoint left,
    TerminalSelectionPoint right,
  ) =>
      left.row < right.row ||
      left.row == right.row && left.column <= right.column;
}

/// Geometry of the centered fixed-cell terminal inside its touch viewport.
final class TerminalSelectionGeometry {
  const TerminalSelectionGeometry({
    required this.viewportSize,
    required this.rows,
    required this.columns,
    required this.cellWidth,
    required this.rowHeight,
  });

  final Size viewportSize;
  final int rows;
  final int columns;
  final double cellWidth;
  final double rowHeight;

  double? get scale {
    final width = columns * cellWidth;
    final height = rows * rowHeight;
    if (!viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return math.min(viewportSize.width / width, viewportSize.height / height);
  }

  Rect? get terminalRect {
    final fit = scale;
    if (fit == null) return null;
    final width = columns * cellWidth * fit;
    final height = rows * rowHeight * fit;
    return Rect.fromLTWH(
      (viewportSize.width - width) / 2,
      (viewportSize.height - height) / 2,
      width,
      height,
    );
  }

  ({int row, int column})? cellAt(Offset localPosition) {
    final rect = terminalRect;
    if (rect == null ||
        localPosition.dx < rect.left ||
        localPosition.dy < rect.top ||
        localPosition.dx >= rect.right ||
        localPosition.dy >= rect.bottom) {
      return null;
    }
    final fit = scale!;
    return (
      row: ((localPosition.dy - rect.top) / (rowHeight * fit)).floor(),
      column: ((localPosition.dx - rect.left) / (cellWidth * fit)).floor(),
    );
  }

  /// Maps a selection-handle hotspot to the closest terminal cell even after
  /// the finger crosses an edge. This is selection presentation policy, not a
  /// replacement for strict hit-testing via [cellAt].
  ({int row, int column})? clampedCellAt(Offset localPosition) {
    final rect = terminalRect;
    if (rect == null ||
        !localPosition.dx.isFinite ||
        !localPosition.dy.isFinite) {
      return null;
    }
    final fit = scale!;
    final row = ((localPosition.dy - rect.top) / (rowHeight * fit))
        .floor()
        .clamp(0, rows - 1);
    final column = ((localPosition.dx - rect.left) / (cellWidth * fit))
        .floor()
        .clamp(0, columns - 1);
    return (row: row, column: column);
  }

  /// Returns +1 near/above the top edge (older history), -1 near/below the
  /// bottom edge (toward live), and zero elsewhere.
  int selectionEdgeScrollRows(Offset localPosition, {int edgeRows = 2}) {
    final rect = terminalRect;
    if (rect == null || edgeRows <= 0 || !localPosition.dy.isFinite) return 0;
    final fit = scale!;
    final band = math.min(edgeRows, rows) * rowHeight * fit;
    if (localPosition.dy < rect.top + band) return 1;
    if (localPosition.dy >= rect.bottom - band) return -1;
    return 0;
  }

  Offset? handlePoint({
    required int row,
    required int column,
    required bool end,
  }) {
    final rect = terminalRect;
    if (rect == null ||
        row < 0 ||
        row >= rows ||
        column < 0 ||
        column >= columns) {
      return null;
    }
    final fit = scale!;
    return Offset(
      rect.left + (column + (end ? 1 : 0)) * cellWidth * fit,
      rect.top + (row + 1) * rowHeight * fit,
    );
  }
}

final class TerminalSelectionHighlight extends StatelessWidget {
  const TerminalSelectionHighlight({
    super.key,
    required this.viewport,
    required this.range,
    required this.geometry,
  });

  final TerminalSelectionViewport viewport;
  final TerminalSelectionRange range;
  final TerminalSelectionGeometry geometry;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _TerminalSelectionPainter(
        viewport: viewport,
        range: range,
        geometry: geometry,
        color:
            DefaultSelectionStyle.of(context).selectionColor ??
            const Color(0x665b9bd5),
      ),
      size: Size.infinite,
    ),
  );
}

final class _TerminalSelectionPainter extends CustomPainter {
  const _TerminalSelectionPainter({
    required this.viewport,
    required this.range,
    required this.geometry,
    required this.color,
  });

  final TerminalSelectionViewport viewport;
  final TerminalSelectionRange range;
  final TerminalSelectionGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = geometry.terminalRect;
    if (rect == null) return;
    final fit = geometry.scale!;
    final paint = Paint()..color = color;
    for (var row = 0; row < viewport.rows; row++) {
      final span = range.spanFor(viewport, row);
      if (span == null) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + span.startColumn * geometry.cellWidth * fit,
          rect.top + row * geometry.rowHeight * fit,
          (span.endColumn - span.startColumn + 1) * geometry.cellWidth * fit,
          geometry.rowHeight * fit,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TerminalSelectionPainter oldDelegate) =>
      oldDelegate.viewport.historyOffset != viewport.historyOffset ||
      oldDelegate.viewport.historyCount != viewport.historyCount ||
      oldDelegate.viewport.historyRowBase != viewport.historyRowBase ||
      oldDelegate.viewport.rows != viewport.rows ||
      oldDelegate.viewport.columns != viewport.columns ||
      oldDelegate.viewport.alternateScreen != viewport.alternateScreen ||
      oldDelegate.range.anchor != range.anchor ||
      oldDelegate.range.focus != range.focus ||
      oldDelegate.color != color ||
      oldDelegate.geometry.viewportSize != geometry.viewportSize;
}
