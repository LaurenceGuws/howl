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

  int get targetOffset => _targetOffset;
  int? get anchorTopRow => _anchorTopRow;
  bool get active => _targetOffset != 0;

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

    _targetOffset = clamped;
    _anchorTopRow = clamped == 0
        ? null
        : historyRowBase + historyCount - clamped;
    return true;
  }

  /// Repositions a scrolled viewport after the live terminal advances while
  /// preserving the previously displayed absolute top row where possible.
  ///
  /// If the anchored row has fallen out of the bounded history ring, the
  /// viewport clamps to the oldest retained row and adopts that as its anchor.
  bool followLive({
    required int historyCount,
    required int historyRowBase,
    required bool alternateScreen,
  }) {
    if (historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    if (!active) return false;
    if (alternateScreen || historyCount == 0) return reset();

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

  /// Accepts the server's canonical/clamped response for one history request.
  void acceptSnapshot({
    required int historyOffset,
    required int historyCount,
    required int historyRowBase,
    required bool alternateScreen,
  }) {
    if (historyOffset < 0 || historyCount < 0 || historyRowBase < 0) {
      throw ArgumentError('history counters must be non-negative');
    }
    if (alternateScreen || historyOffset == 0 || historyCount == 0) {
      reset();
      return;
    }
    _targetOffset = historyOffset.clamp(0, historyCount);
    if (_targetOffset == 0) {
      _anchorTopRow = null;
      return;
    }
    _anchorTopRow = historyRowBase + historyCount - _targetOffset;
  }

  bool reset() {
    final changed =
        active || _anchorTopRow != null || _dragRemainderPixels != 0;
    _targetOffset = 0;
    _anchorTopRow = null;
    _dragRemainderPixels = 0;
    return changed;
  }
}
