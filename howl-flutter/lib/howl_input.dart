/// Language-neutral semantic identities accepted by the app-private native host.
///
/// These are not terminal escape encodings. Howl's native protocol/VT remains
/// authoritative for serialization and terminal byte generation.
abstract final class HowlInput {
  static const keyPress = 1;
  static const keyRepeat = 2;
  static const keyRelease = 3;

  static const mousePress = 1;
  static const mouseRelease = 2;
  static const mouseMove = 3;
  static const mouseWheel = 4;

  static const mouseNone = 0;
  static const mouseLeft = 1;
  static const mouseMiddle = 2;
  static const mouseRight = 3;
  static const mouseWheelUp = 4;
  static const mouseWheelDown = 5;

  static const namedEnter = 1;
  static const namedBackspace = 3;
  static const namedDelete = 10;

  static const maximumRows = 128;
  static const maximumColumns = 256;
}

final class HowlMouseInput {
  const HowlMouseInput({
    required this.kind,
    required this.button,
    required this.modifiers,
    required this.buttonsDown,
    required this.row,
    required this.column,
    this.pixelX,
    this.pixelY,
  });

  final int kind;
  final int button;
  final int modifiers;
  final int buttonsDown;
  final int row;
  final int column;
  final int? pixelX;
  final int? pixelY;
}
