# Testing strategy

## Automated checks

| Layer | Required cases |
| --- | --- |
| Dart unit | Version-call regression, typed codec and invalid schema, UTC timestamps, generation and sequence handling, state before listeners, ordered initial snapshot, multiple listeners, concurrent initialization, channel failure, retry and idempotent disposal. |
| Flutter widget | Mode changes, mask and replacement omit child, blur clips and suppresses semantics and input, always-mask and unsupported fallback, keyboard focus and selection, multiple fields, controller swap, disposal, layout and rebuild counts. |
| Android Kotlin | API gates at 33/34 and 34/35, callback registration and removal, initial return value, duplicate suppression, permission or registration failure, stopped and resumed Activity, configuration changes, stale callbacks and EventChannel cancel/reattach. Test existing flag preservation and overlapping leases if enabled. |
| iOS XCTest | Main-thread observation, screenshot notification with no payload, bound-screen filtering, trait and legacy availability branches, initial capture read, unspecified state, repeated background/foreground, disconnect/rebind and stream cleanup. Test overlay lifecycle if enabled. |
| Integration and CI | Run Dart analysis, Flutter suites, Android and iOS native suites, and example build/integration smoke on both platforms. Inject fake capture states to verify end-to-end presentation. Retain platform versions and test results. |

Simulators and mocks can validate control flow and codecs. ADB and instrumentation screenshots cannot establish Android 14 screenshot callback support.

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
