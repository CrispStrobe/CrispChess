// StockfishJSBridge.swift
// Runs stockfish.js (WASM compiled to JS) via JavaScriptCore on iOS.
// The app binary contains NO GPL code — stockfish.js is loaded as
// external data, like a GGUF model in an LLM app.

import Foundation
import JavaScriptCore
import Flutter

class StockfishJSBridge: NSObject {
    private var jsContext: JSContext?
    private var channel: FlutterMethodChannel?
    private var outputCallback: ((String) -> Void)?

    func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "crispchess/stockfish",
            binaryMessenger: registrar.messenger()
        )
        channel?.setMethodCallHandler(handle)
    }

    func register(with controller: FlutterViewController) {
        channel = FlutterMethodChannel(
            name: "crispchess/stockfish",
            binaryMessenger: controller.engine.binaryMessenger
        )
        channel?.setMethodCallHandler(handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
                return
            }
            initialize(path: path, result: result)

        case "send":
            guard let args = call.arguments as? [String: Any],
                  let command = args["command"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing command", details: nil))
                return
            }
            send(command: command)
            result(nil)

        case "dispose":
            dispose()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(path: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let jsSource = try String(contentsOfFile: path, encoding: .utf8)

                self.jsContext = JSContext()
                self.jsContext?.exceptionHandler = { _, exception in
                    print("[StockfishJS] Exception: \(exception?.toString() ?? "unknown")")
                }

                // Set up postMessage to capture Stockfish output
                let postMessage: @convention(block) (String) -> Void = { [weak self] message in
                    DispatchQueue.main.async {
                        self?.channel?.invokeMethod("onOutput", arguments: message)
                    }
                }
                self.jsContext?.setObject(postMessage,
                    forKeyedSubscript: "postMessage" as NSString)

                // Provide a minimal Module object that Stockfish expects
                self.jsContext?.evaluateScript("""
                    var Module = {
                        print: function(text) { postMessage(text); },
                        printErr: function(text) { /* ignore stderr */ }
                    };
                """)

                // Load and evaluate stockfish.js
                self.jsContext?.evaluateScript(jsSource)

                DispatchQueue.main.async {
                    result(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INIT_FAILED",
                        message: "Failed to load stockfish.js: \(error)",
                        details: nil
                    ))
                }
            }
        }
    }

    private func send(command: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Stockfish.js expects input via a global function
            self?.jsContext?.evaluateScript("""
                if (typeof Module !== 'undefined' && Module.ccall) {
                    Module.ccall('uci_command', 'number', ['string'], ['\(command)']);
                } else {
                    postMessage('info string Engine not ready');
                }
            """)
        }
    }

    private func dispose() {
        jsContext = nil
    }
}
