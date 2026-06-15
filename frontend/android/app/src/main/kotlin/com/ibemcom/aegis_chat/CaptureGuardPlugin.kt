package com.ibemcom.aegis_chat

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class CaptureGuardPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        private const val METHOD_CHANNEL_NAME = "com.ibemcom.aegis_chat/capture_guard"
        private const val EVENT_CHANNEL_NAME = "com.ibemcom.aegis_chat/capture_events"

        fun register(activity: Activity, flutterEngine: FlutterEngine) {
            val plugin = CaptureGuardPlugin(activity)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME)
                .setMethodCallHandler(plugin)
            EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        // Event sink can be stored if we emit Android capture events later
                    }
                    override fun onCancel(arguments: Any?) {}
                })
        }
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableSecureMode" -> {
                activity.runOnUiThread {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
            }
            "disableSecureMode" -> {
                activity.runOnUiThread {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
            }
            "isBeingCaptured" -> {
                // Android blocks capture via FLAG_SECURE, returning false as requested
                result.success(false)
            }
            "isSecureModeEnabled" -> {
                activity.runOnUiThread {
                    val flags = activity.window.attributes.flags
                    val isSecure = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(isSecure)
                }
            }
            else -> result.notImplemented()
        }
    }
}
