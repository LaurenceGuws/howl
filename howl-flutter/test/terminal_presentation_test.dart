import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_presentation.dart';

void main() {
  test('zoom presets carry exact native raster and cell identities', () {
    expect(
      TerminalZoomPreset.values.map((preset) => preset.presentation.fontPixels),
      <int>[9, 12, 16],
    );
    expect(
      TerminalZoomPreset.values.map((preset) => preset.presentation.cellWidth),
      <int>[6, 8, 10],
    );
    expect(
      TerminalZoomPreset.values.map((preset) => preset.presentation.lineHeight),
      <int>[12, 15, 20],
    );
    expect(TerminalZoomPreset.normal.next, TerminalZoomPreset.small);
    expect(TerminalZoomPreset.small.next, TerminalZoomPreset.compact);
    expect(TerminalZoomPreset.compact.next, TerminalZoomPreset.normal);
  });
}
