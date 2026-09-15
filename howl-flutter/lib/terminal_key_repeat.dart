import 'dart:async';

/// Bounded asynchronous drainer for platform editing batches that semantically
/// represent repeated terminal keys.
///
/// Some software keyboards report accelerated deletion as increasingly large
/// document mutations. The terminal should not inherit that visual batching:
/// callers may translate one mutation into N semantic keys and drain them at a
/// stable cadence. The drainer owns no key identity or platform policy.
final class TerminalKeyRepeatDrainer {
  TerminalKeyRepeatDrainer({
    required this.onTick,
    this.interval = const Duration(milliseconds: 30),
    this.maximumPending = 4096,
  }) : assert(!interval.isNegative),
       assert(maximumPending > 0);

  final Future<void> Function() onTick;
  final Duration interval;
  final int maximumPending;

  int _pending = 0;
  bool _draining = false;
  bool _closed = false;
  Completer<void>? _idle;

  int get pending => _pending;
  bool get active => _draining || _pending != 0;
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  /// Adds exact semantic repeats. Returns false rather than silently dropping
  /// input when the bounded pending count would be exceeded.
  bool add(int count) {
    if (_closed || count <= 0) return count == 0 && !_closed;
    if (count > maximumPending - _pending) return false;
    _pending += count;
    if (_draining) return true;
    _draining = true;
    _idle = Completer<void>();
    unawaited(_drain());
    return true;
  }

  /// Cancels repeats that have not yet reached the semantic-control lane.
  /// One tick already in flight is intentionally not recalled.
  void cancelPending() {
    _pending = 0;
  }

  void close() {
    _closed = true;
    _pending = 0;
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _pending > 0) {
        _pending -= 1;
        await onTick();
        if (!_closed && _pending > 0 && interval != Duration.zero) {
          await Future<void>.delayed(interval);
        }
      }
    } finally {
      _draining = false;
      final idle = _idle;
      _idle = null;
      if (idle != null && !idle.isCompleted) idle.complete();
    }
  }
}
