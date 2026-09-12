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

  test('raster density supersamples physical presentation without changing presets', () {
    expect(terminalRasterScale(0), 1);
    expect(terminalRasterScale(double.nan), 1);
    expect(terminalRasterScale(1.0), 1);
    expect(terminalRasterScale(1.7), 2);
    expect(terminalRasterScale(2.5), 3);
    expect(terminalRasterScale(4.8), 4);

    final compact = TerminalZoomPreset.compact.presentation.rasterized(2);
    expect(compact.fontPixels, 18);
    expect(compact.cellWidth, 12);
    expect(compact.lineHeight, 24);

    final normal = TerminalZoomPreset.normal.presentation.rasterized(3);
    expect(normal.fontPixels, 48);
    expect(normal.cellWidth, 30);
    expect(normal.lineHeight, 60);
    expect(
      () => TerminalZoomPreset.normal.presentation.rasterized(5),
      throwsRangeError,
    );
  });
}
