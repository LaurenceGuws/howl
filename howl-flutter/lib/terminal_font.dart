import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String terminalFontFamily = 'IosevkaTerm Nerd Font';
const List<String> terminalFontFamilyFallback = <String>['monospace'];
const String androidPrivateFontFileName = 'IosevkaTermNerdFont-Regular.ttf';

const MethodChannel _androidHost = MethodChannel('howl.flutter/android_host');

typedef TerminalFontLoaderFactory = FontLoader Function(String family);
typedef TerminalFontReader = Future<Uint8List> Function(String path);

/// Loads the optional Android-private terminal face before the first frame.
///
/// Font selection remains presentation policy: absence, an unavailable Android
/// host channel, or an unreadable private font all preserve Flutter's normal
/// monospace fallback rather than making terminal attachment fail.
Future<bool> loadPrivateTerminalFont({
  TargetPlatform? platformOverride,
  MethodChannel channel = _androidHost,
  TerminalFontLoaderFactory? loaderFactory,
  TerminalFontReader? reader,
}) async {
  final platform = platformOverride ?? defaultTargetPlatform;
  if (platform != TargetPlatform.android) return false;

  final String? filesPath;
  try {
    filesPath = await channel.invokeMethod<String>('filesPath');
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
  if (filesPath == null || filesPath.isEmpty) return false;

  final loadBytes = reader ?? (path) => File(path).readAsBytes();
  final Uint8List bytes;
  try {
    bytes = await loadBytes('$filesPath/$androidPrivateFontFileName');
  } on FileSystemException {
    return false;
  }

  final loader = (loaderFactory ?? FontLoader.new)(terminalFontFamily);
  loader.addFont(
    Future<ByteData>.value(
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );
  try {
    await loader.load();
  } on Exception {
    return false;
  }
  return true;
}
