import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_fit.dart';

void main() {
  test('center remains exact when no physical pixel scale is supplied', () {
    final fit = TerminalFit.contain(
      viewportSize: const Size(391, 723),
      logicalSize: const Size(390, 720),
    );
    expect(fit, isNotNull);
    expect(fit!.rect.left, 0.5);
    expect(fit.rect.top, 1.5);
  });

  test('center origin snaps to the DPR-3 physical pixel lattice', () {
    final fit = TerminalFit.contain(
      viewportSize: const Size(391, 723),
      logicalSize: const Size(390, 720),
      devicePixelRatio: 3,
    );
    expect(fit, isNotNull);
    expect(fit!.rect.left, closeTo(2 / 3, 1e-9));
    expect(fit.rect.top, closeTo(5 / 3, 1e-9));
    expect(fit.rect.left * 3, closeTo((fit.rect.left * 3).round(), 1e-9));
    expect(fit.rect.top * 3, closeTo((fit.rect.top * 3).round(), 1e-9));
  });

  test('invalid pixel scale preserves ordinary centered placement', () {
    final ordinary = TerminalFit.centeredOrigin(
      viewportSize: const Size(100, 100),
      contentSize: const Size(81, 83),
    );
    final invalid = TerminalFit.centeredOrigin(
      viewportSize: const Size(100, 100),
      contentSize: const Size(81, 83),
      devicePixelRatio: 0,
    );
    expect(invalid, ordinary);
  });
}
