import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/howl_input.dart';
import 'package:howl_flutter/main.dart';

void main() {
  test('named physical keys use frozen Howl identities', () {
    expect(howlNamedKey(PhysicalKeyboardKey.enter), 1);
    expect(howlNamedKey(PhysicalKeyboardKey.arrowUp), 5);
    expect(howlNamedKey(PhysicalKeyboardKey.arrowRight), 8);
    expect(howlNamedKey(PhysicalKeyboardKey.f12), 40);
    expect(howlNamedKey(PhysicalKeyboardKey.numpadEnter), 58);
    expect(howlNamedKey(PhysicalKeyboardKey.keyA), isNull);
  });
  test('physical Ctrl printable keys use semantic Unicode key identity', () {
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.keyF,
        HowlInput.modifierControl,
      ),
      'f'.runes.single,
    );
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.keyF,
        HowlInput.modifierControl | (1 << 0),
      ),
      'F'.runes.single,
    );
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.keyF,
        HowlInput.modifierControl | (1 << 6),
      ),
      'F'.runes.single,
    );
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.keyF,
        HowlInput.modifierControl | (1 << 0) | (1 << 6),
      ),
      'f'.runes.single,
    );
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.bracketLeft,
        HowlInput.modifierControl,
      ),
      '['.runes.single,
    );
    expect(howlControlUnicodeScalar(LogicalKeyboardKey.keyF, 0), isNull);
    expect(
      howlControlUnicodeScalar(
        LogicalKeyboardKey.enter,
        HowlInput.modifierControl,
      ),
      isNull,
    );
  });
}
