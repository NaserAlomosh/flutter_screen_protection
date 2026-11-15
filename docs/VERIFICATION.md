# Android rebuild verification

Historical rebuild baseline. The navigation integration described here is superseded by [automatic root protection](AUTOMATIC_ROUTE_PROTECTION.md); the current root integration does not require per-call navigation guards.

Completed 14–15 November 2026 (Asia/Amman): all nine API levels 29–37 executed, with 225/225 recorded emulator checks PASS. No commit, push, merge or publication is part of this task.

## Scope and recovery

The package now exposes global screenshot policy and named-route screenshot policy only. Android uses FLAG_SECURE. The former capture streams, callbacks, capability models, native secure text/surfaces, platform views, research dashboard and iOS plugin were removed. Historical documents were moved to `docs/archive` and excluded from the published package.

Before removals, all tracked and nonignored untracked files were archived and the archive was reopened successfully (165 files). Recoverable backup: `.rebuild-backup/flutter-screen-protection-backup-20261114-232830/worktree.tar.gz` (also retained in `/private/tmp/flutter-screen-protection-backup-20261114-232830/`), with `tracked.patch` and `status.txt` alongside. Extract into a separate directory to inspect or restore individual files. Branch remains `development`.

## Toolchain

Apple Silicon arm64 Mac; Flutter 3.35.7 / Dart 3.9.2; JDK 17; Kotlin 2.2.20; AGP 8.11.1; compile SDK 36; minimum SDK 29. ADB 37.0.0. Initial emulator version 36.6.11. SDK package installation upgraded the emulator to 37.2.13 for newer image dependencies. API 29/31/34/35 used 36.6.11; API 30 and subsequent runs use 37.2.13. Each boot log records its actual version.

Initial sandbox restrictions prevented Flutter cache writes and emulator host inspection. The same commands succeeded with approved local execution access. Real local SDK, Gradle and emulator execution are used.

## Automated checks

- PASS — Flutter policy tests: four test groups covering policy precedence, updates, transitions, delayed native acknowledgement, cancellation, restored routes, nonopaque overlays, unnamed/empty names and error propagation.
- PASS — Kotlin JVM tests (two tests): method-channel validation, initial secure state, detach/reattach, disposal, ordered rapid updates and queued main-thread operations.
- PASS — example widget test (one test), including visible backend switch state.
- PASS — Flutter analysis, dependency resolution, clean debug APK build and `git diff --check`.
- Generated caches were cleared after an artifact audit found old release-build outputs. The clean debug libraries contain no obsolete capture/secure-region classes; see `native-artifact-check.txt`.
- See logs under `docs/evidence/ANDROID_API_29_37` for current results.

Full AOSP images are used for the missing API 32/33/36/37 targets to conserve disk space. ATD downloads were cancelled without using them for validation: [Android documents](https://developer.android.com/studio/test/managed-devices) that ATD removes System UI and disables hardware rendering.

## Emulator method

`example/integration_test/policy_test.dart` runs a real Flutter UI with an identifiable background and route label. `tool/validate_android.py` creates only dedicated `FSP_REBUILD_*` AVDs in `/private/tmp/fsp-rebuild-avds`, boots them sequentially, verifies `ro.build.version.sdk`, installs the integration APK, and captures the composed display with `adb exec-out screencap -p`.

The app waits at each scenario until the external runner acknowledges capture through an ADB-forwarded loopback HTTP connection. The integration binding renders continuously so external back, recreation and orientation events can produce frames. The debug-only ValidationActivity retains the Flutter engine across explicit `recreate()` calls. Both allowed and blocked lifecycle states are exercised. Saved allowed-orientation screenshots for every API level were also checked for a real portrait-to-landscape dimension change (1080×1920 to 1920×1080).

Allowed captures must contain the visible marker across more than 25% of pixels. Blocked captures must omit it, or return no pixel data with the Activity's SECURE flag confirmed; matching allowed captures establish that the capture path works. Some Android images return success and zero bytes when SurfaceFlinger refuses protected capture. Logs record this separately from a black PNG. Empty files are not valid screenshot images and are retained only as raw command output evidence.

System UI KEYCODE_SYSRQ is a separate path: saved screenshots are pulled from Pictures/Screenshots and inspected. The runner waits for the previous allowed screenshot's System UI thumbnail to disappear before testing protected content. A saved thumbnail of previously allowed Home is not evidence of protected Transfer content leaking.

Earlier harness attempts are retained under `attempts/`: they include false negatives caused by treating zero-byte secure captures as invalid PNGs, screenshot-thumbnail interference, and a test binding that paused rendering during external lifecycle operations. They are not final compatibility results.

## Reproduce locally

From `example`, build the test APK with `flutter build apk --debug -t integration_test/policy_test.dart` and copy it to `/private/tmp/fsp-validation.apk`. From the repository root, run the runner using Python with Pillow installed:

```sh
python3 tool/validate_android.py 35 --image 'system-images;android-35;google_apis;arm64-v8a'
python3 tool/summarize_validation.py
```

Install the selected image with sdkmanager first. Set ANDROID_HOME if the SDK is not under `~/Library/Android/sdk`. The runner uses emulator port 5580 and an ADB-forwarded HTTP acknowledgement port 8876, and removes only its dedicated temporary AVD after execution. Use `--apk` to select another built validation APK. Build the normal example again without `-t` for interactive demonstration.

## Limits

The observer handles navigation state automatically but cannot synchronously await Android before Flutter draws a newly sensitive route. Use `protectNavigation` before such navigation (including guarded back/deep-link actions), or keep the global policy blocked. Native startup protection requires the documented pre-super.onCreate FLAG_SECURE initialization. One root Navigator/engine is supported; nested navigation is not automatically aggregated.

Emulator results do not establish behavior on every physical OEM device. Frame-by-frame transition capture and physical-button screenshot combinations are separate from the settled-screen ADB and injected System UI tests.

<!-- MATRIX -->
## Executed emulator matrix

| API | Image | ADB checks | System UI checks | Result |
|---|---|---|---|---|
| 29 | Google APIs ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-29/results.json) |
| 30 | Google APIs ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-30/results.json) |
| 31 | Google Play ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-31/results.json) |
| 32 | AOSP ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-32/results.json) |
| 33 | AOSP ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-33/results.json) |
| 34 | Google APIs ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-34/results.json) |
| 35 | Google APIs ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-35/results.json) |
| 36 | AOSP ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-36/results.json) |
| 37 | AOSP ARM64 | PASS (23/23) | PASS (2/2) | [PASS](evidence/ANDROID_API_29_37/api-37/results.json) |
