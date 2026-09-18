import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/history_viewport.dart';

void live(
  HistoryViewport viewport, {
  int rows = 24,
  int columns = 80,
  int count = 1000,
  int base = 100,
  bool alternate = false,
}) {
  viewport.followLive(
    rows: rows,
    columns: columns,
    historyCount: count,
    historyRowBase: base,
    alternateScreen: alternate,
  );
}

void move(HistoryViewport viewport, int rows) {
  viewport.drag(
    deltaY: -rows * 20.0,
    rowHeight: 20,
    historyCount: 1000,
    historyRowBase: 100,
    alternateScreen: false,
  );
}

// The same real policy runs before and after asynchronous preparation. There
// is no copied drain, scheduler, or alternate viewport implementation here.
bool snapshot(
  HistoryViewport viewport,
  HistoryRequest request, {
  bool accept = true,
  int? offset,
  int count = 1000,
  int base = 100,
  int rows = 24,
  int columns = 80,
  bool alternate = false,
}) {
  final check = accept ? viewport.acceptSnapshot : viewport.canPresent;
  return check(
    request,
    historyOffset: offset ?? request.offset,
    historyCount: count,
    historyRowBase: base,
    rows: rows,
    columns: columns,
    alternateScreen: alternate,
  );
}

HistoryViewport entered([int offset = 1]) {
  final viewport = HistoryViewport();
  live(viewport);
  move(viewport, offset);
  return viewport;
}

void main() {
  for (final duringPreparation in [false, true]) {
    test('sustained motion admits views; prepare=$duringPreparation', () {
      final viewport = entered();
      final presented = <int>[];
      for (var i = 1; i <= 100; i++) {
        final request = viewport.captureRequest();
        expect(request.offset, i);
        if (duringPreparation) {
          expect(snapshot(viewport, request, accept: false), isTrue);
        }
        move(viewport, 1);
        expect(viewport.ownsRequest(request), isTrue);
        expect(snapshot(viewport, request), isTrue);
        presented.add(request.offset);
        expect(viewport.targetOffset, i + 1);
        expect(viewport.anchorTopRow, 1100 - (i + 1));
      }
      final latest = viewport.captureRequest();
      expect(snapshot(viewport, latest), isTrue);
      expect(latest.offset, 101);
      expect(presented, List<int>.generate(100, (i) => i + 1));
    });
  }

  test('reversal and a round trip never restore an old desired anchor', () {
    final viewport = entered(10);
    final request = viewport.captureRequest();
    move(viewport, -4);
    expect(snapshot(viewport, request), isTrue);
    expect(viewport.targetOffset, 6);
    move(viewport, 4);
    // Same offset is not the same target revision; server clamping must not
    // overwrite the intervening user decision.
    expect(snapshot(viewport, request, offset: 7), isTrue);
    expect(viewport.targetOffset, 10);
    expect(viewport.anchorTopRow, 1090);
  });

  test('LIVE and reentry reject old results and old worker errors', () {
    final viewport = entered();
    final old = viewport.captureRequest();
    move(viewport, -1);
    expect(viewport.ownsRequest(old), isFalse);
    expect(snapshot(viewport, old), isFalse);
    move(viewport, 7);
    expect(viewport.ownsRequest(old), isFalse);
    expect(snapshot(viewport, old), isFalse);
    expect(viewport.targetOffset, 7);
    expect(snapshot(viewport, viewport.captureRequest()), isTrue);
  });

  test(
    'explicit connection/presentation reset invalidates pending creation',
    () {
      final viewport = entered();
      final creating = viewport.captureRequest();
      viewport.reset();
      viewport.reset();
      move(viewport, 7);
      expect(viewport.ownsRequest(creating), isFalse);
      expect(snapshot(viewport, creating), isFalse);
      expect(viewport.targetOffset, 7);
    },
  );

  test('motion during creation can recapture the latest target', () {
    final viewport = entered();
    final creating = viewport.captureRequest();
    move(viewport, 6);
    expect(viewport.ownsRequest(creating), isTrue);
    expect(viewport.captureRequest().offset, 7);
  });

  for (final change in ['rows', 'columns', 'bank', 'empty']) {
    test('$change cancels even after admission and subsequent restoration', () {
      final viewport = entered(10);
      final request = viewport.captureRequest();
      expect(snapshot(viewport, request, accept: false), isTrue);
      live(
        viewport,
        rows: change == 'rows' ? 25 : 24,
        columns: change == 'columns' ? 81 : 80,
        alternate: change == 'bank',
        count: change == 'empty' ? 0 : 1000,
      );
      expect(viewport.active, isFalse);
      expect(viewport.ownsRequest(request), isFalse);
      live(viewport);
      move(viewport, 10);
      expect(snapshot(viewport, request), isFalse);
      expect(snapshot(viewport, viewport.captureRequest()), isTrue);
    });
  }

  test('growth and ring rotation preserve latest anchor without starving', () {
    final viewport = entered(10);
    final request = viewport.captureRequest();
    live(viewport, count: 1001);
    expect(snapshot(viewport, request), isTrue);
    expect(viewport.targetOffset, 11);
    expect(viewport.anchorTopRow, 1090);
    live(viewport, base: 102);
    expect(snapshot(viewport, request), isTrue);
    expect(viewport.targetOffset, 12);
    expect(viewport.anchorTopRow, 1090);
  });

  test(
    'eviction rechecks returned top after admission; latest clamp survives',
    () {
      final viewport = entered(10);
      final request = viewport.captureRequest();
      expect(snapshot(viewport, request, accept: false), isTrue);
      live(viewport, base: 1091);
      expect(viewport.ownsRequest(request), isTrue);
      expect(snapshot(viewport, request), isFalse);
      expect(viewport.targetOffset, 1000);
      expect(viewport.anchorTopRow, 1091);
      expect(snapshot(viewport, viewport.captureRequest(), base: 1091), isTrue);
    },
  );

  test('unchanged offset after live eviction is still a newer intent', () {
    final viewport = entered(1000);
    final request = viewport.captureRequest();
    live(viewport, base: 101);
    expect(viewport.targetOffset, 1000);
    expect(snapshot(viewport, request, offset: 999), isTrue);
    expect(viewport.targetOffset, 1000);
    expect(viewport.anchorTopRow, 101);
  });

  test('invalid response cannot clear or reconcile current intent', () {
    final viewport = entered(10);
    final request = viewport.captureRequest();
    expect(snapshot(viewport, request, rows: 25), isFalse);
    expect(snapshot(viewport, request, columns: 81), isFalse);
    expect(snapshot(viewport, request, alternate: true), isFalse);
    expect(snapshot(viewport, request, offset: 0), isFalse);
    expect(snapshot(viewport, request, count: 0), isFalse);
    expect(snapshot(viewport, request, offset: 1001), isFalse);
    expect(viewport.targetOffset, 10);
    expect(viewport.anchorTopRow, 1090);
  });

  test('selection row changes protect intent just like touch motion', () {
    final viewport = entered(10);
    final request = viewport.captureRequest();
    viewport.scrollRows(
      5,
      historyCount: 1000,
      historyRowBase: 100,
      alternateScreen: false,
    );
    expect(snapshot(viewport, request), isTrue);
    expect(viewport.targetOffset, 15);
  });

  test('fractional drag survives admission until a whole row accumulates', () {
    final viewport = entered(10);
    final request = viewport.captureRequest();
    for (var i = 0; i < 2; i++) {
      viewport.drag(
        deltaY: -10,
        rowHeight: 20,
        historyCount: 1000,
        historyRowBase: 100,
        alternateScreen: false,
      );
      expect(snapshot(viewport, request), isTrue);
    }
    expect(viewport.targetOffset, 11);
  });

  test('request belongs to one viewport, and inactive capture is rejected', () {
    final viewport = entered();
    final other = entered();
    expect(viewport.ownsRequest(other.captureRequest()), isFalse);
    viewport.reset();
    expect(viewport.captureRequest, throwsStateError);
  });
}
