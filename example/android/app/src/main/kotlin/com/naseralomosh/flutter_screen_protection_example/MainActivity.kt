package com.naseralomosh.flutter_screen_protection_example

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

open class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
}
