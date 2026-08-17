import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/main.dart';

void main() {
  test('named physical keys use frozen Howl identities', () {
    expect(howlNamedKey(PhysicalKeyboardKey.enter), 1);
    expect(howlNamedKey(PhysicalKeyboardKey.arrowUp), 5);
    expect(howlNamedKey(PhysicalKeyboardKey.arrowRight), 8);
    expect(howlNamedKey(PhysicalKeyboardKey.f12), 40);
    expect(howlNamedKey(PhysicalKeyboardKey.numpadEnter), 58);
  });
}
