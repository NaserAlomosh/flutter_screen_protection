package com.naseralomosh.flutter_screen_protection

import android.app.Activity
import android.os.Build
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class FlutterScreenProtectionPlugin internal constructor(
    private val sdkInt: () -> Int,
    private val timestampMs: () -> Long,
) : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    constructor() : this({ Build.VERSION.SDK_INT }, System::currentTimeMillis)

    private companion object {
        const val CHANNEL = "flutter_screen_protection"
        const val EVENTS = "$CHANNEL/events"
        const val VERSION = 1
        const val SCREENSHOT_API = Build.VERSION_CODES.UPSIDE_DOWN_CAKE
    }

    private var messenger: BinaryMessenger? = null
    private var commands: MethodChannel? = null
    private var eventControl: MethodChannel? = null
    private var host: Host? = null
    private var listening = false
    private var generation = 0L
    private var session: Long? = null
    private var sequence = 0L
    private var unregister: (() -> Unit)? = null
    private var registrationFailure: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val engineMessenger = binding.binaryMessenger
        messenger = engineMessenger
        commands = MethodChannel(engineMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        // Handle the EventChannel control methods directly to make cancel idempotent,
        // including after a failed listen or native transport teardown.
        eventControl = MethodChannel(engineMessenger, EVENTS).also {
            it.setMethodCallHandler(::onEventControl)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getCaptureCapabilities" -> {
                if (hasVersion(call)) {
                    result.success(mapOf("version" to VERSION, "capabilities" to capabilities()))
                } else {
                    result.error("protocolFailure", null, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun onEventControl(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> {
                if (!hasVersion(call)) {
                    result.error("protocolFailure", null, null)
                    return
                }
                stopListening()
                result.success(null)
                listening = true
                startSession()
            }
            // Flutter also sends a null cancel on hot restart.
            "cancel" -> {
                if (call.arguments != null && !hasVersion(call)) {
                    result.error("protocolFailure", null, null)
                    return
                }
                stopListening()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @ChecksSdkIntAtLeast(api = SCREENSHOT_API)
    private fun supportsScreenshots(): Boolean = sdkInt() >= SCREENSHOT_API

    private fun hasVersion(call: MethodCall): Boolean =
        (call.arguments as? Map<*, *>)?.get("version") == VERSION

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        if (!supportsScreenshots()) return
        val activity = binding.activity
        if (host?.activity === activity) return
        detachHost()
        if (activity.isDestroyed) return
        val lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding) ?: return
        val attached = Host(activity, lifecycle)
        host = attached
        lifecycle.addObserver(attached)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = detachHost()

    override fun onDetachedFromActivity() = detachHost()

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachHost()
        if (listening) {
            stopListening()
            send(null)
        }
        eventControl?.setMethodCallHandler(null)
        commands?.setMethodCallHandler(null)
        eventControl = null
        commands = null
        messenger = null
    }

    private fun detachHost() {
        val previous = host ?: return
        host = null
        finishSession("detached")
        previous.lifecycle.removeObserver(previous)
    }

    private inner class Host(val activity: Activity, val lifecycle: Lifecycle) :
        DefaultLifecycleObserver {
        var started = false
            private set

        override fun onStart(owner: LifecycleOwner) {
            if (host !== this || started) return
            started = true
            if (listening) startSession()
        }

        override fun onStop(owner: LifecycleOwner) {
            if (host !== this || !started) return
            started = false
            finishSession("backgrounded")
        }

        override fun onDestroy(owner: LifecycleOwner) {
            if (host === this) detachHost()
        }
    }

    private fun startSession() {
        val next = ++generation
        val attached = host
        if (supportsScreenshots() && attached?.started == true) {
            try {
                unregister = Api34ScreenshotObserver.register(attached.activity) {
                    if (session == next) emit(next, "screenshotTaken", "activity")
                }
            } catch (_: SecurityException) {
                registrationFailure = "permissionMissing"
            } catch (_: RuntimeException) {
                registrationFailure = "registrationFailed"
            }
        }
        val unknownReason = when {
            !supportsScreenshots() || unregister != null -> null
            else -> screenshotUnavailableReason()
        }
        session = next
        sequence = 0
        emit(
            next, "snapshot", "unknown",
            mapOf(
                "status" to if (unknownReason == null) "unsupported" else "unknown",
                "reason" to (unknownReason ?: "unsupportedOs"),
                "capabilities" to capabilities(),
            ),
        )
    }

    private fun finishSession(reason: String) {
        val previous = session
        session = null
        if (previous != null) emit(previous, "invalidated", "unknown", mapOf("reason" to reason))
        removeObservation()
    }

    private fun stopListening() {
        listening = false
        session = null
        removeObservation()
    }

    private fun removeObservation() {
        val cleanup = unregister
        unregister = null
        registrationFailure = null
        cleanup?.invoke()
    }

    private fun capabilities(): Map<String, Any> {
        val screenshots = when {
            !supportsScreenshots() -> unavailable("unsupportedOs")
            unregister != null -> mapOf("support" to "supported", "scope" to "activity")
            registrationFailure == "permissionMissing" -> unavailable("permissionMissing")
            else -> unavailable(screenshotUnavailableReason(), temporary = true)
        }
        return mapOf(
            "platform" to "android",
            "screenshots" to screenshots,
            "continuousCapture" to unavailable("unsupportedOs"),
        )
    }

    private fun screenshotUnavailableReason(): String = registrationFailure ?: when (host?.started) {
        null -> "detached"
        false -> "backgrounded"
        true -> "initializing"
    }

    private fun unavailable(reason: String, temporary: Boolean = false) = mapOf(
        "support" to if (temporary) "temporarilyUnavailable" else "unavailable",
        "scope" to "unknown",
        "reason" to reason,
    )

    private fun emit(
        session: Long,
        kind: String,
        scope: String,
        fields: Map<String, Any> = emptyMap(),
    ) {
        val packet = mapOf(
            "version" to VERSION,
            "session" to session,
            "sequence" to sequence++,
            "kind" to kind,
            "timestampMs" to timestampMs(),
            "scope" to scope,
        ) + fields
        if (!send(packet)) {
            stopListening()
            send(null)
        }
    }

    private fun send(packet: Map<String, Any>?): Boolean {
        val engineMessenger = messenger ?: return false
        return try {
            engineMessenger.send(EVENTS, packet?.let(StandardMethodCodec.INSTANCE::encodeSuccessEnvelope))
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}
