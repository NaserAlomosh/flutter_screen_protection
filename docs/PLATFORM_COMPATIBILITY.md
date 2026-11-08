# Platform compatibility

Research checked 2026-11-08. This matrix shows public OS primitives and planned plugin coverage. Device support remains subject to the release test gate. Android 17 and iOS 27 are the latest stable major lines identified for this review. Android minor and quarterly builds and iOS patch releases should be recorded individually in the device report. [Android API levels](https://developer.android.com/guide/topics/manifest/uses-sdk-element), [Android 17 release](https://developer.android.com/blog/posts/android-17-is-here), [Apple releases](https://developer.apple.com/news/releases/).

| Runtime | Screenshot event | Initial capture state and changes | Widget masking | Full-window capture blocking | App-switcher privacy |
| --- | --- | --- | --- | --- | --- |
| Android 10 (29) | Unavailable | Unavailable | Local or fallback policy | `FLAG_SECURE` | Secure-window policy |
| Android 11 (30) | Unavailable | Unavailable | Local or fallback policy | `FLAG_SECURE` | Secure-window policy |
| Android 12 / 12L (31/32) | Unavailable | Unavailable | Local or fallback policy | `FLAG_SECURE` | Secure-window policy |
| Android 13 (33) | Unavailable | Unavailable | Local or fallback policy | `FLAG_SECURE` | Recents control or secure-window policy |
| Android 14 (34) | Activity callback | Unavailable | Local or fallback policy | `FLAG_SECURE` | Recents control or secure-window policy |
| Android 15 (35) | Activity callback | UID recording visibility | Local and reactive | `FLAG_SECURE` | Recents control or secure-window policy |
| Android 16 (36 series) | Activity callback | UID recording visibility | Local and reactive | `FLAG_SECURE` | Recents control or secure-window policy |
| Android 17 (37 series) | Activity callback | UID recording visibility | Local and reactive | `FLAG_SECURE` | Recents control or secure-window policy |
| iOS 15–16 | UIKit notification | Bound `UIScreen` state and notification | Local and reactive | Unavailable for general app UI | Native window overlay |
| iOS 17–18 | UIKit notification | Bound scene trait, with verified screen fallback where needed | Local and reactive | Unavailable for general app UI | Native window overlay |
| iOS 26–27 | UIKit notification | Bound scene trait | Local and reactive | Unavailable for general app UI | Native window overlay |

Apple's release naming jumps from iOS 18 to 26. Android window controls and iOS overlays are optional proposals. All widget modes can run locally without detection. In the default policy an unavailable signal leaves protected fields masked.

## Android

- **API 34 screenshot callback.** Declare the install-time `DETECT_SCREEN_CAPTURE` permission. Register the callback with the visible Activity's lifecycle and use the main executor. Android 14 documents support for the designated hardware button combination and excludes ADB and instrumentation captures. Android notifies the user that detection occurred. The callback provides no image or pre-capture interception. Validate additional OEM methods independently. [Screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection).
- **API 35 recording visibility.** Declare `DETECT_SCREEN_RECORDING`. Register via `WindowManager.addScreenRecordingCallback`, use the returned current value, and remove the same callback at teardown. Visibility refers to activities of the registering UID included in recording. A transition to invisible can mean the app left the capture while recording continues. Validate full-display and single-app capture separately. Treat unsupported projection or sharing paths and inaccessible host state as limitations. Detection does not request MediaProjection consent. [WindowManager](https://developer.android.com/reference/android/view/WindowManager#addScreenRecordingCallback(java.util.concurrent.Executor,java.util.function.Consumer%3Cjava.lang.Integer%3E)), [permissions](https://developer.android.com/reference/android/Manifest.permission).
- **Window privacy.** `FLAG_SECURE` protects the flagged window on platform-supported screenshots and nonsecure displays. Android documents reliability limits on older devices, including API 30 and below. API 33 `setRecentsScreenshotEnabled(false)` is limited to the activity representation in Overview. [Secure activities](https://developer.android.com/security/fraud-prevention/activities), [Activity reference](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean)).

## iOS

- **Screenshot notification.** `UIApplication.userDidTakeScreenshotNotification` is available since iOS 7, arrives after capture, and supplies no payload or scene attribution. No permission prompt is required. [UIKit notification](https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification).
- **Continuous capture.** Prefer `traitCollection.sceneCaptureState` and trait observation on the bound host view from iOS 17. Preserve unspecified or unbound as unknown. On iOS 15–16 use the bound screen's `isCaptured` and `capturedDidChangeNotification`, available since iOS 11. Filter the notification to that screen. Apple marks `isCaptured` deprecated in favor of scene state, while the local iOS 26.5 header uses an unspecified deprecation version. This plan assigns no exact deprecation OS. API floors were cross-checked in UIKit SDK headers. No capture permission prompt is required. Signals can include mirroring, recording, or sharing and cannot reliably distinguish them. [Apple capture guidance](https://developer.apple.com/documentation/swiftui/protecting-sensitive-content-when-screen-sharing), [UIScreen.isCaptured](https://developer.apple.com/documentation/uikit/uiscreen/iscaptured), [change notification](https://developer.apple.com/documentation/uikit/uiscreen/captureddidchangenotification).
- **Scene lifecycle.** The example currently uses the legacy AppDelegate setup. Apple requires scenes on iOS 27 when built with the latest SDK. Validate example migration and embedded host view binding on Xcode 27 before declaring support. [Apple lifecycle guidance](https://developer.apple.com/documentation/UIKit/transitioning-to-the-uikit-scene-based-life-cycle).
- **App-switcher snapshots.** Cover the bound window synchronously with neutral content during the background transition. Verify the actual snapshot and foreground restoration per scene. [Apple QA1838](https://developer.apple.com/library/archive/qa/qa1838/_index.html).

The current Android library compile SDK 36 exposes the proposed API 34–35 calls. Runtime compatibility with Android 17 still needs testing. The current local Apple SDK is iOS 26.5. iOS 27 builds and runtime behavior require additional tooling and evidence.
