package com.naseralomosh.flutter_screen_protection

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Owns FLAG_SECURE for one engine and its attached Activity. */
class FlutterScreenProtectionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var blocked = true
    private var attached = false
    private val main by lazy { Handler(Looper.getMainLooper()) }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post(action)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = true
        blocked = true
        channel = MethodChannel(binding.binaryMessenger, "flutter_screen_protection")
        channel!!.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setProtection") { result.notImplemented(); return }
        val value = (call.arguments as? Map<*, *>)?.get("blocked")
        if (value !is Boolean) { result.error("invalid_argument", "blocked must be a Boolean", null); return }
        onMain {
            if (!attached) {
                result.error("engine_detached", "Flutter engine is detached", null)
            } else {
                blocked = value
                try { applyPolicy(); result.success(null) }
                catch (error: RuntimeException) {
                    blocked = true
                    result.error("window_update_failed", error.message, null)
                }
            }
        }
    }

    private fun applyPolicy() {
        val window = activity?.window ?: return
        if (blocked) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        onMain { activity = binding.activity; applyPolicy() }
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() { onMain { activity = null } }
    override fun onDetachedFromActivity() { onMain { activity = null } }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        onMain {
            attached = false
            blocked = true
            applyPolicy() // Do not expose the last Flutter frame on engine disposal.
            activity = null
        }
    }
}
