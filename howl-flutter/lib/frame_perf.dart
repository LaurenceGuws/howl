final class _BoundedSamples {
  _BoundedSamples({this.capacity = 240}) : assert(capacity > 0);

  final int capacity;
  final List<int> _values = <int>[];

  int get length => _values.length;

  void add(int value) {
    if (value < 0) return;
    if (_values.length == capacity) _values.removeAt(0);
    _values.add(value);
  }

  void clear() => _values.clear();

  int percentile(double fraction) {
    if (_values.isEmpty) return 0;
    final sorted = List<int>.of(_values)..sort();
    final index = ((sorted.length - 1) * fraction).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  int get maximum =>
      _values.isEmpty ? 0 : _values.reduce((a, b) => a > b ? a : b);
}

/// Bounded rolling performance evidence for attended mobile canaries.
///
/// Samples are intentionally metadata-only. No terminal text, keys, or payload
/// bytes are retained here.
final class TerminalFramePerf {
  final _BoundedSamples _observeUs = _BoundedSamples();
  final _BoundedSamples _prepareUs = _BoundedSamples();
  final _BoundedSamples _displayWaitUs = _BoundedSamples();
  final _BoundedSamples _revisionGap = _BoundedSamples();
  final _BoundedSamples _buildUs = _BoundedSamples();
  final _BoundedSamples _rasterUs = _BoundedSamples();
  final _BoundedSamples _totalUs = _BoundedSamples();
  final _BoundedSamples _vsyncOverheadUs = _BoundedSamples();

  void recordTerminal({
    required int observeUs,
    required int prepareUs,
    required int displayWaitUs,
    int? revisionGap,
  }) {
    _observeUs.add(observeUs);
    _prepareUs.add(prepareUs);
    _displayWaitUs.add(displayWaitUs);
    if (revisionGap != null) _revisionGap.add(revisionGap);
  }

  void recordFlutterFrame({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
    required int vsyncOverheadUs,
  }) {
    _buildUs.add(buildUs);
    _rasterUs.add(rasterUs);
    _totalUs.add(totalUs);
    _vsyncOverheadUs.add(vsyncOverheadUs);
  }

  String terminalSummary() =>
      'n=${_observeUs.length} '
      'observe=${_durationSummary(_observeUs)} '
      'prepare=${_durationSummary(_prepareUs)} '
      'display_wait=${_durationSummary(_displayWaitUs)} '
      'rev_gap=${_integerSummary(_revisionGap)}';

  String flutterSummary() =>
      'n=${_totalUs.length} '
      'build=${_durationSummary(_buildUs)} '
      'raster=${_durationSummary(_rasterUs)} '
      'total=${_durationSummary(_totalUs)} '
      'vsync_overhead=${_durationSummary(_vsyncOverheadUs)}';

  void reset() {
    for (final samples in <_BoundedSamples>[
      _observeUs,
      _prepareUs,
      _displayWaitUs,
      _revisionGap,
      _buildUs,
      _rasterUs,
      _totalUs,
      _vsyncOverheadUs,
    ]) {
      samples.clear();
    }
  }

  static String _durationSummary(_BoundedSamples samples) =>
      '${_ms(samples.percentile(.50))}/${_ms(samples.percentile(.95))}/${_ms(samples.maximum)}ms';

  static String _integerSummary(_BoundedSamples samples) =>
      '${samples.percentile(.50)}/${samples.percentile(.95)}/${samples.maximum}';

  static String _ms(int microseconds) =>
      (microseconds / 1000).toStringAsFixed(microseconds >= 10000 ? 0 : 1);
}
