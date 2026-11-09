# Security limitations

## Protection boundaries

| Mechanism | What it can protect | Remaining exposure |
| --- | --- | --- |
| Android Activity and iOS UIKit screenshot signals | Allow a host to react after a supported screenshot | Pixels already captured remain as captured. Other screenshot methods may be invisible. |
| Android UID visibility and iOS capture state | Drive a change to the live interface when capture is observed | Native callback delivery, channel delivery, and Flutter frame latency leave an exposure window. Capture can start before initialization or resume. |
| Opaque mask or safe replacement | Keeps the sensitive subtree off the rendered UI while the policy is in force | Earlier frames, other copies of the value, and previously focused or exported content remain outside the widget's control. |
| Blur | Changes the appearance of currently rendered pixels | Length, shape, contrast, and partially recoverable information can remain. The content is still part of the rendering pipeline. |
| Android `FLAG_SECURE` | Lets Android enforce a window-wide policy for supported capture and nonsecure displays | Affects the entire window. Older device reliability and behavior with other windows and capture paths require validation. |
| Native app-switcher policy | Protects the OS-generated background preview in tested conditions | Foreground capture, lifecycle timing, and other windows require separate treatment. |

See the [API availability and platform sources](PLATFORM_COMPATIBILITY.md).

## Android screenshot observation

Android delivers the supported Activity callback after capture. The event carries metadata only. It cannot prevent a screenshot, retroactively redact pixels or signal that a screen recording has started. Android shows a detection notice to the user. Android 14 documents the hardware screenshot button combination and excludes ADB screenshot commands and instrumentation captures. Other gestures and OEM paths require separate evidence. The adapter observes only the bound, started Activity and leaves window flags under host ownership. [Android screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection).

## Selective exclusion from captured output

Android supports `SurfaceView.setSecure(true)` from API 17. It must be configured before the containing window attaches and applies only to content drawn on that separate native surface. An ordinary Flutter widget shares the Flutter render surface. A secure SurfaceView cannot mark an arbitrary region of that buffer secure. A custom native renderer would need its own surface, compositing, semantics and lifecycle design, with physical evidence before any separate feature claim. API 35 `View.setContentSensitivity` secures the hosting window during active MediaProjection, so it is not a per-view exclusion mechanism. [SurfaceView](https://developer.android.com/reference/android/view/SurfaceView#setSecure(boolean)), [View sensitivity](https://developer.android.com/reference/android/view/View#setContentSensitivity(int)).

UIKit offers capture state and screenshot notifications. Apple's guidance describes hiding sensitive content in response to capture state. The public `isSecureTextEntry` property serves text input. Moving a Flutter view or layer into the internal secure text field hierarchy relies on undocumented implementation behavior and can break rendering, input, accessibility, or future OS compatibility. Treat that approach as excluded and as an App Review risk. No documented public general-purpose iOS switch for excluding arbitrary Flutter views or blocking all screenshots was identified. [Apple capture guidance](https://developer.apple.com/documentation/swiftui/protecting-sensitive-content-when-screen-sharing), [secure text entry](https://developer.apple.com/documentation/uikit/uitextinputtraits/issecuretextentry), [App Review Guidelines §2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

## Fail-safe policy and data handling

- Default protected fields to opaque masking while capture state is pending, unsupported, unbound, or failed. Hosts can keep a field masked at all times if exposure is unacceptable. Known inactive means the API currently reports no capture in its scope. Unsupported methods, external cameras, privileged tools, and compromised OSs can still capture visible content.
- Use a constant or app-supplied safe placeholder. Remove sensitive semantics, focus, selection, and hit testing while protected. Clear any transient editing UI when moving a sensitive screen into protection. Hosts own copies outside the protected subtree, including other views, clipboard, autofill and any app analytics.
- Send only event types, state, scope, reason codes and timestamps. No screenshot images, widget content, recording pixels, account identifiers, storage or network permissions, persistence, or telemetry. Keep example event history bounded and in memory.
- Review Android permission ownership and window flags with the host. Verify all owned windows and lifecycle transitions. Treat test results as scoped to the device, OS build, capture method and policy exercised.

## Unresolved release risks

The first captured frame can precede masking. OEM screenshot gestures and recording tools vary. Android visibility can interact with secure-window policy and split-screen. iOS needs physical verification of initial scene traits, mirroring, external displays and switcher timing. Document each unsupported or unverified path and keep optional policies gated until ownership and capture output are verified.
