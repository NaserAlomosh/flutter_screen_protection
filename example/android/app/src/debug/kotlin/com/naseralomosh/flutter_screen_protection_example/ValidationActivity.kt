package com.naseralomosh.flutter_screen_protection_example

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.SystemClock
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import com.naseralomosh.flutter_screen_protection.FlutterScreenProtectionPlugin
import io.flutter.embedding.engine.FlutterEngine

/** Debug-only lifecycle test host. Retains one engine across recreate(). */
class ValidationActivity : MainActivity() {
    companion object { private var testEngine: FlutterEngine? = null }
    private var delayMillis = 0L
    private var readyAt = 0L
    private val handler = Handler(Looper.getMainLooper())
    private var failProtection = false
    override fun provideFlutterEngine(context: Context): FlutterEngine? = testEngine
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        testEngine = flutterEngine
        // Fault injection belongs only to this debug validation Activity.
        val plugin = flutterEngine.plugins.get(FlutterScreenProtectionPlugin::class.java)
            as FlutterScreenProtectionPlugin
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flutter_screen_protection")
            .setMethodCallHandler { call, result ->
                val blocked = (call.arguments as? Map<*, *>)?.get("blocked") == true
                val action = Runnable {
                    if (blocked && failProtection) result.error("injected_failure", "Validation-only failure", null)
                    else plugin.onMethodCall(call, result)
                }
                // Preserve production channel ordering even under delayed replies.
                val now = SystemClock.uptimeMillis()
                readyAt = maxOf(readyAt, now + if (blocked) delayMillis else 0L)
                if (readyAt > now) handler.postAtTime(action, readyAt)
                else action.run()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fsp.validation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        delayMillis = (call.argument<Number>("delayMillis")?.toLong() ?: 0L).coerceIn(0, 10000)
                        failProtection = call.argument<Boolean>("fail") ?: false
                        result.success(null)
                    }
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "back" -> MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flutter/backgesture")
                        .invokeMethod(call.argument<String>("event")!!, call.argument<Any>("payload"), result)
                    else -> result.notImplemented()
                }
            }
    }
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "fsp.RECREATE") recreate()
    }
}
