import 'package:flutter/material.dart';

import 'ios_native_host_canary.dart';
import 'native_canvas_replay.dart';
import 'native_canvas_surface.dart';

Future<void> runIosNativeHostPressure() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _NativeHostPressureApp());
}

final class _NativeHostPressureApp extends StatelessWidget {
  const _NativeHostPressureApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: false),
    home: const _NativeHostPressureHome(),
  );
}

final class _NativeHostPressureHome extends StatefulWidget {
  const _NativeHostPressureHome();

  @override
  State<_NativeHostPressureHome> createState() =>
      _NativeHostPressureHomeState();
}

final class _NativeHostPressureHomeState
    extends State<_NativeHostPressureHome> {
  NativeIosCanvasResult? _native;
  CanvasReplayCorpus? _corpus;
  CanvasReplayFrameLease? _lease;
  Object? _failure;
  int _frameIndex = 0;
  int _lastUploadCount = 0;
  int _lastUploadBytes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    disposeCanvasReplayLease(_lease);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final native = await loadNativeIosCanvasHcr1();
      final corpus = CanvasReplayCorpus.parse(native.bytes);
      final prepared = await prepareCanvasReplayFrame(null, corpus.frame(0));
      if (!mounted) {
        disposeCanvasReplayLease(prepared.lease);
        return;
      }
      setState(() {
        _native = native;
        _corpus = corpus;
        _lease = prepared.lease;
        _frameIndex = 0;
        _lastUploadCount = prepared.uploadCount;
        _lastUploadBytes = prepared.uploadBytes;
      });
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _showNext() async {
    final corpus = _corpus;
    final old = _lease;
    if (corpus == null || old == null) return;
    final nextIndex = _frameIndex == 0 ? 1 : 0;
    final prepared = await prepareCanvasReplayFrame(
      nextIndex == 0 ? null : old,
      corpus.frame(nextIndex),
    );
    if (!mounted) {
      disposeCanvasReplayLease(prepared.lease);
      return;
    }
    setState(() {
      _lease = prepared.lease;
      _frameIndex = nextIndex;
      _lastUploadCount = prepared.uploadCount;
      _lastUploadBytes = prepared.uploadBytes;
    });
    await WidgetsBinding.instance.endOfFrame;
    for (final image in prepared.retired) {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Scaffold(
        backgroundColor: const Color(0xff090b0e),
        body: SafeArea(
          child: Center(child: Text('native host pressure failed\n$failure')),
        ),
      );
    }
    final native = _native;
    final corpus = _corpus;
    final lease = _lease;
    if (native == null || corpus == null || lease == null) {
      return const Scaffold(
        backgroundColor: Color(0xff090b0e),
        body: Center(child: Text('building native final Canvas…')),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xff090b0e),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: CustomPaint(
                painter: CanvasReplayPainter(
                  lease: lease,
                  logicalWidth: corpus.surfaceWidth.toDouble(),
                  logicalHeight: corpus.surfaceHeight.toDouble(),
                  onPaint: () {},
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xff101318),
                border: Border(top: BorderSide(color: Color(0xff2a2f38))),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'native host linked v${native.hostVersion} · canary v${native.canaryVersion}\n'
                      'frame ${_frameIndex + 1}/2 · ${native.bytes.length} B · '
                      'uploads $_lastUploadCount / $_lastUploadBytes B · no network',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _showNext,
                    child: Text(
                      _frameIndex == 0
                          ? 'Show sparse frame'
                          : 'Show first frame',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
