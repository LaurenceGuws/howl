import 'terminal_selection.dart';

/// Small desktop-pointer state machine over the shared terminal selection model.
///
/// Platform event routing and canonical mouse-mode policy stay in the app shell;
/// this owner only remembers one local primary-drag selection.
final class DesktopSelectionController {
  int? _pointer;
  TerminalSelectionPoint? _anchor;
  TerminalSelectionRange? _range;
  bool _moved = false;

  int? get pointer => _pointer;
  TerminalSelectionRange? get range => _range;
  bool get active => _pointer != null;

  TerminalSelectionRange start({
    required int pointer,
    required TerminalSelectionPoint point,
    required int columns,
    required bool alternateScreen,
  }) {
    _pointer = pointer;
    _anchor = point;
    _moved = false;
    return _range = TerminalSelectionRange(
      anchor: point,
      focus: point,
      columns: columns,
      alternateScreen: alternateScreen,
    );
  }

  TerminalSelectionRange? update(int pointer, TerminalSelectionPoint point) {
    final anchor = _anchor;
    final current = _range;
    if (_pointer != pointer || anchor == null || current == null) return null;
    if (current.focus == point) return current;
    _moved = _moved || point != anchor;
    return _range = TerminalSelectionRange(
      anchor: anchor,
      focus: point,
      columns: current.columns,
      alternateScreen: current.alternateScreen,
    );
  }

  ({TerminalSelectionRange? range, bool keep}) finish(int pointer) {
    if (_pointer != pointer) return (range: _range, keep: _range != null);
    final result = (range: _range, keep: _moved);
    _pointer = null;
    _anchor = null;
    _moved = false;
    if (!result.keep) _range = null;
    return result;
  }

  void clear() {
    _pointer = null;
    _anchor = null;
    _range = null;
    _moved = false;
  }
}
