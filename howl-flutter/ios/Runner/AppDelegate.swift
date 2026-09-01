import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let hostChannel = FlutterMethodChannel(
      name: "howl.flutter/ios_host",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    hostChannel.setMethodCallHandler { call, result in
      guard call.method == "fontPaths" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let primary = Bundle.main.path(
          forResource: "IosevkaTermNerdFont-Regular",
          ofType: "ttf"
        ),
        let fallback = Bundle.main.path(forResource: "NotoSans-Regular", ofType: "ttf")
      else {
        result(
          FlutterError(
            code: "native_fonts_missing",
            message: "Howl iOS native font resources are missing",
            details: nil
          )
        )
        return
      }
      result(["primary": primary, "fallback": fallback])
    }
  }
}
