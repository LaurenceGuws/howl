import 'dart:collection';

import 'package:flutter/painting.dart';

import 'terminal_font.dart';

/// Bounded cache for immutable, already-laid-out terminal graphemes.
///
/// Canonical terminal semantics stay in Howl. This cache owns only Flutter text
/// layout work that is safe to reuse when text, resolved style, and cell width
/// are identical.
final class TerminalGlyphCache {
  TerminalGlyphCache({this.maxEntries = 512}) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<_GlyphKey, TextPainter> _painters = LinkedHashMap();

  int get length => _painters.length;

  TextPainter resolve({
    required String text,
    required Color foreground,
    required int style,
    required int underlineStyle,
    required Color underlineColor,
    required double maxWidth,
    required double fontSize,
  }) {
    final key = _GlyphKey(
      text: text,
      foreground: foreground.toARGB32(),
      style: style,
      underlineStyle: underlineStyle,
      underlineColor: underlineColor.toARGB32(),
      maxWidth: maxWidth,
      fontSize: fontSize,
    );
    final existing = _painters.remove(key);
    if (existing != null) {
      _painters[key] = existing;
      return existing;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: foreground,
          fontFamily: terminalFontFamily,
          fontFamilyFallback: terminalFontFamilyFallback,
          fontSize: fontSize,
          height: 1,
          fontWeight: style & 1 != 0 ? FontWeight.bold : FontWeight.normal,
          fontStyle: style & (1 << 2) != 0
              ? FontStyle.italic
              : FontStyle.normal,
          decoration: _textDecoration(style),
          decorationStyle: _underlineDecoration(underlineStyle),
          decorationColor: underlineColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    _painters[key] = painter;

    if (_painters.length > maxEntries) {
      final oldest = _painters.keys.first;
      _painters.remove(oldest)?.dispose();
    }
    return painter;
  }

  void dispose() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

final class _GlyphKey {
  const _GlyphKey({
    required this.text,
    required this.foreground,
    required this.style,
    required this.underlineStyle,
    required this.underlineColor,
    required this.maxWidth,
    required this.fontSize,
  });

  final String text;
  final int foreground;
  final int style;
  final int underlineStyle;
  final int underlineColor;
  final double maxWidth;
  final double fontSize;

  @override
  bool operator ==(Object other) =>
      other is _GlyphKey &&
      other.text == text &&
      other.foreground == foreground &&
      other.style == style &&
      other.underlineStyle == underlineStyle &&
      other.underlineColor == underlineColor &&
      other.maxWidth == maxWidth &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(
    text,
    foreground,
    style,
    underlineStyle,
    underlineColor,
    maxWidth,
    fontSize,
  );
}

TextDecoration _textDecoration(int style) {
  final values = <TextDecoration>[];
  if (style & (1 << 7) != 0) values.add(TextDecoration.underline);
  if (style & (1 << 8) != 0) values.add(TextDecoration.lineThrough);
  return values.isEmpty ? TextDecoration.none : TextDecoration.combine(values);
}

TextDecorationStyle _underlineDecoration(int value) => switch (value) {
  1 => TextDecorationStyle.double,
  2 => TextDecorationStyle.wavy,
  3 => TextDecorationStyle.dotted,
  4 => TextDecorationStyle.dashed,
  _ => TextDecorationStyle.solid,
};
