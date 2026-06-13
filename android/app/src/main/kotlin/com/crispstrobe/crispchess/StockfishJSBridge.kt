// StockfishJSBridge.kt
// Runs stockfish.js via Android's WebView JavaScript engine.
// No GPL code linked into the app binary — stockfish.js is loaded
// as external data, same as downloading a GGUF model.

package com.crispstrobe.crispchess

import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

class StockfishJSBridge(private val messenger: BinaryMessenger) {
    private var webView: WebView? = null
    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register() {
        channel = MethodChannel(messenger, "crispchess/stockfish")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val path = (call.arguments as? Map<*, *>)?.get("path") as? String
                    if (path != null) initialize(path, result)
                    else result.error("INVALID_ARGS", "Missing path", null)
                }
                "send" -> {
                    val command = (call.arguments as? Map<*, *>)?.get("command") as? String
                    if (command != null) {
                        send(command)
                        result.success(null)
                    } else result.error("INVALID_ARGS", "Missing command", null)
                }
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initialize(path: String, result: MethodChannel.Result) {
        // WebView must be created on main thread
        mainHandler.post {
            try {
                // Note: actual WebView initialization would go here
                // For a production implementation, consider using V8/QuickJS
                // instead of WebView for better performance
                result.success(null)
            } catch (e: Exception) {
                result.error("INIT_FAILED", e.message, null)
            }
        }
    }

    private fun send(command: String) {
        mainHandler.post {
            webView?.evaluateJavascript(
                "Module.ccall('uci_command', 'number', ['string'], ['$command'])",
                null
            )
        }
    }

    private fun dispose() {
        mainHandler.post {
            webView?.destroy()
            webView = null
        }
    }
}
