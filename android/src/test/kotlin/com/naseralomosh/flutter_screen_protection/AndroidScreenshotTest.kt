package com.naseralomosh.flutter_screen_protection

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.gson.Gson
import com.google.gson.JsonParser
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.mockito.Mockito.*
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import kotlin.test.*

internal class AndroidScreenshotTest {
    @Test
    fun below34UsesUnsupportedFixtureWithoutAccessingTheActivity() {
        for (sdk in listOf(29, 33)) {
            val engine = Engine(sdk)
            val host = TestHost()
            engine.plugin.onAttachedToActivity(host.binding)
            engine.listen()
            engine.assertFixture("androidBelow34", 0)
            assertEquals("unsupportedOs", engine.screenshotCapability()["reason"])
            verifyNoInteractions(host.binding, host.activity)
        }
    }

    @Test
    fun api34AndLaterRegisterOnTheMainExecutorAndEmitTheSharedV1Packets() {
        for (sdk in listOf(34, 35, 36)) {
            val engine = Engine(sdk)
            val host = TestHost()
            engine.plugin.onAttachedToActivity(host.binding)
            host.start()
            assertEquals("initializing", engine.screenshotCapability()["reason"])
            engine.listen()
            val callback = host.callback()
            callback.onScreenCaptured()
            assertEquals(listOf("listen", "snapshot", "screenshotTaken"), engine.order)
            engine.assertFixture("unsupported", 0)
            engine.assertFixture("screenshot", 1)
            assertEquals("supported", engine.screenshotCapability()["support"])
        }
    }

    @Test
    fun duplicateAttachAndStartDoNotRegisterAgainAndReplacementListenCleansUp() {
        val engine = Engine()
        val host = TestHost()
        engine.plugin.onAttachedToActivity(host.binding)
        engine.listen()
        assertEquals("backgrounded", engine.screenshotCapability()["reason"])
        host.start()
        engine.plugin.onAttachedToActivity(host.binding)
        host.start()
        val first = host.callback()
        assertEquals(listOf(1L, 2L), engine.packets.map { it["session"] })
        engine.listen()
        val second = host.callback(count = 2)
        verify(host.activity).unregisterScreenCaptureCallback(first)
        assertEquals(3L, engine.packets.last()["session"])
        assertEquals(0L, engine.packets.last()["sequence"])
        first.onScreenCaptured()
        second.onScreenCaptured()
        assertEquals(listOf("snapshot", "snapshot", "snapshot", "screenshotTaken"), engine.kinds())
    }

    @Test
    fun aStartedActivityCanRebindToAnExistingStreamImmediately() {
        val engine = Engine()
        engine.listen()
        val host = TestHost(startedOnAttach = true)
        engine.plugin.onAttachedToActivity(host.binding)
        host.callback().onScreenCaptured()
        assertEquals(listOf("snapshot", "snapshot", "screenshotTaken"), engine.kinds())
        assertEquals(listOf(1L, 2L, 2L), engine.packets.map { it["session"] })
    }

    @Test
    fun cancellationIsIdempotentAndReleasesObservation() {
        val engine = Engine()
        val host = TestHost()
        engine.plugin.onAttachedToActivity(host.binding)
        host.start()
        engine.listen()
        val callback = host.callback()
        assertNull(engine.call("cancel", null))
        engine.cancel()
        verify(host.activity).unregisterScreenCaptureCallback(callback)
        callback.onScreenCaptured()
        assertEquals(listOf("snapshot"), engine.kinds())
        assertEquals("initializing", engine.screenshotCapability()["reason"])
    }

    @Test
    fun configurationChangeInvalidatesBeforeRebindingAndDropsLateCallbacks() {
        val engine = Engine()
        engine.listen()
        assertEquals("detached", engine.screenshotCapability()["reason"])
        val original = TestHost()
        engine.plugin.onAttachedToActivity(original.binding)
        original.start()
        val first = original.callback()
        engine.plugin.onDetachedFromActivityForConfigChanges()
        engine.plugin.onDetachedFromActivityForConfigChanges()
        verify(original.activity).unregisterScreenCaptureCallback(first)
        verify(original.lifecycle).removeObserver(original.observer())
        assertEquals("detached", engine.packets.last()["reason"])
        val replacement = TestHost()
        engine.plugin.onReattachedToActivityForConfigChanges(replacement.binding)
        replacement.start()
        val second = replacement.callback()
        original.start()
        first.onScreenCaptured()
        second.onScreenCaptured()
        assertEquals(listOf("snapshot", "snapshot", "invalidated", "snapshot", "screenshotTaken"), engine.kinds())
        assertEquals(listOf(1L, 2L, 2L, 3L, 3L), engine.packets.map { it["session"] })
        assertEquals(listOf(0L, 0L, 1L, 0L, 1L), engine.packets.map { it["sequence"] })
        engine.plugin.onDetachedFromActivity()
        verify(replacement.activity).unregisterScreenCaptureCallback(second)
    }

    @Test
    fun stopAndStartRefreshTheSnapshotAndEngineDetachEndsTheStream() {
        val engine = Engine()
        val host = TestHost()
        engine.plugin.onAttachedToActivity(host.binding)
        host.start()
        engine.listen()
        val first = host.callback()
        host.observer().onStop(host.owner)
        verify(host.activity).unregisterScreenCaptureCallback(first)
        assertEquals("backgrounded", engine.packets.last()["reason"])
        first.onScreenCaptured()
        host.start()
        val second = host.callback(count = 2)
        engine.plugin.onDetachedFromEngine(engine.binding)
        verify(host.activity).unregisterScreenCaptureCallback(second)
        assertEquals(listOf("snapshot", "invalidated", "snapshot", "invalidated"), engine.kinds())
        assertEquals("end", engine.order.last())
        assertEquals(emptyMap(), engine.handlers)
    }

    @Test
    fun activityDestructionCleansUpEvenBeforeTheEmbeddingDetaches() {
        val engine = Engine()
        val host = TestHost(startedOnAttach = true)
        engine.plugin.onAttachedToActivity(host.binding)
        engine.listen()
        val callback = host.callback()
        host.observer().onDestroy(host.owner)
        engine.plugin.onDetachedFromActivity()
        verify(host.activity).unregisterScreenCaptureCallback(callback)
        callback.onScreenCaptured()
        assertEquals(listOf("snapshot", "invalidated"), engine.kinds())

        `when`(host.activity.isDestroyed).thenReturn(true)
        engine.plugin.onAttachedToActivity(host.binding)
        host.callback()
        assertEquals("detached", engine.screenshotCapability()["reason"])
    }

    @Test
    fun missingPermissionAndRegistrationFailureGiveSafeSnapshots() {
        for (failure in listOf("permissionMissing", "registrationFailed")) {
            val engine = Engine()
            val host = TestHost()
            if (failure == "permissionMissing") {
                `when`(host.activity.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE))
                    .thenReturn(PackageManager.PERMISSION_DENIED)
            } else {
                host.registrationError = IllegalStateException()
            }
            engine.plugin.onAttachedToActivity(host.binding)
            host.start()
            engine.listen()
            assertEquals(failure, engine.screenshotCapability()["reason"])
            assertEquals("unknown", engine.packets.single()["status"])
            assertEquals(failure, engine.packets.single()["reason"])
            if (failure == "permissionMissing") {
                assertTrue(host.callbacks.isEmpty())
            } else {
                val callback = host.callback()
                verify(host.activity).unregisterScreenCaptureCallback(callback)
                callback.onScreenCaptured()
                assertEquals(listOf("snapshot"), engine.kinds())
            }
        }
    }

    @Test
    fun unregistrationAndTransportFailuresFenceCallbacks() {
        val engine = Engine()
        val host = TestHost()
        engine.plugin.onAttachedToActivity(host.binding)
        host.start()
        engine.listen()
        val callback = host.callback()
        doThrow(IllegalStateException()).`when`(host.activity).unregisterScreenCaptureCallback(callback)
        engine.failSend = true
        callback.onScreenCaptured()
        verify(host.activity).unregisterScreenCaptureCallback(callback)
        assertEquals(listOf("listen", "snapshot", "end"), engine.order)
        callback.onScreenCaptured()
        engine.cancel()
        assertEquals(listOf("snapshot"), engine.kinds())
    }

    @Test
    fun rejectsInvalidListenAndKeepsTheExistingSubscription() {
        val engine = Engine()
        val host = TestHost()
        engine.plugin.onAttachedToActivity(host.binding)
        host.start()
        engine.listen()
        val callback = host.callback()
        assertFailsWith<io.flutter.plugin.common.FlutterException> {
            engine.call("listen", mapOf("version" to 2))
        }
        callback.onScreenCaptured()
        assertEquals(listOf("snapshot", "screenshotTaken"), engine.kinds())
    }

    private class TestHost(startedOnAttach: Boolean = false) {
        val owner = mock(LifecycleOwner::class.java)
        val executor = Executor { it.run() }
        val callbacks = mutableListOf<Activity.ScreenCaptureCallback>()
        var registrationError: RuntimeException? = null
        val activity = mock(Activity::class.java) { invocation ->
            if (invocation.method.name == "registerScreenCaptureCallback") {
                assertSame(executor, invocation.getArgument(0))
                callbacks.add(invocation.getArgument(1))
                registrationError?.let { throw it }
            }
            RETURNS_DEFAULTS.answer(invocation)
        }
        private val observers = mutableListOf<DefaultLifecycleObserver>()
        val lifecycle = mock(Lifecycle::class.java) { invocation ->
            if (invocation.method.name == "addObserver") {
                val observer = invocation.getArgument<DefaultLifecycleObserver>(0)
                observers.add(observer)
                if (startedOnAttach) observer.onStart(owner)
            }
            RETURNS_DEFAULTS.answer(invocation)
        }
        val binding = mock(ActivityPluginBinding::class.java)

        init {
            `when`(binding.activity).thenReturn(activity)
            `when`(binding.lifecycle).thenReturn(HiddenLifecycleReference(lifecycle))
            `when`(activity.mainExecutor).thenReturn(executor)
            `when`(activity.checkSelfPermission(Manifest.permission.DETECT_SCREEN_CAPTURE))
                .thenReturn(PackageManager.PERMISSION_GRANTED)
        }

        fun observer() = observers.single()

        fun start() = observer().onStart(owner)

        fun callback(count: Int = 1): Activity.ScreenCaptureCallback {
            assertEquals(count, callbacks.size)
            return callbacks.last()
        }
    }

    private class Engine(sdk: Int = 34) {
        private var clock = 1700000000000L
        val plugin = FlutterScreenProtectionPlugin({ sdk }, { clock++ })
        val binding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler>()
        val packets = mutableListOf<Map<*, *>>()
        val order = mutableListOf<String>()
        var failSend = false
        private val codec = StandardMethodCodec.INSTANCE
        private val eventChannel = "flutter_screen_protection/events"
        private val version = mapOf("version" to 1)

        init {
            val messenger = mock(BinaryMessenger::class.java) { invocation ->
                val channel = invocation.getArgument<String>(0)
                when (invocation.method.name) {
                    "setMessageHandler" -> {
                        val handler = invocation.getArgument<BinaryMessenger.BinaryMessageHandler?>(1)
                        if (handler == null) handlers.remove(channel) else handlers[channel] = handler
                    }
                    "send" -> {
                        assertEquals(eventChannel, channel)
                        val message = invocation.getArgument<ByteBuffer?>(1)
                        if (message == null) {
                            order.add("end")
                        } else {
                            if (failSend) throw IllegalStateException()
                            val packet = codec.decodeEnvelope(message.readable()) as Map<*, *>
                            packets.add(packet)
                            order.add(packet["kind"] as String)
                        }
                    }
                }
                null
            }
            `when`(binding.binaryMessenger).thenReturn(messenger)
            plugin.onAttachedToEngine(binding)
        }

        fun listen() = assertNull(call("listen", version, recordAcknowledgement = true))
        fun cancel() = assertNull(call("cancel", version))
        fun kinds() = packets.map { it["kind"] }

        fun screenshotCapability(): Map<*, *> {
            val response = call("getCaptureCapabilities", version, channel = "flutter_screen_protection") as Map<*, *>
            assertEquals(1, response["version"])
            return (response["capabilities"] as Map<*, *>)["screenshots"] as Map<*, *>
        }

        fun call(
            method: String,
            arguments: Any?,
            recordAcknowledgement: Boolean = false,
            channel: String = eventChannel,
        ): Any? {
            var reply: ByteBuffer? = null
            val request = codec.encodeMethodCall(MethodCall(method, arguments)).readable()
            handlers.getValue(channel).onMessage(request) {
                if (recordAcknowledgement) order.add(method)
                reply = it
            }
            return codec.decodeEnvelope(checkNotNull(reply).readable())
        }

        fun assertFixture(name: String, index: Int) {
            val fixtures = javaClass.getResourceAsStream("/capture_v1.json")!!.bufferedReader().use {
                JsonParser.parseReader(it).asJsonObject
            }
            assertEquals(fixtures[name], Gson().toJsonTree(packets[index]))
        }

        // Android's messenger copies the written bytes into a readable buffer.
        private fun ByteBuffer.readable(): ByteBuffer = duplicate().apply { flip() }
    }
}
