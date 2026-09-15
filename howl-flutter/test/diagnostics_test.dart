import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/diagnostics.dart';

void main() {
  test('diagnostics are bounded, single-line, and copy-ready', () {
    final diagnostics = HowlDiagnostics(maximumEntries: 3);
    final base = DateTime.utc(2026, 9, 15, 12);
    diagnostics.record('Transport', 'one', timestamp: base);
    diagnostics.record(
      'Native',
      'two\ninjected',
      timestamp: base.add(const Duration(milliseconds: 1)),
    );
    diagnostics.record(
      'Transport',
      'three',
      timestamp: base.add(const Duration(milliseconds: 2)),
    );
    diagnostics.record(
      'Transport',
      'four',
      timestamp: base.add(const Duration(milliseconds: 3)),
    );

    expect(diagnostics.entries, hasLength(3));
    expect(diagnostics.entries.first.message, 'two injected');
    final exported = diagnostics.export();
    expect(exported, contains('[Native] two injected'));
    expect(exported, contains('[Transport] four'));
    expect(exported, isNot(contains('[Transport] one')));
    expect(exported, isNot(contains('\ninjected')));
  });
}
