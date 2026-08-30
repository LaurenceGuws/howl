import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/launch_config.dart';

void main() {
  test('compiled geometry authority is usable on mobile builds', () {
    expect(
      geometryLeaderEnabled(compiledValue: '1', environmentValue: null),
      isTrue,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '0', environmentValue: '1'),
      isFalse,
    );
  });

  test('desktop environment remains a fallback when no define is compiled', () {
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: '1'),
      isTrue,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: '0'),
      isFalse,
    );
    expect(
      geometryLeaderEnabled(compiledValue: '', environmentValue: null),
      isFalse,
    );
  });
}
