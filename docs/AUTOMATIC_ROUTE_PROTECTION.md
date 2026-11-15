# Automatic route protection verification

## Architecture change

The pre-existing observer sent asynchronous policy messages but could not prevent Flutter from drawing before a reply. `protectNavigation` solved this only when callers modified each navigation operation. This change retains the existing Kotlin FLAG_SECURE implementation and policies, and adds a single root paint gate exposed as `FlutterScreenProtection.builder`.

Required setup: initialize once, install the builder and observer on one root Navigator, and preserve stable route names. Existing pushNamed, pop, pushReplacementNamed, screens and route factories remain unchanged. The example no longer calls the per-operation guard. The optional legacy helper and its passing tests remain available.

The gate suppresses Navigator layers until the latest required native protection has succeeded. It also suppresses pointer hit testing and subtree semantics while closed; widgets may still build, lay out and receive programmatic updates. Native failures leave the gate closed. Request revisions prevent stale replies from opening it. Outgoing route completion and gesture state retain protection during transitions; an engine FrameTiming report for an allowed painted frame is required before native allowance. A missing timing report fails closed. A cancellable repaint retry requests another safe frame while acknowledgement is pending; it stops on acknowledgement, supersession or detach. This fixes an intermittent idle-release stall observed during emulator removal/pop tests. The retry never clears protection by elapsed time.

Guarantee boundary: Flutter pixels inside this root gate, using one observed Navigator and conforming TransitionRoute-based Flutter routes. Native platform views, external windows, arbitrary nested Navigator state and routes that violate opacity contracts are not covered. Android window/compositor behavior remains subject to the platform; sampled screenshots do not prove every physical OEM or every possible inter-frame timing.

## Automated tests

Original plugin tests remain unchanged. New tests inspect paint counts and actual render-boundary pixels under delayed acknowledgements, cached route reveals, native failures, stale replies, backend/list updates, restoration, system back and predictive gesture commit/cancel. Widget tests explicitly synthesize raster timing reports because their fake binding has no raster thread; emulator tests use actual engine reports.

## Emulator method

New results are separate from the earlier baseline, under `docs/evidence/AUTOMATIC_ROUTE_PROTECTION/api-N/`.

The automatic integration test repeats the baseline policy/lifecycle matrix using the root builder and ordinary navigation calls. Additional tests take three ADB screenshots per transition while animations are in flight. The test-only ValidationActivity can delay or reject native secure requests. For delayed/error gate samples, verification requires a real black PNG **and FLAG_SECURE off**, demonstrating that the Flutter gate itself withholds protected content. Protected content uses a distinct red marker; allowed Home uses green. Both markers are checked for leakage.

API 34+ predictive tests inject Android-to-Flutter `flutter/backgesture` start/progress/cancel/commit messages through a debug-only native channel and the real Flutter predictive transition handler. This validates the predictive callback/rendering path; it is separate from a physical edge-gesture qualification. The runner also enables gestural navigation before launch and injects an actual Android edge swipe. That probe requires a Flutter user-gesture callback, captures three in-flight frames with no protected red pixels, and verifies the committed protected destination. The retained-engine lifecycle harness refreshes framework back registration before this probe. It is not a physical-handset qualification. API 29–33 do not claim native predictive-progress validation. All APIs exercise ordinary system back using ADB KEYCODE_BACK.

Native delay/failure injection and predictive-message injection exist only in the debug validation Activity, not in the plugin or release application. Original settled-screen ADB and System UI screenshot checks are retained. Evidence includes PNGs or explicit capture refusals, window state, logcat and SDK identity. First-frame correctness also has deterministic widget tests; finite emulator screenshots cannot exhaust all frame timings.

## Current results

Final corrected build: **467 / 467 emulator checks PASS**, including **159 in-flight capture samples** and **81 real neutral-frame PNGs with native FLAG_SECURE off**. No failed or inconclusive checks remain in the final matrix. Earlier diagnostic attempts are preserved under `evidence/AUTOMATIC_ROUTE_PROTECTION/attempts/` as archives, with the idle-release VM state trace alongside them.

| Android API | Checks | In-flight capture samples | OS predictive edge gesture | Result |
|---|---:|---:|---|---|
| 29 | 47 | 15 | Not applicable | PASS |
| 30 | 47 | 15 | Not applicable | PASS |
| 31 | 47 | 15 | Not applicable | PASS |
| 32 | 47 | 15 | Not applicable | PASS |
| 33 | 47 | 15 | Not applicable | PASS |
| 34 | 58 | 21 | PASS | PASS |
| 35 | 58 | 21 | PASS | PASS |
| 36 | 58 | 21 | PASS | PASS |
| 37 | 58 | 21 | PASS | PASS |

Flutter plugin tests: **13 passed** (original tests retained); example widget test: **1 passed**; Kotlin/JVM tests: **2 passed**. Static analysis reports no issues. The integration APK and normal example debug APK both build successfully. Original production Kotlin code and original policy test sources were not changed.

The matrix covers ordinary named push/pop/replacement/removal, global precedence, runtime route lists, rapid changes, native delay/error recovery, system back, Activity recreation, foreground/background and orientation. Restoration is covered by automated Flutter tests. API 34–37 also pass predictive callback cancellation/commit and actual OS edge-swipe checks. Each final emulator run records the same test APK SHA-256 in `run.json`.

- [Machine-readable summary](evidence/AUTOMATIC_ROUTE_PROTECTION/summary.json)
- [Independent neutral-frame pixel audit](evidence/AUTOMATIC_ROUTE_PROTECTION/pixel-audit.json)
- [Tested source hashes](evidence/AUTOMATIC_ROUTE_PROTECTION/source-sha256.json)
- [API 29 delayed-entry screenshot](evidence/AUTOMATIC_ROUTE_PROTECTION/api-29/delayed_push_first_frames-0.png)
- [API 36 native-failure gate screenshot](evidence/AUTOMATIC_ROUTE_PROTECTION/api-36/native_failure_gate-0.png)
- [API 36 OS gesture results](evidence/AUTOMATIC_ROUTE_PROTECTION/api-36/results.json)

Diagnostic `releaseWaitSeconds` / `settledCheckSeconds` fields include ADB capture overhead; they are not release-latency benchmarks.


## Reproduce

```sh
flutter test
flutter analyze
(cd example && flutter test)
(cd example && flutter build apk --debug --target integration_test/automatic_navigation_test.dart)
# Keep this test APK separate from the interactive example build.
cp example/build/app/outputs/flutter-apk/app-debug.apk /private/tmp/fsp-automatic.apk
# Repeat with installed arm64-v8a system images for APIs 29 through 37.
/private/tmp/fsp-validation-venv/bin/python tool/validate_android.py 35 \
  --image 'system-images;android-35;google_apis;arm64-v8a' \
  --apk /private/tmp/fsp-automatic.apk \
  --evidence-dir docs/evidence/AUTOMATIC_ROUTE_PROTECTION
```

The driver requires Pillow, the Android SDK, an installed system image, and a free emulator port 5580/HTTP forward 8876. It creates and removes only its temporary test AVD. Run sequentially. API 37's image identifier is `android-37.0`; verify actual `ro.build.version.sdk`, as the driver does.

Settled screenshots allow 1.5 seconds for batched engine raster reports and native flag application after `pumpAndSettle`. Transition samples do not use this delay. Initial attempts exposed both too-early settled captures and an idle-release stall (a painted safe frame with no matching raster report). The latter was fixed with a cancellable safe-frame repaint retry. Attempts before that fix are retained separately and are not counted as successful final runs. Settled allowance also has a bounded, recorded native-clear wait; a timeout still fails the capture check.

## Scope of qualification

The emulator builds use Flutter 3.35.7 / Dart 3.9.2 in debug mode on arm64 system images. Navigator 1.0 is exercised directly. Navigator 2.0/go_router setup is an explicit integration contract, not a separately executed router-version matrix. Nested navigators are not automatically aggregated. Native platform views, multiple engines sharing a window, physical OEM capture behavior and exhaustive per-frame compositor timing remain outside this qualification.
