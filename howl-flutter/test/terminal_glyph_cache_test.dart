import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_glyph_cache.dart';

void main() {
  test('identical grapheme style and width reuse one layout', () {
    final cache = TerminalGlyphCache(maxEntries: 4);
    addTearDown(cache.dispose);
    final first = cache.resolve(
      scalars: <int>[65],
      foreground: const Color(0xffeeeeee),
      style: 0,
      underlineStyle: 0,
      underlineColor: const Color(0xffeeeeee),
      maxWidth: 10,
      fontSize: 16,
    );
    final second = cache.resolve(
      scalars: List<int>.from(<int>[65]),
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
    for (final scalar in <int>[65, 66, 67]) {
      cache.resolve(
        scalars: <int>[scalar],
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
