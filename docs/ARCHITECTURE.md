# Architecture

## Repository audit

Baseline inspected at `07a193a`. Findings come from source and configuration inspection.

| Area | Current state |
| --- | --- |
| Package | `pubspec.yaml` declares package version 0.0.1, Dart `^3.9.2` and Flutter `>=3.3.0`. Both SDK constraints apply. Flutter 3.3 does not bundle Dart 3.9, so the declared Flutter lower bound is misleading as a compatibility statement. The local example points to Flutter 3.35.7. Test and declare an actual joint floor in a later phase. |
| Dart | `lib/` has an instance facade, token-verified `FlutterScreenProtectionPlatform`, and default method-channel implementation. `flutter_screen_protection` carries only `getPlatformVersion`. |
| Android | `android/build.gradle` defines min SDK 24 and compile SDK 36, AGP 8.9.1, Kotlin 2.1.0, Java/Kotlin target 11. No library target SDK is set there. The example uses Flutter Gradle defaults, which resolve to min 24 and compile/target 36 with its configured SDK. Registration uses Flutter embedding v2 with the Kotlin class declared in pubspec. The engine-bound handler reports OS version and detaches its handler. No Activity binding or capture permissions exist in the library. |
| iOS | Podspec and example project set deployment target 13.0. The podspec declares Swift 5.0 and a Flutter dependency. The Swift registrar installs the version method handler. The example registers via its AppDelegate and has no scene manifest. The privacy manifest is present but its resource-bundle entry is commented out. |
| Example | One Flutter screen displays the version with fallback on platform error. No capture UI or privacy policies. |
| Tests | Two Dart test files cover delegation/default implementation and mocked version lookup. Kotlin and XCTest fixtures cover version handling. The example widget test checks the status label and the integration test checks a nonempty native version. No capture, protection, or lifecycle coverage exists. |
| Distribution | README and changelog were scaffold text. License, package homepage, and podspec metadata require maintainer input. No tracked GitHub Actions workflows. The configured GitHub remote establishes repository identity only. |

References for compatibility policy. [Flutter deployment support](https://docs.flutter.dev/reference/supported-platforms), [Dart SDK constraints](https://dart.dev/tools/pub/pubspec#sdk-constraints).

## Layers

- **Dart facade and models** expose typed capabilities, capture state, capture events, errors, and protection configuration. The existing version facade and platform interface stay source-compatible. Window policy handles remain optional future work.
- **Capture controller** is the single owner per Flutter host, normally scoped to the root of its widget tree. It maintains current state and fans out events. Consumers receive read-only state. The controller subscribes before initialization completes and keeps monitoring while it owns the host, independent of app listener count.
- **Platform transport** uses a separate injectable `CapturePlatform` seam so existing version implementations and mocks retain their interface. The channel adapter uses MethodChannel for commands and EventChannel for ordered snapshots and events. It owns the EventChannel listen/cancel handshake so registration failures reach the controller as safe reasons.
- **Planned Android adapter** binds the current Activity through `ActivityAware`. Observe started/stopped state using a reviewed Flutter lifecycle bridge or supported host callbacks. Attach screenshot callbacks for the eligible Activity and recording callbacks while the host is eligible. Guard APIs and permission failures independently. Keep window policy ownership separate from detection.
- **Planned iOS adapter** binds the Flutter host view/window and scene via public Flutter/UIKit lifecycle hooks. On the main thread, observe screenshot notifications and the host view's capture trait. For iOS 15–16 observe the bound screen. Remove observers, trait registrations, and overlays when the host detaches. For a scene-less or ambiguous host, expose the verified fallback or unknown scope and hold the safe policy.
- **Planned widget** maps controller state and local policy to a small render state, and rebuilds only when that state changes. It does not create platform observers.

## Lifecycle and ordering

The Dart controller owns one subscription regardless of broadcast listener count. The default adapter rejects a concurrent owner of its channel. The state listenable is readable before initialization and retains the latest observation for late listeners. Failures clear observation immediately, fence old callbacks, and serialize cancellation before an explicit retry. A retry requires a newer native generation than the last accepted one. Dispose is terminal, idempotent, and independent of paused consumer listeners. The [v1 protocol](API_DESIGN.md#wire-contract) defines the producer and consumer ordering rules.


Use one native registration generation per binding, with a monotonically increasing sequence inside each stream session. Serialize observer registration, initial reads, state emission, and invalidation on the native main thread. Send an initial snapshot on the event channel, then changes through the same channel. Do not combine a method-channel state read with an independently ordered stream. For Android recording, use the registration return value, then process queued callbacks. For iOS, install observation and read the bound trait or screen on the main thread.

On background/stop or detach, invalidate current observation and clear stale callbacks using the generation. On resume or rebind, require a fresh snapshot before revealing values. Do not represent lifecycle invalidation as capture ending. Rotation, Activity recreation, hot restart, scene disconnection and host errors release registrations even if Dart cancellation never arrives. Rebind only after the new host is identified. Explicit owner teardown cancels the stream, restores plugin-owned policies, and closes Dart state.

## Optional policies

Use route-owned leases for Android secure-window policy with an effective OR per window. Track the pre-existing flag and clear only a bit the plugin acquired. Document exclusive coordination with host code that also writes the flag, since a concurrent writer cannot be distinguished. Reapply a continuing lease to a replacement window before its sensitive view is shown. If applying a required policy fails, keep the content masked.

Keep Android Recents policy separate. Review restoration first because the public Activity method is a setter and the plugin cannot infer prior ownership. Require explicit host ownership or defer it. iOS uses a separate, nonanimated native overlay for each owned window, inserted before the background snapshot and removed after the scene is ready and capture state has refreshed. Prefer a public host integration point over global window discovery.

See the [decision register](DECISION_REGISTER.md) for pending ownership, lifecycle, and scope decisions.
