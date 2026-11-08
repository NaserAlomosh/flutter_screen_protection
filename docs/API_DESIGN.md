# API design

Proposed contract for Phase 1 review. Keep the existing `FlutterScreenProtection().getPlatformVersion()` callable. Add a controller with an explicit owner and inject it into the widget or share it through a host scope later if needed.

| Proposed API | Contract |
| --- | --- |
| `FlutterScreenProtectionController.initialize()` | Concurrent calls share initialization. Completes after the first synchronized snapshot, including an explicit unsupported snapshot. Operational failure leaves safe state and returns a typed error. Retry requires a fresh native session. |
| `captureEvents` | Broadcast stream of `ScreenshotTaken` and `CaptureStateChanged`. Listeners own cancellation. Events describe observations, with UTC timestamps and scope. No history replay. |
| `state` | Read-only listenable capture snapshot with current status, scope, and reason. Starts unknown. Snapshot synchronization updates this even if no event listener is attached. |
| `capabilities` | Read-only capability snapshot per feature with supported, unavailable, or temporarily unavailable and a stable reason. Refresh on rebind. Screenshot and continuous capture support are independent. |
| `dispose()` | Async and idempotent. Cancels observation, closes the stream and releases controller-owned handles. Terminal for the controller. Construct a new owner to restart. |
| `acquireSecureWindow()` | Optional reviewed API. Returns a disposable lease after acknowledgement. Multiple leases aggregate per window. Unavailable on iOS. |

Use `CaptureStatus.active`, `inactive`, `unknown`, and `unsupported`. `active` reflects Android recording visibility or iOS continuous capture. A false boolean would conflate unknown and inactive, so the initial API exposes a typed status. Use distinct reasons for initializing, backgrounded, detached, unsupported OS, permission missing, and transport/protocol failure. No artificial started or stopped event on initial sync or invalidation. Emit confirmed transitions only within a synchronized binding. A new binding begins with a fresh snapshot even if the previous binding had a known state.

## Wire contract

Keep `flutter_screen_protection` for method calls. Add `flutter_screen_protection/events` for observations. Agree on versioned maps before implementation. Each observation includes schema version, stream generation, sequence, kind, scope, and UTC epoch milliseconds stamped when observed by native code. Snapshots contain capabilities and current state. Sequence determines order. Clock time is informational. Drop stale generations and duplicate sequences. A gap or unknown schema invalidates current state and triggers controlled resync or a typed failure. Malformed packets and platform errors carry safe reason codes. Treat MissingPluginException on a known unsupported platform as unavailable. On an expected host, treat it as a registration failure. Close only on terminal disposal. A disconnected host invalidates the state until reattachment.

[MethodChannel](https://api.flutter.dev/flutter/services/MethodChannel-class.html), [EventChannel](https://api.flutter.dev/flutter/services/EventChannel-class.html).

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
