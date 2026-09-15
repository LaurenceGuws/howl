import 'dart:async';

/// Owns one synthetic hold-repeat clock for platform key hosts that expose
/// press/release but no repeat transitions.
final class HeldKeyRepeat {
  HeldKeyRepeat({
    required this.onRepeat,
    this.initialDelay = const Duration(milliseconds: 500),
    this.interval = const Duration(milliseconds: 100),
  }) : assert(!initialDelay.isNegative),
       assert(interval > Duration.zero);

  final void Function(int key, int modifiers) onRepeat;
  final Duration initialDelay;
  final Duration interval;

  Timer? _delay;
  Timer? _periodic;
  int? _key;
  int _modifiers = 0;

  int? get key => _key;
  bool get active => _key != null;

  void start(int key, int modifiers) {
    cancel();
    _key = key;
    _modifiers = modifiers;
    _delay = Timer(initialDelay, () {
      final current = _key;
      if (current == null) return;
      onRepeat(current, _modifiers);
      _periodic = Timer.periodic(interval, (_) {
        final repeating = _key;
        if (repeating != null) onRepeat(repeating, _modifiers);
      });
    });
  }

  void cancel({int? key}) {
    if (key != null && key != _key) return;
    _delay?.cancel();
    _periodic?.cancel();
    _delay = null;
    _periodic = null;
    _key = null;
    _modifiers = 0;
  }

  void close() => cancel();
}
