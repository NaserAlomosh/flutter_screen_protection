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
import java.util.WeakHashMap

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

        // A plugin can be replaced while its engine and Dart isolate keep running.
        // The main thread owns this table, and the keys do not keep engines alive.
        val generations = WeakHashMap<BinaryMessenger, Long>()
    }

    private var engineAttachment: Any? = null
    private var messenger: BinaryMessenger? = null
    private var commands: MethodChannel? = null
    private var eventControl: MethodChannel? = null
    private var host: Host? = null
    private var subscription: Any? = null
    private var session: Session? = null
    private var observationChangeDepth = 0
    private var startRequested = false

    private class Session(val generation: Long) {
        var sequence = 0L
        var unregister: (() -> Unit)? = null
        var registrationFailure: String? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val attachment = Any()
        engineAttachment = attachment
        val engineMessenger = binding.binaryMessenger
        messenger = engineMessenger
        commands = MethodChannel(engineMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                if (engineAttachment === attachment) onMethodCall(call, result)
                else result.notImplemented()
            }
        }
        // The v1 EventChannel control handshake makes cancel idempotent.
        eventControl = MethodChannel(engineMessenger, EVENTS).also {
            it.setMethodCallHandler { call, result ->
                if (engineAttachment === attachment) onEventControl(call, result)
                else result.notImplemented()
            }
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
                changeObservation {
                    val next = Any()
                    replaceSubscription(next)
                    try {
                        result.success(null)
                    } catch (failure: RuntimeException) {
                        if (subscription === next) replaceSubscription(null)
                        throw failure
                    }
                    if (subscription === next) startRequested = true
                }
            }
            // Flutter also sends a null cancel on hot restart.
            "cancel" -> {
                if (call.arguments != null && !hasVersion(call)) {
                    result.error("protocolFailure", null, null)
                    return
                }
                changeObservation {
                    replaceSubscription(null)
                    result.success(null)
                }
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
        // Flutter may already have queued work for a handler being removed.
        engineAttachment = null
        changeObservation {
            detachHost()
            if (subscription != null) {
                replaceSubscription(null)
                send(null)
            }
            eventControl?.setMethodCallHandler(null)
            commands?.setMethodCallHandler(null)
            eventControl = null
            commands = null
            messenger = null
        }
    }

    private fun detachHost() = changeObservation {
        val previous = host ?: return@changeObservation
        host = null
        finishSession("detached")
        previous.lifecycle.removeObserver(previous)
    }

    // All transitions run on the main thread. A host can reenter during registration
    // or removal. Fence it immediately and defer new starts until cleanup returns.
    private inline fun changeObservation(change: () -> Unit) {
        observationChangeDepth++
        try {
            change()
            while (observationChangeDepth == 1 && startRequested) {
                startRequested = false
                if (subscription != null) startSession()
            }
        } finally {
            observationChangeDepth--
        }
    }

    private inner class Host(val activity: Activity, val lifecycle: Lifecycle) :
        DefaultLifecycleObserver {
        var started = false
            private set

        override fun onStart(owner: LifecycleOwner) {
            if (host !== this || started) return
            started = true
            changeObservation {
                if (subscription != null) startRequested = true
            }
        }

        override fun onStop(owner: LifecycleOwner) {
            if (host !== this || !started) return
            started = false
            changeObservation { finishSession("backgrounded") }
        }

        override fun onDestroy(owner: LifecycleOwner) {
            if (host === this) detachHost()
        }
    }

    private fun startSession() {
        if (session?.unregister != null) return
        val engine = messenger ?: return
        val generation = (generations[engine] ?: 0L) + 1
        generations[engine] = generation
        val current = Session(generation)
        session = current
        val attached = host
        if (supportsScreenshots() && attached?.started == true) {
            try {
                val cleanup = Api34ScreenshotObserver.register(attached.activity) {
                    if (session === current && current.sequence > 0) {
                        emit(current, "screenshotTaken", "activity")
                    }
                }
                if (session !== current) {
                    cleanup()
                    return
                }
                current.unregister = cleanup
            } catch (_: SecurityException) {
                current.registrationFailure = "permissionMissing"
            } catch (_: RuntimeException) {
                current.registrationFailure = "registrationFailed"
            }
        }
        if (session !== current) return

        val unknownReason = when {
            !supportsScreenshots() || current.unregister != null -> null
            else -> screenshotUnavailableReason()
        }
        emit(
            current, "snapshot", "unknown",
            mapOf(
                "status" to if (unknownReason == null) "unsupported" else "unknown",
                "reason" to (unknownReason ?: "unsupportedOs"),
                "capabilities" to capabilities(),
            ),
        )
    }

    private fun finishSession(reason: String) {
        startRequested = false
        val previous = session ?: return
        session = null
        if (previous.sequence > 0) emit(previous, "invalidated", "unknown", mapOf("reason" to reason))
        previous.unregister?.invoke()
    }

    private fun replaceSubscription(next: Any?) {
        subscription = next
        startRequested = false
        val previous = session
        session = null
        previous?.unregister?.invoke()
    }

    private fun capabilities(): Map<String, Any> {
        val screenshots = when {
            !supportsScreenshots() -> unavailable("unsupportedOs")
            session?.unregister != null -> mapOf("support" to "supported", "scope" to "activity")
            session?.registrationFailure == "permissionMissing" -> unavailable("permissionMissing")
            else -> unavailable(screenshotUnavailableReason(), temporary = true)
        }
        return mapOf(
            "platform" to "android",
            "screenshots" to screenshots,
            "continuousCapture" to unavailable("unsupportedOs"),
        )
    }

    private fun screenshotUnavailableReason(): String = session?.registrationFailure ?: when (host?.started) {
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
        current: Session,
        kind: String,
        scope: String,
        fields: Map<String, Any> = emptyMap(),
    ) {
        val owner = subscription
        val packet = mapOf(
            "version" to VERSION,
            "session" to current.generation,
            "sequence" to current.sequence++,
            "kind" to kind,
            "timestampMs" to timestampMs(),
            "scope" to scope,
        ) + fields
        if (!send(packet) && subscription === owner) {
            changeObservation {
                replaceSubscription(null)
                if (subscription == null) send(null)
            }
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
