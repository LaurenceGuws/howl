/// Discrete native terminal presentation sizes.
///
/// Each preset is one complete raster/lattice identity. Changing presets must
/// recreate the native presentation host so glyphs are rerasterized rather than
/// scaling an old atlas bitmap in Flutter.
enum TerminalZoomPreset { compact, small, normal }

final class TerminalPresentation {
  const TerminalPresentation({
    required this.fontPixels,
    required this.cellWidth,
    required this.lineHeight,
  });

  final int fontPixels;
  final int cellWidth;
  final int lineHeight;

  TerminalPresentation rasterized(int scale) {
    if (scale < 1 || scale > maximumTerminalRasterScale) {
      throw RangeError.range(scale, 1, maximumTerminalRasterScale, 'scale');
    }
    return TerminalPresentation(
      fontPixels: fontPixels * scale,
      cellWidth: cellWidth * scale,
      lineHeight: lineHeight * scale,
    );
  }
}

const int maximumTerminalRasterScale = 4;

int terminalRasterScale(double devicePixelRatio) {
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) return 1;
  return devicePixelRatio.ceil().clamp(1, maximumTerminalRasterScale);
}

extension TerminalZoomPresetPresentation on TerminalZoomPreset {
  TerminalPresentation get presentation => switch (this) {
    TerminalZoomPreset.compact => const TerminalPresentation(
      fontPixels: 9,
      cellWidth: 6,
      lineHeight: 12,
    ),
    TerminalZoomPreset.small => const TerminalPresentation(
      fontPixels: 12,
      cellWidth: 8,
      lineHeight: 15,
    ),
    TerminalZoomPreset.normal => const TerminalPresentation(
      fontPixels: 16,
      cellWidth: 10,
      lineHeight: 20,
    ),
  };

  TerminalZoomPreset get next => switch (this) {
    TerminalZoomPreset.normal => TerminalZoomPreset.small,
    TerminalZoomPreset.small => TerminalZoomPreset.compact,
    TerminalZoomPreset.compact => TerminalZoomPreset.normal,
  };
}
