# Testing strategy

## Automated checks

| Layer | Required cases |
| --- | --- |
| Dart unit | Version-call regression, typed codec and invalid schema, UTC timestamps, generation and sequence handling, state before listeners, ordered initial snapshot, multiple listeners, concurrent initialization, channel failure, retry and idempotent disposal. |
| Flutter widget | Mode changes, mask and replacement omit child, blur clips and suppresses semantics and input, always-mask and unsupported fallback, keyboard focus and selection, multiple fields, controller swap, disposal, layout and rebuild counts. |
| Android Kotlin | API gates at 33/34 and 34/35, callback registration and removal, initial return value, duplicate suppression, permission or registration failure, stopped and resumed Activity, configuration changes, stale callbacks and EventChannel cancel/reattach. Test existing flag preservation and overlapping leases if enabled. |
| iOS XCTest | Main-thread observation, screenshot notification with no payload, bound-screen filtering, trait and legacy availability branches, initial capture read, unspecified state, repeated background/foreground, disconnect/rebind and stream cleanup. Test overlay lifecycle if enabled. |
| Integration and CI | Run Dart analysis, Flutter suites, Android and iOS native suites, and example build/integration smoke on both platforms. Inject fake capture states to verify end-to-end presentation. Retain platform versions and test results. |

Simulators and mocks can validate control flow and codecs. ADB screen capture commands and instrumentation screenshots are outside Android 14’s documented callback path.

## Physical qualification

| Device band | Required evidence |
| --- | --- |
| Android 10–13 | Test fallback at floor API 29 and Recents boundary API 33 if offered. Check secure-window behavior on an older device and a supported recent device if shipped. |
| Android 14 | Verify physical screenshot gesture, user notice and unsupported recording state. Record behavior with ADB separately as an excluded path. |
| Android 15–17 | Exercise API 35 and current API 37 hardware. Add API 36 and representative non-Pixel OEM coverage. Test recording visibility in full-display and single-app capture. |
| iOS 15–16 | Exercise the legacy screen path on available physical hardware, including recording already running at launch. Verify the claimed floor or qualify it explicitly. |
| iOS 17–18 and 26–27 | Exercise the scene path at its boundary and on current hardware. Include mirroring where available and test the latest SDK scene lifecycle. |

For supported paths, take a screenshot, start and stop recording, background and foreground, rapidly navigate between protected screens, rotate or rebind where supported, and relaunch during active capture. Exercise multiple protected widgets and compare what the user sees with the first and later captured frames. If optional policies ship, test output with the policy off and on, across route changes, with a pre-existing Android flag, and with task-switcher snapshots inspected separately. Verify no stale value appears on startup or resume while state is unknown. Capture metadata only in logs.

Record build SHA, device model, OS build, capture method, expected versus actual state and output, and any timing or uncovered paths. Use synthetic data in retained evidence. Release review requires documented outcomes for boundary and current devices, and approved claim changes for gaps. No physical-device or implementation tests were run in this planning phase.

## FSP-002 Android screenshot validation

Automated checks use the shared v1 fixtures and the real Flutter message codecs. The Kotlin suite mocks the Android Activity and invokes the callback captured at registration. It checks API gating, snapshot order, permission failure, registration and removal exceptions, transport failure, Activity stop and restart, configuration rebinding, stale callbacks and stream cancellation. Dart channel tests verify that repeated initialization and multiple listeners share a subscription and that screenshot delivery preserves continuous-capture state.

| Check | Result |
| --- | --- |
| Flutter 3.35.4 and Dart 3.9.2 | Pub resolution, formatting of changed Dart files, and package and example analysis passed. 66 package tests and one example widget test passed. |
| Android build and JVM tests | Debug APK, Kotlin compilation and Android lint passed under ADR-007. Lint reported dependency-version warnings. All 12 Android JVM tests passed, including version lookup. |
| Manifest merger | Debug and release merge reports trace `DETECT_SCREEN_CAPTURE` to the library. The debug APK declares it. A higher-priority debug manifest with `tools:node="remove"` removed it from the merged manifest and APK. |

Runtime evidence used Android Emulator 36.6.11.0 and the example debug app built from the FSP-002 changes over `114e66b278a424e3ae1f988c921963edd113bc51`.

| Runtime | Result |
| --- | --- |
| API 29 · `QSR1.211112.011` | Two integration tests passed. The app installed and ran, screenshot capability reported `unsupportedOs`, and native version lookup worked. |
| API 31 · `SE1A.220203.002.A1` | Two integration tests passed. Screenshot capability reported `unsupportedOs`, and native version lookup worked. |
| API 34 · `UE1A.230829.050` | Two integration tests passed. Android granted the merged permission, saved a System UI screenshot triggered by a simulated Power and Volume Down chord, and delivered `ScreenshotTaken` to Flutter. Continuous-capture state stayed unsupported. |
| API 34 · host permission removed | One integration test passed. Screenshot capability reported `permissionMissing` and state stayed unknown. |
| API 35 · `AE3A.240806.043` | Two integration tests passed. Android saved a System UI screenshot triggered by a simulated Power and Volume Down chord, and Flutter received `ScreenshotTaken`. Continuous-capture state stayed unsupported. |

Run the device test from `example/`. Use `unsupported` for API 33 and below, `supported` for API 34 and above with the default manifest, or `permissionMissing` with the permission removed.

```sh
flutter test integration_test -d DEVICE_ID --dart-define=FSP_SCREENSHOT_EXPECTED=supported
```

For capture delivery, add `--dart-define=FSP_TAKE_SCREENSHOT=true` on API 34+. Wait for `FSP_SCREENSHOT_READY`, then use the Android screenshot button combination. The test requires an activity-scoped `ScreenshotTaken` event and verifies that continuous-capture state is unchanged. Record the Android build, screenshot trigger, system notice and EventChannel result. The API 34 and 35 emulator runs used `adb shell input keycombination -t 350 KEYCODE_VOLUME_DOWN KEYCODE_POWER` to exercise the system screenshot path. The OS saved a screenshot file in each run. The physical gesture and the user-facing system notice remain unverified.
