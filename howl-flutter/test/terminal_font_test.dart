import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howl_flutter/terminal_font.dart';

final class _RecordingFontLoader extends FontLoader {
  _RecordingFontLoader(super.family);

  Uint8List? loadedBytes;
  String? loadedFamily;

  @override
  Future<void> loadFont(Uint8List list, String family) async {
    loadedBytes = Uint8List.fromList(list);
    loadedFamily = family;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android private font registers under the shared presentation family',
    () async {
      const channel = MethodChannel('howl.flutter/test_android_host');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'filesPath');
            return '/private/howl';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final source = Uint8List.fromList(<int>[1, 2, 3, 4]);
      late _RecordingFontLoader loader;
      final loaded = await loadPrivateTerminalFont(
        platformOverride: TargetPlatform.android,
        channel: channel,
        reader: (path) async {
          expect(path, '/private/howl/$androidPrivateFontFileName');
          return source;
        },
        loaderFactory: (family) => loader = _RecordingFontLoader(family),
      );

      expect(loaded, isTrue);
      expect(loader.family, terminalFontFamily);
      expect(loader.loadedFamily, terminalFontFamily);
      expect(loader.loadedBytes, source);
    },
  );

  test(
    'missing Android private font preserves fallback instead of failing',
    () async {
      const channel = MethodChannel('howl.flutter/test_android_host_missing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => '/private/howl');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final loaded = await loadPrivateTerminalFont(
        platformOverride: TargetPlatform.android,
        channel: channel,
        reader: (_) async => throw const FileSystemException('absent'),
      );

      expect(loaded, isFalse);
    },
  );

  test(
    'non-Android presentation never asks the Android host for a font path',
    () async {
      const channel = MethodChannel('howl.flutter/test_android_host_unused');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls += 1;
            return '/unexpected';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final loaded = await loadPrivateTerminalFont(
        platformOverride: TargetPlatform.linux,
        channel: channel,
      );

      expect(loaded, isFalse);
      expect(calls, 0);
    },
  );
}
