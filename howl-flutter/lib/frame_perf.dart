final class _BoundedSamples {
  _BoundedSamples({this.capacity = 240})
    : assert(capacity > 0),
      _values = List<int>.filled(capacity, 0, growable: false);

  final int capacity;
  final List<int> _values;
  int _length = 0;
  int _next = 0;

  int get length => _length;

  void add(int value) {
    if (value < 0) return;
    _values[_next] = value;
    _next += 1;
    if (_next == capacity) _next = 0;
    if (_length < capacity) _length += 1;
  }

  void clear() {
    _length = 0;
    _next = 0;
  }

  int percentile(double fraction) {
    if (_length == 0) return 0;
    final sorted = List<int>.of(_values.take(_length))..sort();
    final index = ((sorted.length - 1) * fraction).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  int get maximum {
    if (_length == 0) return 0;
    var result = _values[0];
    for (var index = 1; index < _length; index += 1) {
      if (_values[index] > result) result = _values[index];
    }
    return result;
  }
}

/// Bounded metadata-only performance evidence for attended Howl canaries.
///
/// This deliberately retains no terminal text, input, Canvas payload, or packet
/// bytes. Packet size and command count are recorded only as integer metadata.
/// `adoptGapUs` measures accepted terminal-frame adoption cadence in Dart; it is
/// not a claim that pixels have reached the display. Flutter engine FrameTiming
/// is recorded separately for build/raster/total timing.
final class TerminalFramePerf {
  final _BoundedSamples _observeUs = _BoundedSamples();
  final _BoundedSamples _prepareUs = _BoundedSamples();
  final _BoundedSamples _displayWaitUs = _BoundedSamples();
  final _BoundedSamples _adoptGapUs = _BoundedSamples();
  final _BoundedSamples _revisionGap = _BoundedSamples();
  final _BoundedSamples _packetBytes = _BoundedSamples();
  final _BoundedSamples _commands = _BoundedSamples();
  final _BoundedSamples _buildUs = _BoundedSamples();
  final _BoundedSamples _rasterUs = _BoundedSamples();
  final _BoundedSamples _totalUs = _BoundedSamples();
  final _BoundedSamples _vsyncOverheadUs = _BoundedSamples();

  void recordTerminal({
    required int observeUs,
    required int prepareUs,
    required int displayWaitUs,
    required int packetBytes,
    required int commands,
    int? adoptGapUs,
    int? revisionGap,
  }) {
    _observeUs.add(observeUs);
    _prepareUs.add(prepareUs);
    _displayWaitUs.add(displayWaitUs);
    _packetBytes.add(packetBytes);
    _commands.add(commands);
    if (adoptGapUs != null) _adoptGapUs.add(adoptGapUs);
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
      'adopt_gap=${_durationSummary(_adoptGapUs)} '
      'rev_gap=${_integerSummary(_revisionGap)} '
      'packet_kib=${_kibSummary(_packetBytes)} '
      'commands=${_integerSummary(_commands)}';

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
      _adoptGapUs,
      _revisionGap,
      _packetBytes,
      _commands,
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

  static String _kibSummary(_BoundedSamples samples) =>
      '${_kib(samples.percentile(.50))}/${_kib(samples.percentile(.95))}/${_kib(samples.maximum)}';

  static String _ms(int microseconds) =>
      (microseconds / 1000).toStringAsFixed(microseconds >= 10000 ? 0 : 1);

  static String _kib(int bytes) => (bytes / 1024).toStringAsFixed(1);
}
