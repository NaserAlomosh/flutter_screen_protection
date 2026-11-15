# API design

Phase 1 Dart contract with Android screenshot observation. Widget rendering remains planned. Keep the existing `FlutterScreenProtection().getPlatformVersion()` callable. Add a controller with an explicit owner and inject it into the widget or share it through a host scope later if needed.

| API | Contract |
| --- | --- |
| `FlutterScreenProtectionController.initialize()` | Concurrent calls share initialization. Completes after the first synchronized snapshot, including an explicit unsupported snapshot. Operational failure during initialization leaves the state unknown and returns a `CaptureException`. After initialization, transport and protocol failures update the state and capability reasons. Call again after a failure to start a fresh native session. On a platform outside Android or iOS, initialization completes with an explicit local unsupported state. |
| `captureEvents` | Broadcast stream of `ScreenshotTaken`, `CaptureStateChanged`, `CaptureStateInvalidated`, and native `CaptureError` events. Listeners own cancellation. Events describe observations, with UTC timestamps, scope, session, and sequence. No history replay. |
| `state` | Read-only listenable capture snapshot with current status, scope, and reason. Starts unknown. Snapshot synchronization updates this even if no event listener is attached. |
| `capabilities` | Read-only capability snapshot per feature with supported, unavailable, or temporarily unavailable and a stable reason. Refresh on rebind. Screenshot and continuous capture support are independent. |
| `dispose()` | Async and idempotent. Cancels observation, closes the stream and releases controller-owned handles. Terminal for the controller. Construct a new owner to restart. |
| `SensitiveProtectionConfiguration` | App-owned mask, blur, or replace configuration. Defaults to mask under uncertainty and supports explicit reveal and always-protect options. Replacement content remains in Dart. |

Use `CaptureStatus.active`, `inactive`, `unknown`, and `unsupported`. `active` reflects Android recording visibility or iOS continuous capture. A false boolean would conflate unknown and inactive, so the initial API exposes a typed status. Use distinct reasons for initializing, backgrounded, detached, unsupported OS, permission missing, and transport/protocol failure. No artificial started or stopped event on initial sync or invalidation. Emit confirmed transitions only within a synchronized binding. A new binding begins with a fresh snapshot even if the previous binding had a known state.

## Wire contract

The v1 contract uses Flutter's StandardMethodCodec. [MethodChannel](https://api.flutter.dev/flutter/services/MethodChannel-class.html) · [EventChannel](https://api.flutter.dev/flutter/services/EventChannel-class.html)

- **MethodChannel** `flutter_screen_protection` keeps `getPlatformVersion` unchanged. The Android `getCaptureCapabilities` command takes `{"version":1}` and returns `{"version":1,"capabilities":{…}}` using the structure below. This query is diagnostic. The controller takes capabilities and state from the ordered snapshot.
- **EventChannel** `flutter_screen_protection/events` receives `listen` and `cancel` with `{"version":1}`. Successful commands return a null success envelope. Deliver observations as success envelopes on the same channel. Flutter's binary null message ends the stream. The Dart adapter handles acknowledgements explicitly and queues up to 64 early packets until registration succeeds.
- The native adapter must serialize acknowledgement, observer setup, snapshot emission, events, invalidation, and cancellation on the main thread. Fence old callbacks before acknowledging cancel. Cancel is idempotent. A new listen must release any prior registration before creating the replacement. On host detach, invalidate before removing observation and releasing native resources.

Every packet is a string-keyed map with the following fields. Unknown additive fields are ignored. Unknown versions, enum values, or invalid types in required fields fail closed. Omit optional reasons when absent. Decoding also accepts null for an optional reason.

| Field | Type and meaning |
| --- | --- |
| `version` | Integer `1`. |
| `session` | Integer from 1 through 2⁵³−1. Native generations strictly increase for each new binding and stream listen on the same engine. |
| `sequence` | Integer from 0 through 2⁵³−1. Start at 0 for each snapshot, then increment by one per packet. |
| `kind` | `snapshot`, `screenshotTaken`, `captureStarted`, `captureStopped`, `invalidated`, or `error`. |
| `timestampMs` | Integer UTC Unix epoch milliseconds from 0 through 8640000000000000. Timestamp is informational. Session and sequence determine order. |
| `scope` | `unknown`, `activity`, `uid`, `application`, `scene`, or `screen`. Snapshot scope matches the continuous capability scope. Signal events use the corresponding supported scope. |

| Kind | Additional fields and behavior |
| --- | --- |
| `snapshot` | `status` is `unknown`, `active`, `inactive`, or `unsupported`. Include `capabilities` and include a `reason` for unknown or unsupported. Known states require supported continuous detection and no reason. Unsupported requires an unavailable continuous capability with the same reason. |
| `screenshotTaken` | Envelope only. Continuous capture state stays as it was. |
| `captureStarted`, `captureStopped` | Envelope only. Map to active and inactive. Require a known previous observation within the same binding. A change from unknown requires a new snapshot. |
| `invalidated` | Required `reason`. Reset state to unknown and mark capabilities temporarily unavailable. The binding ends and the next binding starts with a newer snapshot on the same stream. |
| `error` | Required `reason`. Publish a typed native error and retire the stream. Use a channel error for registration failure before the first snapshot. |

A capability snapshot has a `platform` field (`android`, `ios`, or `other`) and two maps named `screenshots` and `continuousCapture`. Each map has `support` (`supported`, `unavailable`, or `temporarilyUnavailable`), `scope`, and a `reason` when support is unavailable or temporarily unavailable. Supported screenshots use Android `activity` or iOS `application` scope. Supported continuous capture uses Android `uid` or iOS `scene`/`screen` scope.

Stable `CaptureReason` strings are `initializing`, `backgrounded`, `detached`, `ambiguousHost`, `unsupportedPlatform`, `unsupportedOs`, `permissionMissing`, `registrationFailed`, `transportFailure`, `protocolFailure`, `initializationTimeout`, and `disposed`. Transmit reason codes and metadata only. Channel exception messages, details, and stack traces are discarded in Dart.

Packets from obsolete generations and repeated or older sequences are dropped. A gap, malformed current packet, invalid transition, unexpected new generation without a snapshot, or unsupported protocol version invalidates state and retires the stream. Initialization defaults to a 10-second deadline for registration and the first snapshot. After stream failure, an explicit `initialize()` retries after cancellation and waits for a newer generation. On lifecycle invalidation the existing stream stays open for a replacement binding. Disposing closes the Dart broadcast and releases native subscription ownership.

### Android screenshot capability

On API 33 and below the screenshot capability is `unavailable` with `unsupportedOs`. On API 34 and above a successful callback registration yields `supported` with `activity` scope. Before registration, the diagnostic query reports `initializing` for a started Activity, `backgrounded` for a stopped Activity, or `detached` for an unbound engine. These are temporarily unavailable. A missing manifest grant yields `unavailable` with `permissionMissing`, and another registration exception yields `temporarilyUnavailable` with `registrationFailed`. Both registration failures yield a valid snapshot with safe `unknown` state, so controller initialization can complete and the host can read the feature-specific reason. A subsequent Activity start or stream listen makes a fresh registration attempt.

Android continuous capture is currently unavailable with `unsupportedOs` on all supported Android versions, including those with a recording API. A `screenshotTaken` event has only the v1 envelope fields and leaves the continuous state unchanged. An Activity lifecycle invalidation changes state to `unknown` until the next binding snapshot.

Shared JSON wire examples are in [capture_v1.json](../test/fixtures/capture_v1.json). Kotlin and Swift tests can reuse the fixtures.

## Widget contract

```dart
SensitiveContent(
  controller: controller,
  protection: SensitiveProtection.blur,
  blurSigma: 12,
  child: const Text('0000 0000 0000 0000'),
)

SensitiveContent(
  controller: controller,
  protection: SensitiveProtection.replace,
  replacement: const Text('••••••••'),
  child: const Text('12,450.75 JOD'),
)
```

In the planned default policy the configured mode applies to known active capture and an opaque mask applies to unknown and unsupported states. Known inactive reveals content unless the host selects an always-protect policy. An explicit host override may reveal on unsupported states. Validate a finite positive sigma and require replacement for replace mode. Use caller constraints or fixed placeholders for stable layout. Swapping out a subtree may reset child-local state. The application retains business state outside the subtree. Replace and mask build safe content in place of the child. Blur uses clipped `ImageFiltered` over the child with semantics and interaction suppressed. Background blur would filter surrounding content and adds avoidable work. Avoid caching rendered sensitive data. Rebuild each field only on a change to its effective presentation and unsubscribe when its controller changes or the field is disposed. [ImageFiltered](https://api.flutter.dev/flutter/widgets/ImageFiltered-class.html).
