import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var secureTextField: UITextField?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupSecureChannel()
    DispatchQueue.main.async { [weak self] in
      self?.setScreenshotProtection(enabled: true)
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setupSecureChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "com.washatv/secure", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setSecure" {
        let secure = (call.arguments as? [String: Any])?["secure"] as? Bool ?? true
        self?.setScreenshotProtection(enabled: secure)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setScreenshotProtection(enabled: Bool) {
    guard let rootView = window?.rootViewController?.view else { return }
    if enabled {
      if secureTextField != nil { return }
      let tf = UITextField()
      tf.isSecureTextEntry = true
      tf.isUserInteractionEnabled = false
      tf.translatesAutoresizingMaskIntoConstraints = false
      rootView.addSubview(tf)
      NSLayoutConstraint.activate([
        tf.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
        tf.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
        tf.widthAnchor.constraint(equalTo: rootView.widthAnchor),
        tf.heightAnchor.constraint(equalTo: rootView.heightAnchor),
      ])
      rootView.layer.superlayer?.addSublayer(tf.layer)
      tf.layer.sublayers?.last?.addSublayer(rootView.layer)
      secureTextField = tf
    } else {
      secureTextField?.removeFromSuperview()
      secureTextField = nil
      if let rootView = window?.rootViewController?.view {
        rootView.layer.superlayer?.addSublayer(rootView.layer)
      }
    }
  }
}
