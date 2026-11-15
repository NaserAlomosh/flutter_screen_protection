package com.naseralomosh.flutter_screen_protection_example

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine

/** Debug-only lifecycle test host. Retains one engine across recreate(). */
class ValidationActivity : MainActivity() {
    companion object { private var testEngine: FlutterEngine? = null }
    override fun provideFlutterEngine(context: Context): FlutterEngine? = testEngine
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        testEngine = flutterEngine
    }
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "fsp.RECREATE") recreate()
    }
}
