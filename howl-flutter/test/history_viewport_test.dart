import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/history_viewport.dart';

void main() {
  test('touch drag accumulates whole rows with terminal direction', () {
    final viewport = HistoryViewport()..beginDrag();

    expect(
      viewport.drag(
        deltaY: -9,
        rowHeight: 20,
        historyCount: 50,
        historyRowBase: 100,
        alternateScreen: false,
      ),
      isFalse,
    );
    expect(viewport.targetOffset, 0);

    expect(
      viewport.drag(
        deltaY: -32,
        rowHeight: 20,
        historyCount: 50,
        historyRowBase: 100,
        alternateScreen: false,
      ),
      isTrue,
    );
    expect(viewport.targetOffset, 2);
    expect(viewport.anchorTopRow, 148);

    expect(
      viewport.drag(
        deltaY: 21,
        rowHeight: 20,
        historyCount: 50,
        historyRowBase: 100,
        alternateScreen: false,
      ),
      isTrue,
    );
    expect(viewport.targetOffset, 1);
    expect(viewport.anchorTopRow, 149);
  });

  test('drag clamps at live and oldest history without sticky remainder', () {
    final viewport = HistoryViewport()..beginDrag();
    viewport.drag(
      deltaY: -400,
      rowHeight: 20,
      historyCount: 3,
      historyRowBase: 40,
      alternateScreen: false,
    );
    expect(viewport.targetOffset, 3);
    expect(viewport.anchorTopRow, 40);

    viewport.drag(
      deltaY: 400,
      rowHeight: 20,
      historyCount: 3,
      historyRowBase: 40,
      alternateScreen: false,
    );
    expect(viewport.targetOffset, 0);
    expect(viewport.anchorTopRow, isNull);

    expect(
      viewport.drag(
        deltaY: -10,
        rowHeight: 20,
        historyCount: 3,
        historyRowBase: 40,
        alternateScreen: false,
      ),
      isFalse,
    );
  });

  test('live history growth preserves absolute anchored top row', () {
    final viewport = HistoryViewport();
    viewport.acceptSnapshot(
      historyOffset: 10,
      historyCount: 100,
      historyRowBase: 1000,
      alternateScreen: false,
    );
    expect(viewport.anchorTopRow, 1090);

    expect(
      viewport.followLive(
        historyCount: 101,
        historyRowBase: 1000,
        alternateScreen: false,
      ),
      isTrue,
    );
    expect(viewport.targetOffset, 11);
    expect(viewport.anchorTopRow, 1090);
  });

  test('ring rotation preserves anchor and eviction clamps to oldest row', () {
    final viewport = HistoryViewport();
    viewport.acceptSnapshot(
      historyOffset: 10,
      historyCount: 100,
      historyRowBase: 1000,
      alternateScreen: false,
    );

    viewport.followLive(
      historyCount: 100,
      historyRowBase: 1001,
      alternateScreen: false,
    );
    expect(viewport.targetOffset, 11);
    expect(viewport.anchorTopRow, 1090);

    viewport.followLive(
      historyCount: 100,
      historyRowBase: 1100,
      alternateScreen: false,
    );
    expect(viewport.targetOffset, 100);
    expect(viewport.anchorTopRow, 1100);
  });

  test('alternate screen and empty history cannot enter scrollback', () {
    final viewport = HistoryViewport()..beginDrag();
    expect(
      viewport.drag(
        deltaY: -80,
        rowHeight: 20,
        historyCount: 20,
        historyRowBase: 0,
        alternateScreen: true,
      ),
      isFalse,
    );
    expect(viewport.active, isFalse);

    expect(
      viewport.drag(
        deltaY: -80,
        rowHeight: 20,
        historyCount: 0,
        historyRowBase: 0,
        alternateScreen: false,
      ),
      isFalse,
    );
  });

  test('server-clamped snapshot becomes the new canonical anchor', () {
    final viewport = HistoryViewport();
    viewport.acceptSnapshot(
      historyOffset: 7,
      historyCount: 7,
      historyRowBase: 20,
      alternateScreen: false,
    );
    expect(viewport.targetOffset, 7);
    expect(viewport.anchorTopRow, 20);

    viewport.acceptSnapshot(
      historyOffset: 0,
      historyCount: 0,
      historyRowBase: 0,
      alternateScreen: true,
    );
    expect(viewport.active, isFalse);
  });
}
