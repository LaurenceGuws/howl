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
        adoptGapUs: index * 500,
        revisionGap: index,
        packetBytes: index * 1024,
        commands: index * 3,
      );
      perf.recordFlutterFrame(
        buildUs: index * 10,
        rasterUs: index * 20,
        totalUs: index * 100,
        vsyncOverheadUs: index * 5,
      );
    }

    final terminal = perf.terminalSummary();
    expect(terminal, contains('n=240'));
    expect(terminal, contains('adopt_gap='));
    expect(terminal, contains('rev_gap='));
    expect(terminal, contains('packet_kib='));
    expect(terminal, contains('commands='));
    expect(perf.flutterSummary(), contains('n=240'));
    expect(perf.flutterSummary(), contains('raster='));
  });

  test('reset clears prior canary samples', () {
    final perf = TerminalFramePerf();
    perf.recordTerminal(
      observeUs: 1000,
      prepareUs: 2000,
      displayWaitUs: 3000,
      adoptGapUs: 4000,
      packetBytes: 4096,
      commands: 20,
    );
    perf.recordFlutterFrame(
      buildUs: 1000,
      rasterUs: 2000,
      totalUs: 3000,
      vsyncOverheadUs: 400,
    );
    perf.reset();

    expect(perf.terminalSummary(), startsWith('n=0 '));
    expect(perf.flutterSummary(), startsWith('n=0 '));
  });
}
