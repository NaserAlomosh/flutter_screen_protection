# FSP-017 — Selective capture research revalidation

Date: 2026-11-14. Status: **BLOCKED**. Recommendation: **NO-GO** for the full requested behavior.

## Specification and repository baseline

Read the complete 539-line attachment titled “FSP-016 — Android Selective Screenshot & Recording Protection Research” (stored as `Pasted text(20261114-200401).txt`). The repository already contained FSP-016, its isolated prototypes, tests, report, and capture evidence before this run. Per the specification's task-ID collision rule, this follow-up uses the next unused ID, FSP-017. The original report and evidence remain unchanged; this is not a claim to have authored or rerun that prior work.

Branch: `development`. HEAD: `e8f78b8de7219c5d1190969d930088361e535d5b`. The starting tree contained substantial tracked and untracked FSP-015/FSP-016 changes. No branch creation, commit, push, merge, publication, iOS modification, stable API change, or unrelated formatting was performed.

Reviewed project requirements, architecture, decisions, task register, implementation plan, security limitations, testing strategy, FSP-015 and FSP-016 reports, secure native rendering, Dart platform-view integration, screenshot observer lifecycle, and research implementation/tests. Native security uses `SurfaceView.setSecure(true)` before attachment and Canvas drawing into that surface. Flutter uses explicit Hybrid Composition (`initExpensiveAndroidView` and `AndroidViewSurface`). No application-window `FLAG_SECURE` setter was found in the Android/Dart implementation.

## Baseline and root cause

The retained Samsung recorder logs contain error `-50004` and `Secure layer detected. Screenshot failed` for default, media-overlay, and on-top variants. These are evidence of capture-client rejection associated with secure surfaces. They do not establish Samsung's proprietary implementation or prove that every possible window composition is rejected. The physical-button screenshot refusal is a user-supplied historical observation, not a physical test performed in this run.

The secure-layer boundary is the strongest candidate for excluding pixels without putting a sensitive copy into Flutter's ordinary buffer. Changing Z-order changes composition, not the security policy of the capture client. Successful ADB capture does not satisfy successful physical-button capture. Black rectangles also do not establish the requested asterisk replacement.

Public contracts rechecked: [SurfaceView](https://developer.android.com/reference/android/view/SurfaceView) and [WindowManager recording observation](https://developer.android.com/reference/android/view/WindowManager). The latter reports recording visibility; it does not specify a pre-encoder masking barrier. The full API/candidate investigation, API floors, unsupported paths, and alternative-window limitations remain in [FSP-016](FSP-016_SELECTIVE_CAPTURE_RESEARCH.md#public-api-investigation).

## Experiments and evidence

| Experiment | Implementation / APIs | Retained device results | Current assessment |
| --- | --- | --- | --- |
| A: secure compositions | Debug native Canvas SurfaceView, `setSecure(true)`, default / `setZOrderMediaOverlay(true)` / `setZOrderOnTop(true)`; Hybrid Composition | Samsung SM-S936B API 36: ADB outputs exclude fields; built-in recorder rejects all three. Limited API 34/35 emulator evidence exists. API 29 safely unavailable. | FAIL for native recorder requirement; physical Samsung screenshots BLOCKED. No fresh device execution. |
| B: input diagnostics | `dispatchKeyEvent`, metadata-only receipt logs; delegates unchanged to superclass | Historical injected volume events verify instrumentation only | NO-GO as a guaranteed pre-capture mechanism; physical input sequence BLOCKED. No masking on volume keys added. |
| C: recording reaction | API 35+ `addScreenRecordingCallback`, initial return value, generation-fenced removal, Flutter replacement of fixed synthetic fixtures | Samsung admits recording, but retained recording 2 first-frame image exposes both values. Historical ADB recording also exposes values. | FAIL for secure recording; best effort only. Lifecycle fix below does not repair first-frame exposure. |
| D: other rendering | Public API review; no speculative production implementation | Separate windows and alternative texture arrangements remain NOT TESTED | No evidence justifying production use. Hidden SurfaceControl methods, privileged capture bypasses, and unprotected sensitive fallback remain excluded. |

No new device/OS compatibility is claimed. Existing Android 10/14/15/16 findings are historical and scoped as described in FSP-016. Repeated physical screenshots, full landscape acceptance, Activity recreation, hot restart, and new-build recording transitions remain pending.

Verified all **47** files in `docs/evidence/FSP-016/MANIFEST.sha256` against their hashes. This verifies retained-file integrity, not the truth of every historical claim. Visually inspected [recording 2 first frame](evidence/FSP-016/recording-callback-2-first.png): both fixture values are readable and the displayed recording state is 0. The [original MP4](evidence/FSP-016/recording-callback-2.mp4) is retained; it was not freshly decoded in this run. Re-read the [recorder rejection log](evidence/FSP-016/media-recorder.txt) and [top-layer rejection log](evidence/FSP-016/top-recorder.txt).

## Implementation change

The existing C harness cleared state on Flutter inactivity, but still accepted a late native state-0 callback while inactive. Native registration lasts until Activity `onStop`, leaving an interval in which this could reveal the ordinary synthetic text again.

Added an explicit foreground guard initialized from Flutter's lifecycle state. Recording callbacks are accepted only while foregrounded and in recording mode; rendering also requires foreground state. Resume still requests a new native observation. Extended the lifecycle widget regression to inject state 0 after inactivity and require the fixture to remain absent.

This is bounded research-harness hardening, not a secure capture solution. The diagnostic transport still lacks end-to-end session identifiers for already-enqueued packets crossing a rapid resume/mode transition. Do not promote it to a production API. Even a complete transport redesign would not provide Android's missing first-frame synchronization contract.

## Verification in this run

| Check | Result |
| --- | --- |
| Direct configured Dart 3.9.2 analyzer, `dart --suppress-analytics analyze` | PASS: no issues after the change |
| Changed Dart files, `dart --suppress-analytics format --output=none --set-exit-if-changed ...` | PASS: 2 files, 0 changes |
| Whole-repository format check | FAIL: five pre-existing files need formatting; output-only mode wrote nothing |
| Evidence SHA-256 verification | PASS: 47/47 |
| `git diff --check` | PASS |
| `flutter analyze` | BLOCKED before analysis: SDK `engine.stamp` write denied |
| Package Flutter tests, including direct flutter-tools snapshot attempt | BLOCKED before tests: SDK `engine.stamp` / `lockfile` writes denied |
| Example Flutter tests | BLOCKED before tests: SDK cache write denied |
| Android plugin and example JVM tests, debug research APK via Gradle | BLOCKED before tasks: Gradle distribution lock write denied |
| Research APK via Flutter | BLOCKED before build: SDK cache write denied |
| ADB device inventory | BLOCKED: local smart-socket listener denied (`Operation not permitted`) |
| Fresh physical-device tests | BLOCKED: no ADB access and no physical operator in this run |

**Executed test-case count this run: 0.** The strengthened regression is not execution-verified. Historical FSP-016 counts (76 package, 12 example, 24 plugin JVM, 7 example JVM) are not current passes. Initial direct Dart commands also hit a telemetry-file permission error after printing results; rerunning with the supported `--suppress-analytics` option completed analysis and changed-file formatting successfully.

The five pre-existing formatting failures are `example/integration_test/plugin_integration_test.dart`, `lib/flutter_screen_protection_method_channel.dart`, `lib/flutter_screen_protection_platform_interface.dart`, `test/flutter_screen_protection_method_channel_test.dart`, and `test/flutter_screen_protection_test.dart`. They were left untouched.

## Changed files in this run

- Modified `example/lib/main_research.dart`: foreground/mode guards and formatting of those edits.
- Modified `example/test/capture_research_test.dart`: late-background callback regression assertion.
- Created `docs/FSP-017_SELECTIVE_CAPTURE_REVALIDATION.md`: this report.
- Appended FSP-017 entry to `TASKS.md`.
- Appended follow-up qualification scope to `IMPLEMENTATION_MASTER_PLAN.md`.

All other working-tree modifications predate this run. The FSP-016 report, native prototype variants, recording probe, debug manifest, evidence, public package API, and iOS code were preserved.

## Next implementation and manual qualification

Keep the isolated prototypes and do not ship a guaranteed `SensitiveContent` capture API. First rerun the automated suites and debug build in an environment permitted to use the configured Flutter/Gradle caches and local test sockets. Then complete the existing physical qualification procedure; no additional speculative rendering workaround is justified by the evidence.

From `example/`, build `flutter build apk --debug -t lib/main_research.dart`, install the debug APK, and explicitly launch `com.naseralomosh.flutter_screen_protection_example/.CaptureResearchActivity`. For FSP-015/default/media/top:

1. Confirm both synthetic values are visible on the physical Samsung and the transaction is within the viewport.
2. Press physical Power + Volume Down. Record any refusal toast verbatim. Confirm a new actual image was saved; retain its real format and filename.
3. Inspect that exact saved file for both values and surrounding Flutter UI. Do not substitute ADB screencap.
4. Repeat ten times in portrait/landscape and after background/foreground, Activity recreation, region replacement, and hot restart.
5. Try Samsung's built-in recorder, full-screen and app-only separately. Inspect each saved MP4 from its first frame through transitions and the final frame. One leaked frame is FAIL.
6. For input diagnostics, compare volume alone, power alone, both chord orders, and gestures. Do not infer physical ordering from injected ADB events.

Both FSP-016 and FSP-017 remain BLOCKED. **NO-GO** means no tested approach meets the unchanged primary requirement; it is not an impossibility claim about every future Android/OEM implementation.
