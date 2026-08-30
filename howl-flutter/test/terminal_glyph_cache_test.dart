import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_glyph_cache.dart';

void main() {
  test('identical grapheme style and width reuse one layout', () {
    final cache = TerminalGlyphCache(maxEntries: 4);
    addTearDown(cache.dispose);
    final first = cache.resolve(
      text: 'A',
      foreground: const Color(0xffeeeeee),
      style: 0,
      underlineStyle: 0,
      underlineColor: const Color(0xffeeeeee),
      maxWidth: 10,
      fontSize: 16,
    );
    final second = cache.resolve(
      text: 'A',
      foreground: const Color(0xffeeeeee),
      style: 0,
      underlineStyle: 0,
      underlineColor: const Color(0xffeeeeee),
      maxWidth: 10,
      fontSize: 16,
    );
    expect(identical(first, second), isTrue);
    expect(cache.length, 1);
  });

  test('cache remains bounded across distinct glyphs', () {
    final cache = TerminalGlyphCache(maxEntries: 2);
    addTearDown(cache.dispose);
    for (final text in <String>['A', 'B', 'C']) {
      cache.resolve(
        text: text,
        foreground: const Color(0xffffffff),
        style: 0,
        underlineStyle: 0,
        underlineColor: const Color(0xffffffff),
        maxWidth: 10,
        fontSize: 16,
      );
    }
    expect(cache.length, 2);
  });
}
