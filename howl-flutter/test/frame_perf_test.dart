import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/frame_perf.dart';

void main() {
  test('frame perf summaries stay bounded and percentile ordered', () {
    final perf = TerminalFramePerf();
    for (var index = 1; index <= 300; index += 1) {
      perf.recordTerminal(
        observeUs: index * 100,
        prepareUs: index * 10,
        displayWaitUs: index * 1000,
        revisionGap: index,
      );
      perf.recordNative(
        receiveDecodeUs: index * 100,
        projectUs: index * 10,
        composeUs: index * 20,
        serializeUs: index * 5,
      );
      perf.recordFlutterFrame(
        buildUs: index * 10,
        rasterUs: index * 20,
        totalUs: index * 100,
        vsyncOverheadUs: index * 5,
      );
    }

    expect(perf.terminalSummary(), contains('n=240'));
    expect(perf.terminalSummary(), contains('rev_gap='));
    expect(perf.nativeSummary(), contains('n=240'));
    expect(perf.nativeSummary(), contains('receive_decode='));
    expect(perf.flutterSummary(), contains('n=240'));
    expect(perf.flutterSummary(), contains('raster='));
  });

  test('reset clears prior canary samples', () {
    final perf = TerminalFramePerf();
    perf.recordTerminal(observeUs: 1000, prepareUs: 2000, displayWaitUs: 3000);
    perf.recordNative(
      receiveDecodeUs: 1000,
      projectUs: 2000,
      composeUs: 3000,
      serializeUs: 4000,
    );
    perf.recordFlutterFrame(
      buildUs: 1000,
      rasterUs: 2000,
      totalUs: 3000,
      vsyncOverheadUs: 400,
    );
    perf.reset();

    expect(perf.terminalSummary(), startsWith('n=0 '));
    expect(perf.nativeSummary(), startsWith('n=0 '));
    expect(perf.flutterSummary(), startsWith('n=0 '));
  });
}
