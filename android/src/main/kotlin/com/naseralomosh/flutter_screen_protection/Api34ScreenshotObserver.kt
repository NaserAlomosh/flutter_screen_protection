package com.naseralomosh.flutter_screen_protection

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi

/** Keep references to API 34 types out of the plugin class loaded on older Android. */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal object Api34ScreenshotObserver {
    fun register(activity: Activity, onScreenshot: () -> Unit): () -> Unit {
        if (activity.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException()
        }

        var listener: (() -> Unit)? = onScreenshot
        val callback = Activity.ScreenCaptureCallback { listener?.invoke() }
        val unregister = {
            // Even if the platform rejects removal, the callback cannot retain the plugin.
            listener = null
            try {
                activity.unregisterScreenCaptureCallback(callback)
            } catch (_: RuntimeException) {
                // Android may already have removed the Activity's observer.
            }
        }
        try {
            activity.registerScreenCaptureCallback(activity.mainExecutor, callback)
        } catch (failure: RuntimeException) {
            // Android can add the callback locally before registration with the system fails.
            unregister()
            throw failure
        }
        return unregister
    }
}
