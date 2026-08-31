import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'native_host.dart';
import 'protocol.dart';

const bool nativeHostMeasurementEnabled = bool.fromEnvironment('HOWL_MEASURE');
const String _measureBegin = 'HOWL_MEASURE_BEGIN';
const String _measureEnd = 'HOWL_MEASURE_END';

final class TerminalMeasurement {
  TerminalMeasurement({required this.mode}) {
    if (!nativeHostMeasurementEnabled) return;
    _reportFile.deleteSyncIfExists();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  final String mode;
  bool _started = false;
  bool _active = false;
  bool _stopPending = false;
  bool _finished = false;
  int _paintCount = 0;
  int _nativeObservations = 0;
  int _nativeWorkerUs = 0;
  int _nativePacketBytes = 0;
  int _nativePrepareUs = 0;
  int _rssBefore = -1;
  int _maxRssBefore = -1;
  Stopwatch? _wall;
  final List<ui.FrameTiming> _timings = <ui.FrameTiming>[];

  File get _reportFile =>
      File('${Directory.systemTemp.path}/howl-native-host-ab.json');

  void observeDart(HowlSnapshot snapshot) {
    if (!nativeHostMeasurementEnabled || _finished) return;
    _markers(
      begin: _snapshotContainsAscii(snapshot, _measureBegin),
      end: _snapshotContainsAscii(snapshot, _measureEnd),
    );
  }

  void observeNative({
    required NativeHostMetadata metadata,
    required NativeHostObservation observation,
    required int prepareMicroseconds,
  }) {
    if (!nativeHostMeasurementEnabled || _finished) return;
    _markers(begin: metadata.measureBegin, end: metadata.measureEnd);
    if (!_active && !_stopPending) return;
    _nativeObservations += 1;
    _nativeWorkerUs += observation.workerMicroseconds;
    _nativePacketBytes += observation.bytes.length;
    _nativePrepareUs += prepareMicroseconds;
  }

  void onPaint() {
    if (_active || _stopPending) _paintCount += 1;
  }

  Future<void> afterPresentedFrame() async {
    if (!nativeHostMeasurementEnabled || !_stopPending || _finished) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _active = false;
    _stopPending = false;
    _finished = true;
    _wall?.stop();
    final report = <String, Object?>{
      'schema': 'howl.flutter-native-host-ab/v1',
      'mode': mode,
      'wall_us': _wall?.elapsedMicroseconds,
      'paint_count': _paintCount,
      'frame_timing_count': _timings.length,
      'build_us': _durationStats(
        _timings.map((timing) => timing.buildDuration.inMicroseconds),
      ),
      'raster_us': _durationStats(
        _timings.map((timing) => timing.rasterDuration.inMicroseconds),
      ),
      'rss_before': _rssBefore,
      'rss_after': _currentRss(),
      'max_rss_before': _maxRssBefore,
      'max_rss_after': _maxRss(),
      'native_observations': _nativeObservations,
      'native_worker_us_total': _nativeWorkerUs,
      'native_worker_us_per_observation': _nativeObservations == 0
          ? null
          : _nativeWorkerUs / _nativeObservations,
      'native_packet_bytes_total': _nativePacketBytes,
      'native_packet_bytes_per_observation': _nativeObservations == 0
          ? null
          : _nativePacketBytes / _nativeObservations,
      'native_prepare_us_total': _nativePrepareUs,
      'native_prepare_us_per_observation': _nativeObservations == 0
          ? null
          : _nativePrepareUs / _nativeObservations,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    _reportFile.writeAsStringSync(encoded);
    stdout.writeln('HOWL_NATIVE_HOST_AB ${jsonEncode(report)}');
  }

  void dispose() {
    if (!nativeHostMeasurementEnabled) return;
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _markers({required bool begin, required bool end}) {
    if (begin && !_started) {
      _started = true;
      _active = true;
      _paintCount = 0;
      _nativeObservations = 0;
      _nativeWorkerUs = 0;
      _nativePacketBytes = 0;
      _nativePrepareUs = 0;
      _timings.clear();
      _rssBefore = _currentRss();
      _maxRssBefore = _maxRss();
      _wall = Stopwatch()..start();
    }
    if (end && _active) {
      _stopPending = true;
    }
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (_active || _stopPending) _timings.addAll(timings);
  }
}

bool _snapshotContainsAscii(HowlSnapshot snapshot, String needle) {
  final target = needle.codeUnits;
  for (final row in snapshot.rows) {
    var matched = 0;
    for (final cell in row.cells) {
      for (final scalar in cell.scalars) {
        final byte = scalar <= 0x7f ? scalar : -1;
        if (byte == target[matched]) {
          matched += 1;
          if (matched == target.length) return true;
        } else {
          matched = byte == target.first ? 1 : 0;
        }
      }
    }
  }
  return false;
}

Map<String, Object?> _durationStats(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    return const <String, Object?>{
      'count': 0,
      'mean': null,
      'p50': null,
      'p90': null,
      'max': null,
    };
  }
  final sum = sorted.fold<int>(0, (total, value) => total + value);
  int percentile(double value) =>
      sorted[((sorted.length - 1) * value).round().clamp(0, sorted.length - 1)];
  return <String, Object?>{
    'count': sorted.length,
    'mean': sum / sorted.length,
    'p50': percentile(0.50),
    'p90': percentile(0.90),
    'max': sorted.last,
  };
}

int _currentRss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

int _maxRss() {
  try {
    return ProcessInfo.maxRss;
  } catch (_) {
    return -1;
  }
}

extension on File {
  void deleteSyncIfExists() {
    try {
      deleteSync();
    } on FileSystemException {
      // Absent stale measurement output is the normal launch state.
    }
  }
}
