import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_key_repeat.dart';

void main() {
  test('repeat drainer preserves exact batch count in order', () async {
    var ticks = 0;
    final drainer = TerminalKeyRepeatDrainer(
      interval: Duration.zero,
      onTick: () async => ticks += 1,
    );
    expect(drainer.add(5), isTrue);
    await drainer.idle;
    expect(ticks, 5);
    expect(drainer.pending, 0);
    expect(drainer.active, isFalse);
  });

  test(
    'repeat drainer coalesces new batches behind an in-flight tick',
    () async {
      var ticks = 0;
      final firstTick = Completer<void>();
      final drainer = TerminalKeyRepeatDrainer(
        interval: Duration.zero,
        onTick: () async {
          ticks += 1;
          if (ticks == 1) await firstTick.future;
        },
      );

      expect(drainer.add(2), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(ticks, 1);
      expect(drainer.add(3), isTrue);
      firstTick.complete();
      await drainer.idle;
      expect(ticks, 5);
    },
  );

  test('repeat drainer is bounded and pending work can be cancelled', () async {
    var ticks = 0;
    final firstTick = Completer<void>();
    final drainer = TerminalKeyRepeatDrainer(
      interval: Duration.zero,
      maximumPending: 4,
      onTick: () async {
        ticks += 1;
        if (ticks == 1) await firstTick.future;
      },
    );

    expect(drainer.add(4), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(drainer.add(2), isFalse);
    drainer.cancelPending();
    firstTick.complete();
    await drainer.idle;
    expect(ticks, 1);
  });
}
