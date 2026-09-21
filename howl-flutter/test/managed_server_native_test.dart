import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/native_host.dart';
import 'package:howl_flutter/server_manager.dart';
import 'package:howl_flutter/terminal_presentation.dart';

void main() {
  final howl = Platform.environment['HOWL_TEST_HOWL'];
  final enabled = Platform.environment['HOWL_NATIVE_MANAGER_TEST'] == '1';

  test(
    'live managed server crosses Dart FFI into one retained Session',
    () async {
      final runtime = await Directory.systemTemp.createTemp(
        'howl-flutter-manager-',
      );
      Process? server;
      NativeServerManager? manager;
      NativeHostObserver? observer;
      NativeHostControl? control;
      String? managerEndpoint;
      try {
        server = await Process.start(howl!, <String>[
          'server',
          'run',
          runtime.path,
          '--shell',
          '/bin/sh',
        ]);
        final startupLine = await server.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 5));
        final startup = jsonDecode(startupLine) as Map<String, Object?>;
        expect(startup['schema'], 'howl.server/v2');
        managerEndpoint = startup['manager']! as String;

        manager = await NativeServerManager.create(endpoint: managerEndpoint);
        final empty = await manager.roster
            .observe(afterRevision: 0)
            .timeout(const Duration(seconds: 5));
        expect(empty.sessions, isEmpty);

        final created = await manager.control.createSession('flutter');
        expect(created.sessionId, greaterThan(0));
        final roster = await manager.roster
            .observe(afterRevision: empty.rosterRevision)
            .timeout(const Duration(seconds: 5));
        expect(roster.byId(created.sessionId)?.name, 'flutter');

        final presentation = TerminalZoomPreset.normal.presentation;
        control = await NativeHostControl.createManaged(
          serverEndpoint: managerEndpoint,
          sessionId: created.sessionId,
        );
        final fontMatch = await Process.run('fc-match', <String>[
          '-f',
          '%{file}',
          'monospace',
        ]);
        expect(fontMatch.exitCode, 0);
        final fontPath = fontMatch.stdout.toString().trim();
        expect(fontPath, isNotEmpty);
        observer = await NativeHostObserver.createManaged(
          serverEndpoint: managerEndpoint,
          sessionId: created.sessionId,
          primaryFontPath: fontPath,
          fallbackFontPath: fontPath,
          secondaryFallbackFontPath: fontPath,
          presentation: presentation,
        );
        await control.committedText('echo FLUTTER_MANAGER_CANARY\n');

        var revision = 0;
        var sawCanary = false;
        for (var attempt = 0; attempt < 12 && !sawCanary; attempt += 1) {
          final observation = await observer
              .observe(
                afterRevision: revision,
                historyOffset: 0,
                residency: Uint8List(0),
              )
              .timeout(const Duration(seconds: 5));
          expect(observation, isA<NativeHostFrameObservation>());
          final frame = parseNativeHostPacket(
            (observation as NativeHostFrameObservation).bytes,
            presentation,
          );
          revision = frame.metadata.revision;
          sawCanary = frame.semanticText.contains('FLUTTER_MANAGER_CANARY');
        }
        expect(sawCanary, isTrue);

        await observer.close();
        observer = null;
        await control.close();
        control = null;
        await manager.control.closeSession(created.sessionId);
        final closed = await manager.roster
            .observe(afterRevision: roster.rosterRevision)
            .timeout(const Duration(seconds: 5));
        expect(closed.byId(created.sessionId), isNull);
      } finally {
        await observer?.close();
        await control?.close();
        await manager?.close();
        if (managerEndpoint != null && howl != null) {
          await Process.run(howl, <String>[
            'server',
            'shutdown',
            managerEndpoint,
          ]).timeout(const Duration(seconds: 5));
        }
        if (server != null) {
          try {
            await server.exitCode.timeout(const Duration(seconds: 2));
          } on TimeoutException {
            server.kill(ProcessSignal.sigkill);
            await server.exitCode;
          }
        }
        await runtime.delete(recursive: true);
      }
    },
    skip: enabled && howl != null ? false : 'set HOWL_NATIVE_MANAGER_TEST=1',
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
