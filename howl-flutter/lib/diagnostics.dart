import 'dart:collection';

final class HowlDiagnosticEntry {
  const HowlDiagnosticEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });

  final DateTime timestamp;
  final String source;
  final String message;

  String format() {
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '[$hh:$mm:$ss.$ms] [$source] $message';
  }
}

/// Bounded, memory-only operator trace for platform/transport diagnostics.
///
/// This deliberately has no persistence or network sink. The mobile control
/// strip may copy the current bounded trace to the system clipboard for an
/// attended debugging session.
final class HowlDiagnostics {
  HowlDiagnostics({this.maximumEntries = 96})
    : assert(maximumEntries > 0 && maximumEntries <= 256);

  final int maximumEntries;
  final List<HowlDiagnosticEntry> _entries = <HowlDiagnosticEntry>[];

  UnmodifiableListView<HowlDiagnosticEntry> get entries =>
      UnmodifiableListView<HowlDiagnosticEntry>(_entries);

  void record(String source, String message, {DateTime? timestamp}) {
    final safeSource = _singleLine(source, maximumLength: 32);
    final safeMessage = _singleLine(message, maximumLength: 320);
    if (safeSource.isEmpty || safeMessage.isEmpty) return;
    _entries.add(
      HowlDiagnosticEntry(
        timestamp: timestamp ?? DateTime.now(),
        source: safeSource,
        message: safeMessage,
      ),
    );
    if (_entries.length > maximumEntries) {
      _entries.removeRange(0, _entries.length - maximumEntries);
    }
  }

  String export() => _entries.map((entry) => entry.format()).join('\n');

  static String _singleLine(String value, {required int maximumLength}) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (normalized.length <= maximumLength) return normalized;
    return '${normalized.substring(0, maximumLength - 1)}…';
  }
}
