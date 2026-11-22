import UIKit
import Flutter

// UIScene lifecycle (required for apps built with the iOS 27 SDK: UIKit
// traps at launch otherwise). Info.plist's UIApplicationSceneManifest hands
// the window to FlutterSceneDelegate, so `window` is nil here and the
// FlutterViewController must not be touched in didFinishLaunching. Plugins
// and our own channel are wired when the implicit engine is ready instead.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Retains the WebKit-backed Stockfish bridge for the app's lifetime.
  private var stockfishBridge: StockfishJSBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Wire the crispchess/stockfish method channel (iOS runs Stockfish as
    // downloaded JS inside WebKit — no GPL code in the app binary).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StockfishJSBridge") {
      let bridge = StockfishJSBridge()
      bridge.register(with: registrar)
      stockfishBridge = bridge
    }
  }
}
