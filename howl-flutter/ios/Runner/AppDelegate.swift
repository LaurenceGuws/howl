import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var repeatFeedback: UISelectionFeedbackGenerator?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let repeatHapticChannel = FlutterMethodChannel(
      name: "howl.flutter/ios_repeat_haptic",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    repeatHapticChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "tick" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let feedback: UISelectionFeedbackGenerator
      if let existing = self?.repeatFeedback {
        feedback = existing
      } else {
        feedback = UISelectionFeedbackGenerator()
        self?.repeatFeedback = feedback
        feedback.prepare()
      }
      feedback.selectionChanged()
      feedback.prepare()
      result(nil)
    }
    let networkChannel = FlutterMethodChannel(
      name: "howl.flutter/ios_network_probe",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    networkChannel.setMethodCallHandler { call, result in
      guard call.method == "probeTcp" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let hostText = arguments["host"] as? String,
        let portValue = arguments["port"] as? Int,
        (1...65535).contains(portValue),
        let port = NWEndpoint.Port(rawValue: UInt16(portValue))
      else {
        result(
          FlutterError(
            code: "invalid_probe_endpoint",
            message: "The iOS network probe requires a numeric host and TCP port",
            details: nil
          )
        )
        return
      }

      let connection = NWConnection(
        host: NWEndpoint.Host(hostText),
        port: port,
        using: .tcp
      )
      let queue = DispatchQueue(label: "howl.ios-network-probe")
      var finished = false

      func reasonName(_ reason: NWPath.UnsatisfiedReason?) -> String {
        guard let reason else { return "none" }
        switch reason {
        case .notAvailable: return "notAvailable"
        case .cellularDenied: return "cellularDenied"
        case .wifiDenied: return "wifiDenied"
        case .localNetworkDenied: return "localNetworkDenied"
        @unknown default: return "unknown"
        }
      }

      func finish(_ state: String, error: NWError? = nil) {
        guard !finished else { return }
        finished = true
        let payload: [String: Any] = [
          "state": state,
          "reason": reasonName(connection.currentPath?.unsatisfiedReason),
          "error": error.map { String(describing: $0) } ?? "none",
        ]
        connection.cancel()
        DispatchQueue.main.async { result(payload) }
      }

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          finish("ready")
        case .waiting(let error):
          finish("waiting", error: error)
        case .failed(let error):
          finish("failed", error: error)
        case .cancelled:
          finish("cancelled")
        case .setup, .preparing:
          break
        @unknown default:
          finish("unknown")
        }
      }
      connection.start(queue: queue)
      queue.asyncAfter(deadline: .now() + .seconds(3)) {
        finish("timeout")
      }
    }
  }
}
