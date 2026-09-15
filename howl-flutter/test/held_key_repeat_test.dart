import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/held_key_repeat.dart';

void main() {
  test('held key repeats after delay and stops on matching release', () async {
    final repeats = <(int, int)>[];
    final repeat = HeldKeyRepeat(
      initialDelay: const Duration(milliseconds: 10),
      interval: const Duration(milliseconds: 5),
      onRepeat: (key, modifiers) => repeats.add((key, modifiers)),
    );
    repeat.start(7, 4);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(repeats, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(repeats, isNotEmpty);
    expect(repeats.every((entry) => entry == (7, 4)), isTrue);
    repeat.cancel(key: 7);
    final stoppedAt = repeats.length;
    await Future<void>.delayed(const Duration(milliseconds: 12));
    expect(repeats.length, stoppedAt);
  });

  test('unrelated release does not cancel held key', () async {
    var ticks = 0;
    final repeat = HeldKeyRepeat(
      initialDelay: Duration.zero,
      interval: const Duration(milliseconds: 5),
      onRepeat: (_, _) => ticks += 1,
    );
    repeat.start(3, 0);
    repeat.cancel(key: 4);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(ticks, greaterThan(0));
    repeat.close();
  });
}
