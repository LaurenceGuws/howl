import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/desktop_selection.dart';
import 'package:howl_flutter/terminal_selection.dart';

void main() {
  const first = TerminalSelectionPoint(row: 10, column: 4);
  const second = TerminalSelectionPoint(row: 12, column: 7);

  test('desktop selection keeps only a moved primary drag', () {
    final controller = DesktopSelectionController();
    final initial = controller.start(
      pointer: 7,
      point: first,
      columns: 80,
      alternateScreen: false,
    );
    expect(controller.pointer, 7);
    expect(initial.anchor, first);
    expect(controller.finish(7).keep, isFalse);
    expect(controller.range, isNull);

    controller.start(
      pointer: 9,
      point: first,
      columns: 80,
      alternateScreen: true,
    );
    final moved = controller.update(9, second)!;
    expect(moved.anchor, first);
    expect(moved.focus, second);
    expect(moved.alternateScreen, isTrue);
    final finished = controller.finish(9);
    expect(finished.keep, isTrue);
    expect(finished.range?.focus, second);
    expect(controller.active, isFalse);
    expect(controller.range?.focus, second);
  });

  test('wrong pointer cannot mutate or finish the drag', () {
    final controller = DesktopSelectionController()
      ..start(pointer: 3, point: first, columns: 20, alternateScreen: false);
    expect(controller.update(4, second), isNull);
    expect(controller.finish(4).keep, isTrue);
    expect(controller.pointer, 3);
    controller.clear();
    expect(controller.range, isNull);
    expect(controller.active, isFalse);
  });
}
