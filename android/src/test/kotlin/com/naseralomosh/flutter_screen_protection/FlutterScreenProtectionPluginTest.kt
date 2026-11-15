package com.naseralomosh.flutter_screen_protection

import android.app.Activity
import android.os.Looper
import android.view.Window
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito.*
import kotlin.test.Test

class FlutterScreenProtectionPluginTest {
    @Test fun policyLifecycleAndCleanup() {
        mockStatic(Looper::class.java).use {
            val plugin = FlutterScreenProtectionPlugin()
            val engine = mock(FlutterPlugin.FlutterPluginBinding::class.java)
            `when`(engine.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
            plugin.onAttachedToEngine(engine)
            val activity = mock(Activity::class.java)
            val window = mock(Window::class.java)
            `when`(activity.window).thenReturn(window)
            val binding = mock(ActivityPluginBinding::class.java)
            `when`(binding.activity).thenReturn(activity)
            plugin.onAttachedToActivity(binding)
            verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            fun update(value: Any) = mock(MethodChannel.Result::class.java).also {
                plugin.onMethodCall(MethodCall("setProtection", mapOf("blocked" to value)), it)
            }
            verify(update(false)).success(null)
            verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            plugin.onDetachedFromActivityForConfigChanges()
            clearInvocations(window)
            update(true)
            verifyNoInteractions(window)
            plugin.onReattachedToActivityForConfigChanges(binding)
            verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            update(false); update(true); update(false)
            verify(window, times(2)).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            verify(update("false")).error(eq("invalid_argument"), anyString(), isNull())
            plugin.onDetachedFromEngine(engine)
            verify(window, times(3)).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            clearInvocations(window)
            verify(update(false)).error(eq("engine_detached"), anyString(), isNull())
            verifyNoInteractions(window)
        }
    }
    @Test fun backgroundCallsAreMarshalledInOrder() {
        val pending = mutableListOf<Runnable>()
        mockStatic(Looper::class.java).use { loopers ->
            val mainLooper = mock(Looper::class.java)
            loopers.`when`<Looper> { Looper.getMainLooper() }.thenReturn(mainLooper)
            mockConstruction(android.os.Handler::class.java) { handler, _ ->
                `when`(handler.post(any(Runnable::class.java))).thenAnswer {
                    pending.add(it.getArgument(0)); true
                }
            }.use {
                val plugin = FlutterScreenProtectionPlugin()
                val engine = mock(FlutterPlugin.FlutterPluginBinding::class.java)
                `when`(engine.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
                plugin.onAttachedToEngine(engine)
                val activity = mock(Activity::class.java)
                val window = mock(Window::class.java)
                `when`(activity.window).thenReturn(window)
                val binding = mock(ActivityPluginBinding::class.java)
                `when`(binding.activity).thenReturn(activity)
                plugin.onAttachedToActivity(binding)
                val result = mock(MethodChannel.Result::class.java)
                plugin.onMethodCall(MethodCall("setProtection", mapOf("blocked" to false)), result)
                plugin.onDetachedFromActivity()
                verifyNoInteractions(window, result)
                pending.toList().forEach { it.run() }
                val order = inOrder(window, result)
                order.verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                order.verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                order.verify(result).success(null)
            }
        }
    }
}
