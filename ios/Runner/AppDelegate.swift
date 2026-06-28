import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Retains the WebKit-backed Stockfish bridge for the app's lifetime.
  private var stockfishBridge: StockfishJSBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Wire the crispchess/stockfish method channel (iOS runs Stockfish as
    // downloaded JS inside WebKit — no GPL code in the app binary).
    if let controller = window?.rootViewController as? FlutterViewController {
      let bridge = StockfishJSBridge()
      bridge.register(with: controller)
      stockfishBridge = bridge
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
