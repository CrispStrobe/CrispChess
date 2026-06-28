// StockfishJSBridge.swift
//
// Runs stockfish.js (GPL-3.0) on iOS inside a WKWebView — i.e. Apple's own
// WebKit JS engine. The app binary contains NO GPL code: stockfish.js is
// downloaded at runtime (CDN) by the Dart side and served to the web view
// through an in-memory custom URL scheme, exactly like a browser fetching and
// running a GPL web app. This is the App Store-sanctioned execution path
// (Guideline 2.5.2 / DPLA §3.3.2: code run by WebKit/JavaScriptCore that does
// not change the app's primary purpose).
//
// A WKWebView (rather than a bare JSContext) is used deliberately: it provides
// the full browser environment stockfish.js expects (Web Worker, setTimeout,
// XHR) and gets the JIT entitlement, and Workers run same-origin under the
// custom scheme so the engine loads cleanly.

import Foundation
import WebKit
import Flutter

class StockfishJSBridge: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    private var webView: WKWebView?
    private var channel: FlutterMethodChannel?
    private weak var host: FlutterViewController?
    private var jsSource: String = ""
    private var pendingInit: FlutterResult?

    /// Wire up the `crispchess/stockfish` method channel on the Flutter engine.
    func register(with controller: FlutterViewController) {
        host = controller
        let ch = FlutterMethodChannel(
            name: "crispchess/stockfish",
            binaryMessenger: controller.binaryMessenger
        )
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        channel = ch
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                return
            }
            DispatchQueue.main.async { self.initialize(path: path, result: result) }

        case "send":
            guard let args = call.arguments as? [String: Any],
                  let command = args["command"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing command", details: nil))
                return
            }
            DispatchQueue.main.async {
                self.send(command: command)
                result(nil)
            }

        case "dispose":
            DispatchQueue.main.async {
                self.dispose()
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Lifecycle

    private func initialize(path: String, result: @escaping FlutterResult) {
        do {
            jsSource = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            result(FlutterError(code: "INIT_FAILED",
                                message: "Failed to read stockfish.js: \(error)",
                                details: nil))
            return
        }

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "sf")
        config.userContentController = ucc
        // Serve the harness + engine from an in-memory same-origin scheme so the
        // Web Worker (stockfish.js) is allowed to load.
        config.setURLSchemeHandler(self, forURLScheme: "sfengine")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isHidden = true
        // Keep it in the view hierarchy so JS/Workers run reliably.
        host?.view.addSubview(wv)
        webView = wv

        pendingInit = result   // completed when the harness posts "__ready__"
        wv.load(URLRequest(url: URL(string: "sfengine://app/harness.html")!))
    }

    private func send(command: String) {
        guard let wv = webView else { return }
        // JSON-encode the command so arbitrary UCI strings are escaped safely.
        let encoded = (try? JSONSerialization.data(withJSONObject: [command])).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[\"\"]"
        wv.evaluateJavaScript("window.sfSend(\(encoded)[0]);", completionHandler: nil)
    }

    private func dispose() {
        if let wv = webView {
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "sf")
            wv.removeFromSuperview()
        }
        webView = nil
        jsSource = ""
    }

    // MARK: - WKScriptMessageHandler (engine output → Flutter)

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        if line == "__ready__" {
            pendingInit?(nil)
            pendingInit = nil
            return
        }
        channel?.invokeMethod("onOutput", arguments: line)
    }

    // MARK: - WKURLSchemeHandler (serve harness + engine from memory)

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "sfengine", code: -1))
            return
        }
        let data: Data
        let mime: String
        if url.absoluteString.hasSuffix("stockfish.js") {
            data = jsSource.data(using: .utf8) ?? Data()
            mime = "text/javascript"
        } else {
            data = StockfishJSBridge.harnessHTML.data(using: .utf8) ?? Data()
            mime = "text/html"
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    // The page spawns stockfish.js as a Web Worker (its native execution mode)
    // and relays UCI I/O between the worker and native via the message handler.
    private static let harnessHTML = """
    <!DOCTYPE html><html><head><meta charset="utf-8"></head><body><script>
    (function () {
      function out(s) { window.webkit.messageHandlers.sf.postMessage(String(s)); }
      try {
        var w = new Worker('stockfish.js');
        w.onmessage = function (e) { out(e.data); };
        w.onerror = function (e) { out('info string worker_error ' + (e.message || '')); };
        window.sfSend = function (cmd) { w.postMessage(cmd); };
        out('__ready__');
      } catch (err) {
        out('info string harness_error ' + err);
      }
    })();
    </script></body></html>
    """
}
