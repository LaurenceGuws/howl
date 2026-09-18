/// One immutable request, scoped to a viewport lifetime rather than motion.
final class HistoryRequest {
  const HistoryRequest._(this.offset, this._targetRevision, this._lifetime);

  final int offset;
  final int _targetRevision;
  final Object _lifetime;
}

/// Client-local scrollback state over Howl's retained history window.
///
/// `targetOffset` is the number of retained rows above the live viewport. A
/// nonzero viewport also remembers the absolute retained top row so later PTY
/// output can advance `historyRowBase`/`historyCount` without pulling the
/// displayed content toward the live bottom.
final class HistoryViewport {
  int _targetOffset = 0;
  int? _anchorTopRow;
  double _dragRemainderPixels = 0;
  int _targetRevision = 0;
  Object _lifetime = Object();
  (int, int)? _geometry;
  int _retainedRowBase = 0;

  int get targetOffset => _targetOffset;
  int? get anchorTopRow => _anchorTopRow;
  bool get active => _targetOffset != 0;

  HistoryRequest captureRequest() {
    if (!active) throw StateError('history is not active');
    return HistoryRequest._(_targetOffset, _targetRevision, _lifetime);
  }

  /// Also gates asynchronous failures: an old worker cannot clear reentry.
  bool ownsRequest(HistoryRequest request) =>
      active && identical(request._lifetime, _lifetime);

  void beginDrag() {
    _dragRemainderPixels = 0;
  }

  void endDrag() {
    _dragRemainderPixels = 0;
  }

  /// Applies one touch delta. Moving a finger upward (`deltaY < 0`) moves to
  /// older history. Only whole terminal rows change the viewport.
  bool drag({
    required double deltaY,
    required double rowHeight,
    required int historyCount,
    required int historyRowBase,
    required bool alternateScreen,
  }) {
    if (rowHeight <= 0 || !rowHeight.isFinite) {
      throw ArgumentError.value(rowHeight, 'rowHeight');
    }
    if (historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    if (alternateScreen || historyCount == 0) {
      _dragRemainderPixels = 0;
      return false;
    }

    _dragRemainderPixels -= deltaY;
    final rows = (_dragRemainderPixels / rowHeight).truncate();
    if (rows == 0) return false;
    _dragRemainderPixels -= rows * rowHeight;

    final requested = _targetOffset + rows;
    final clamped = requested.clamp(0, historyCount);
    if (clamped != requested) _dragRemainderPixels = 0;
    if (clamped == _targetOffset) return false;

    if (clamped == 0) return reset();
    _targetRevision += 1;
    _targetOffset = clamped;
    _anchorTopRow = historyRowBase + historyCount - clamped;
    return true;
  }

  /// Moves by an exact number of canonical rows. Positive rows reveal older
  /// history; negative rows move toward the live viewport.
  bool scrollRows(
    int rows, {
    required int historyCount,
    required int historyRowBase,
    required bool alternateScreen,
  }) {
    if (historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    if (rows == 0 || alternateScreen || historyCount == 0) return false;

    final requested = _targetOffset + rows;
    final clamped = requested.clamp(0, historyCount);
    if (clamped == _targetOffset) return false;

    if (clamped == 0) return reset();
    _targetRevision += 1;
    _targetOffset = clamped;
    _anchorTopRow = historyRowBase + historyCount - clamped;
    return true;
  }

  /// Repositions a scrolled viewport after the live terminal advances while
  /// preserving the previously displayed absolute top row where possible.
  ///
  /// If the anchored row has fallen out of the bounded history ring, the
  /// viewport clamps to the oldest retained row and adopts that as its anchor.
  /// Call for every live view, including while inactive, to track the geometry
  /// and retained lower bound used to admit asynchronous history responses.
  bool followLive({
    required int rows,
    required int columns,
    required int historyCount,
    required int historyRowBase,
    required bool alternateScreen,
  }) {
    if (historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    if (rows <= 0 || columns <= 0) {
      throw ArgumentError('geometry must be positive');
    }
    final geometryChanged = _geometry != null && _geometry != (rows, columns);
    _geometry = (rows, columns);
    _retainedRowBase = historyRowBase;
    // Reflow invalidates absolute row anchors. Ordinary output does not.
    if (geometryChanged || alternateScreen || historyCount == 0) return reset();
    if (!active) return false;
    _targetRevision += 1;

    final anchor = _anchorTopRow;
    if (anchor == null) return reset();
    final newestHistoryEnd = historyRowBase + historyCount;
    final requested = newestHistoryEnd - anchor;
    final clamped = requested.clamp(0, historyCount);
    if (clamped == 0) return reset();

    final changed = clamped != _targetOffset;
    _targetOffset = clamped;
    if (clamped != requested) {
      _anchorTopRow = newestHistoryEnd - clamped;
    }
    return changed;
  }

  /// Complete older targets may be shown, but never after cancellation,
  /// known reflow/bank changes, or eviction of their returned top row.
  bool canPresent(
    HistoryRequest request, {
    required int historyOffset,
    required int historyCount,
    required int historyRowBase,
    required int rows,
    required int columns,
    required bool alternateScreen,
  }) {
    if (historyOffset < 0 || historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    return ownsRequest(request) &&
        _geometry == (rows, columns) &&
        !alternateScreen &&
        historyOffset > 0 &&
        historyOffset <= historyCount &&
        historyRowBase + historyCount - historyOffset >= _retainedRowBase;
  }

  /// Recheck after preparation, then reconcile only an unchanged target.
  /// A true result admits presentation; it need not change desired state.
  bool acceptSnapshot(
    HistoryRequest request, {
    required int historyOffset,
    required int historyCount,
    required int historyRowBase,
    required int rows,
    required int columns,
    required bool alternateScreen,
  }) {
    if (!canPresent(
      request,
      historyOffset: historyOffset,
      historyCount: historyCount,
      historyRowBase: historyRowBase,
      rows: rows,
      columns: columns,
      alternateScreen: alternateScreen,
    )) {
      return false;
    }
    if (request._targetRevision == _targetRevision) {
      _targetOffset = historyOffset;
      _anchorTopRow = historyRowBase + historyCount - historyOffset;
    }
    return true;
  }

  bool reset() {
    final changed =
        active || _anchorTopRow != null || _dragRemainderPixels != 0;
    if (changed) _lifetime = Object();
    _targetOffset = 0;
    _anchorTopRow = null;
    _dragRemainderPixels = 0;
    return changed;
  }
}
