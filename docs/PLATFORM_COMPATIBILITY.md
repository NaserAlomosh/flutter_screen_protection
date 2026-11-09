# Platform compatibility

ADR-007 was approved for implementation and qualification on 2026-11-08. The feature matrix describes OS primitives and planned capture coverage. Build and runtime evidence below covers the existing version plugin and Dart capture foundation.

## Approved configuration

| Area | Applied settings |
| --- | --- |
| Flutter and Dart | The package and example require Flutter **3.35.4 or later** and Dart **3.9.2 or later within Dart 3**. Flutter 3.35.4 bundles Dart 3.9.2. |
| Android installation and support | The library and example declare **minSdk 24** (Android 7.0). The approved project support floor is **Android 10 / API 29**, verified on the API 29 emulator below. API 24–28 are outside the support matrix. |
| Android build | The library and example use **compileSdk 36**, **Gradle 8.14**, **AGP 8.11.1**, **Kotlin 2.2.20**, and **JVM target 11**. The example pins the Gradle daemon to **JDK 17**. Use JDK 17 to launch the build as well. The library leaves `targetSdk` to the host. The example inherits it from Flutter. |
| iOS installation and build | The podspec, Runner project, and Flutter framework metadata declare deployment target **15.0**. The pod and example compile in **Swift 5** language mode. |

The approved Android pins cover API 36 and meet the minimum checks in Flutter 3.47.9. AGP 8.11.1 requires SDK Build Tools 35.0.0 or later and JDK 17. Flutter manages the example NDK version. Flutter 3.35.4 uses NDK 27.0.12077973, and Flutter 3.47.7 uses NDK 28.2.13676358. Both NDKs were installed locally. [AGP 8.11](https://developer.android.com/build/releases/agp-8-11-0-release-notes) · [Kotlin compatibility](https://kotlinlang.org/docs/gradle-configure-project.html) · [Flutter 3.47.9 version checks](https://github.com/flutter/flutter/blob/3.47.9/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt)

Xcode **26.6** build **17F113** provides iOS SDK **26.5** and Apple Swift **6.3.3**, which supports Swift 5 language mode. CocoaPods **1.16.2** was used locally. Apple lists iOS **15.0** as Xcode 26.6's lower deployment target, and Flutter 3.47 lists iOS 15 as its minimum supported iOS runtime. [Apple Xcode requirements](https://developer.apple.com/xcode/system-requirements/) · [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms)

## Local evidence

Qualification used isolated copies of `development` at `af02295facc869d90b7abfb7d49f8722e313ed79` with the ADR-007 changes applied. Android builds used arm64 JDK **17.0.19**. The example lockfile was regenerated on Flutter 3.35.4 with only its Flutter SDK floor changing. Flutter 3.47.7 was run as a comparison. The official Flutter 3.47.9 archive was downloaded to temporary storage and verified against the release manifest checksum.

| Check | Flutter 3.35.4 / Dart 3.9.2 | Flutter 3.47.7 / Dart 3.13.5 | Flutter 3.47.9 / Dart 3.13.7 |
| --- | --- | --- | --- |
| Offline dependency resolution and analysis | Passed. Zero analyzer issues. | Passed. Zero analyzer issues. | Passed. Zero analyzer issues. |
| Flutter plugin and example widget tests | 63 plugin tests and 1 example widget test passed. | 63 plugin tests and 1 example widget test passed. | 63 plugin tests and 1 example widget test passed. |
| Android debug APK | Passed with Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20 and JDK 17. APK reports min SDK 24, compile SDK 36, and target SDK 36. | Passed with the same pins and APK metadata. Flutter warns that a future release will require newer Android tooling. | Blocked during dependency resolution. Gradle could not resolve the Maven hosts for Flutter engine artifacts. |
| Android native JVM test | 1 passed. | 1 passed. | Skipped after Android dependency resolution failed. |
| iOS simulator debug build | Passed with deployment target 15.0. Both simulator binary slices report minimum iOS 15.0. | Passed with the same deployment target. Flutter warns that a future release will require Swift Package Manager support. | Passed with deployment target 15.0. |
| Native XCTest on iOS 26.5 | 1 passed. | 1 passed. | Result unconfirmed. The temporary test logs were unavailable after the interrupted run. |
| Flutter version-call integration on iOS 26.5 | 1 passed after rebooting the simulator following XCTest. | 1 passed after rebooting the simulator following XCTest. | Xcode build finished. The integration result was unconfirmed after the interruption. |
| Android API 29 installation, launch, and version call | Passed. APK installed and the existing native version-call integration test passed. | Passed. APK installed and the existing native version-call integration test passed. | Skipped after Android dependency resolution failed. |
| iOS 15 installation, launch, and version call | Blocked. No iOS 15 simulator or device available. | Blocked for the same reason. | Blocked for the same reason. |

Android runtime checks used the official Google APIs ARM64 Android 10 image, API 29 revision 13, build `QSR1.211112.011`, with Android Emulator **36.6.11.0**. The emulator reported API 29 before the tests ran.

Xcode 26.6 reported that iOS 15.0 and 15.5 simulator images were unavailable for download in its catalog. The installed iOS 26.5 simulator can exercise version lookup. A deployment target in the built app does not establish that the app runs on that OS version.

## Feature-level availability

Compilation, app installation, and the availability of each signal have separate floors. In particular, Android API 36 is a build SDK. It does not require API 36 at runtime. Android screenshot callbacks start at API 34 and recording visibility starts at API 35. On iOS, UIKit's screenshot notification dates to iOS 7, bound-screen capture state to iOS 11, and the preferred scene trait to iOS 17. The approved plugin deployment floor is iOS 15. The installed Android SDK stubs confirmed the API 33/34 screenshot and 34/35 recording boundaries. The iOS 26.5 UIKit headers confirmed the notification, screen, and scene API floors. Older OS APIs do not extend the project qualification range.

| Runtime | Screenshot event | Initial capture state and changes | Widget masking | Full-window capture blocking | App-switcher privacy |
| --- | --- | --- | --- | --- | --- |
| Android 7–9 (24–28) | Unavailable | Unavailable | Outside planned qualification | OS primitive only | Outside planned qualification |
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

Android API 23 and below are below the declared installation floor. iOS 13–14 are below the approved deployment floor. Apple's release naming jumps from iOS 18 to 26. Android window controls and iOS overlays are optional proposals. All widget modes can run locally without detection. In the default policy an unavailable signal leaves protected fields masked.

## Android

- **API 34 screenshot callback.** Declare the install-time `DETECT_SCREEN_CAPTURE` permission. Register the callback with the visible Activity's lifecycle and use the main executor. Android 14 documents support for the designated hardware button combination and excludes ADB and instrumentation captures. Android notifies the user that detection occurred. The callback provides no image or pre-capture interception. Validate additional OEM methods independently. [Screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection).
- **API 35 recording visibility.** Declare `DETECT_SCREEN_RECORDING`. Register via `WindowManager.addScreenRecordingCallback`, use the returned current value, and remove the same callback at teardown. Visibility refers to activities of the registering UID included in recording. A transition to invisible can mean the app left the capture while recording continues. Validate full-display and single-app capture separately. Treat unsupported projection or sharing paths and inaccessible host state as limitations. Detection does not request MediaProjection consent. [WindowManager](https://developer.android.com/reference/android/view/WindowManager#addScreenRecordingCallback(java.util.concurrent.Executor,java.util.function.Consumer%3Cjava.lang.Integer%3E)), [permissions](https://developer.android.com/reference/android/Manifest.permission).
- **Window privacy.** `FLAG_SECURE` protects the flagged window on platform-supported screenshots and nonsecure displays. Android documents reliability limits on older devices, including API 30 and below. API 33 `setRecentsScreenshotEnabled(false)` is limited to the activity representation in Overview. [Secure activities](https://developer.android.com/security/fraud-prevention/activities), [Activity reference](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean)).

## iOS

- **Screenshot notification.** `UIApplication.userDidTakeScreenshotNotification` is available since iOS 7, arrives after capture, and supplies no payload or scene attribution. No permission prompt is required. [UIKit notification](https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification).
- **Continuous capture.** Prefer `traitCollection.sceneCaptureState` and trait observation on the bound host view from iOS 17. Preserve unspecified or unbound as unknown. On iOS 15–16 use the bound screen's `isCaptured` and `capturedDidChangeNotification`, available since iOS 11. Filter the notification to that screen. Apple marks `isCaptured` deprecated in favor of scene state, while the local iOS 26.5 header uses an unspecified deprecation version. This plan assigns no exact deprecation OS. API floors were cross-checked in UIKit SDK headers. No capture permission prompt is required. Signals can include mirroring, recording, or sharing and cannot reliably distinguish them. [Apple capture guidance](https://developer.apple.com/documentation/swiftui/protecting-sensitive-content-when-screen-sharing), [UIScreen.isCaptured](https://developer.apple.com/documentation/uikit/uiscreen/iscaptured), [change notification](https://developer.apple.com/documentation/uikit/uiscreen/captureddidchangenotification).
- **Scene lifecycle.** The example currently uses the legacy AppDelegate setup. Apple requires scenes on iOS 27 when built with the latest SDK. Validate example migration and embedded host view binding on Xcode 27 before declaring support. [Apple lifecycle guidance](https://developer.apple.com/documentation/UIKit/transitioning-to-the-uikit-scene-based-life-cycle).
- **App-switcher snapshots.** Cover the bound window synchronously with neutral content during the background transition. Verify the actual snapshot and foreground restoration per scene. [Apple QA1838](https://developer.apple.com/library/archive/qa/qa1838/_index.html).

## Remaining qualification

Verify installation, launch and the existing `getPlatformVersion()` integration test on iOS 15 using an iOS 15 device or a host with a compatible simulator. Repeat the Flutter 3.47.9 Android build and tests with access to the Flutter engine Maven artifacts. Rerun the iOS 26.5 native tests on Flutter 3.47.9 to obtain confirmed results. Android API 37 and Xcode 27/iOS 27 remain outside the local evidence. Signed device builds and physical capture behavior require separate evidence. Android manifest ownership remains in ADR-009.
