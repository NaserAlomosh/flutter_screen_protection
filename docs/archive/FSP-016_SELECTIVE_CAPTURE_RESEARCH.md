# FSP-016 — Android selective capture research

**Date:** 2026-11-09. **Status:** BLOCKED on primary physical-button qualification; **recommendation: NO-GO for the full requirement**. No tested architecture satisfies all acceptance criteria on Samsung SM-S936B. Do not promote these experiments to a stable protection API.

## Objective and decision

Keep real fields visible locally, automatically hide only those fields in ordinary hardware-button screenshots and native recordings, and preserve successful capture of surrounding Flutter UI. No whole-window secure flag, manual privacy action, after-capture redaction, privileged API, or insecure fallback is acceptable.

Secure surfaces remain the strongest public candidate for keeping sensitive pixels out of ordinary capture. However, Samsung rejected its recorder for **all three tested compositions**. Reactive recording masking allowed Samsung recording, but the saved second recording **exposes both values in its first decoded frame**. Shell recording also exposed both values while the recording callback state remained inactive. Neither mechanism meets the combined requirement.

Physical buttons could not be pressed remotely. The operator connected the phone but subsequently confirmed they were away from the office. ADB injection is not a replacement for that test. The user reports that FSP-015 physical screenshots were blocked; this report records that as supplied evidence, not a newly observed hardware test.

## Repository audit and baseline

- Branch `development`; HEAD `e8f78b8de7219c5d1190969d930088361e535d5b`. No branch, commit, push, merge, or publication performed.
- FSP-016 was unused. FSP-015 already occupied its own task and remains unchanged.
- Audited requirements, implementation plan, task register, decisions, architecture, security limitations, FSP-015 report, plugin/native observer, SecureText/platform-view code, and existing Android/Dart/example tests.
- Existing documentation contains older cross-platform planning. This research adds Android-only code and does not rewrite that historical plan or modify any iOS source.
- Pre-existing work: 11 tracked modified files and 5 untracked FSP-015 files. The initial patch and hashes were captured in `/tmp/fsp016/preexisting.patch` and `preexisting-untracked.json`. Existing code changes were preserved; only append-only FSP-016 entries were added to the two shared planning files.
- Baseline: package analysis PASS; 76 package tests PASS; 6 example tests PASS; 24 Android JVM tests PASS; debug example APK PASS. Configured Flutter 3.35.7 / Dart 3.9.2, compile SDK 36, AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, JDK 17, JVM target 11.

### Exact FSP-015 APIs and lifecycle

Dart uses `PlatformViewsService.initExpensiveAndroidView`, `AndroidViewSurface`, the platform-view registry, and per-view `MethodChannel`. Native code uses `SurfaceView.setSecure(true)`, `SurfaceHolder.Callback2`, `lockCanvas`, `Canvas.drawColor/drawText`, and `unlockCanvasAndPost`. Security is configured on the unattached view before drawing. No sensitive copy is drawn into Flutter. Standard below-window ordering uses the SurfaceView hole-punch path. Values and errors are excluded from diagnostics; disposal removes callbacks/handlers, hides the surface, and clears content.

The plugin gates creation at API 34 even though `setSecure` exists from API 17. API 29 is deliberately unavailable. Its `Active` state means a buffer was posted, not that capture compatibility or visible appearance has passed.

Screenshot observation uses `Activity.registerScreenCaptureCallback`/`unregisterScreenCaptureCallback`, `mainExecutor`, `DETECT_SCREEN_CAPTURE`, `ActivityAware`, `FlutterLifecycleAdapter`, and a started Activity lifecycle. Session generations fence stale callbacks. It is **after capture**, independent of secure rendering, and cannot redact the current screenshot. Existing channel/controller tests cover malformed data, ordering, retries, cancellation, lifecycle invalidation, and hot-restart cancellation.

**No application-window `FLAG_SECURE` setter exists in the audited Kotlin/Dart implementation or these additions.** The research also does not clear someone else's secure flag. A secure child surface is distinct from a secure Activity window.

### Samsung refusal: established facts versus inference

The historical FSP-015 report records built-in-recorder preflight error `-50004`, `Secure layer detected. Screenshot failed`, with no saved recording; removing secure regions allowed recording. Fresh FSP-016 tests reproduced that refusal at 14:01:58 (default), 14:02:39 (media-overlay), and 14:03:06 (on-top), device local time. ADB captures on the same phone saved successfully and excluded both regions.

This establishes a Samsung recorder preflight rejection associated with secure layers, not a Flutter whole-window flag. The most plausible explanation for the supplied hardware-screenshot refusal is a related Samsung capture-side policy. **The exact proprietary screenshot implementation, its traversal of every possible layer/window, and its handling of all capture scopes are UNVERIFIED.** AOSP source is not proof of Samsung internals. Three Z-order results do not prove that every conceivable window arrangement fails.

## Public API investigation

| Candidate | Mechanism and API floor | Partial exclusion / capture success | Decision |
| --- | --- | --- | --- |
| Secure SurfaceView | API 17; distinct compositor surface marked secure before attachment; native Canvas produces its pixels | Can exclude only that layer; successful overall capture is capture-client/OEM dependent | Best security candidate; Samsung recorder FAIL in all tested variants |
| SurfaceView media-overlay / on-top | Public Z-order setters, API 5; changes relative composition, not security | Same secure layer remains present; no promise to bypass capture preflight | Implemented as isolated A variants; recorder FAIL |
| Separate application child window / dialog | Put secure content in another window/surface | No public guarantee that full-display Samsung preflight ignores the secure window. App-only capture has different scope. Window-wide security of a small window is not a documented capture-client exemption | NOT TESTED; no production implementation justified by evidence |
| TextureView | API 14; texture composited into ordinary view/window rendering | No public per-TextureView secure exclusion equivalent; sensitive pixels can enter the ordinary captured window | NO-GO for unprotected values |
| Flutter texture/virtual-display composition | Copies/composes platform view output through different paths | Cannot assume secure BufferQueue metadata survives an ordinary Flutter texture. Z-order and security are not interchangeable | Not used as an insecure fallback; NOT TESTED |
| SurfaceControl | Public class API 29 supports composition transactions | SDK 36 source marks `Builder.setSecure` and `Transaction.setSkipScreenshot` with `@hide`; Java `public` in framework source does not mean public SDK API | Hidden techniques excluded; no public general capture-excluded layer API identified |
| View content sensitivity | API 35 `setContentSensitivity(SENSITIVE)` | Marks the **hosting window** secure during MediaProjection, not just the view; does not solve screenshot replacement | NO-GO for preserving ordinary content in that window |
| New SurfaceView composition ordering | Newer SDK/reference `setCompositionOrder` refines Z-order | Does not establish a new exclusion policy or override recorder admission | No SDK upgrade or speculative implementation |
| Protected graphics buffers / DRM paths | Hardware-protected producer/consumer pipelines are distinct from screenshot exclusion | Not an arbitrary Canvas/Flutter text redaction facility, and not a Samsung capture-admission guarantee | No credible production solution for this task |
| Screenshot callback | API 34 Activity notification | Delivered after supported capture; not a pre-capture fence | Observation only |
| Recording visibility callback | API 35 `WindowManager.addScreenRecordingCallback` and removal; `DETECT_SCREEN_RECORDING` normal permission | UID visibility state and initial return value; asynchronous observation, no first-frame barrier | C experiment; best effort only, observed leakage |
| Input events | `Activity.dispatchKeyEvent`; Volume Down may be delivered | System handles screenshot chords upstream; Power delivery and screenshot gestures cannot be assumed; no render/capture synchronization | Diagnostic only; NO-GO as guaranteed protection |

Sources checked against installed SDK 36 source/stubs and current public documentation:

- [SurfaceView security and composition](https://developer.android.com/reference/android/view/SurfaceView).
- [AOSP SurfaceView rendering architecture](https://source.android.com/docs/core/graphics/arch-sv-glsv).
- [TextureView](https://developer.android.com/reference/android/view/TextureView).
- [SurfaceControl public API](https://developer.android.com/reference/android/view/SurfaceControl).
- [View content sensitivity](https://developer.android.com/reference/android/view/View#setContentSensitivity(int)).
- [Recording visibility API](https://developer.android.com/reference/android/view/WindowManager#addScreenRecordingCallback(java.util.concurrent.Executor,%20java.util.function.Consumer)).
- [Screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection).
- [AOSP policy implementation showing screenshot chord recognition and consumed-key handling](https://android.googlesource.com/platform/frameworks/base/+/19c468c8b796/services/core/java/com/android/server/policy/PhoneWindowManager.java).
- [Flutter Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views).

Local source evidence: `~/Library/Android/sdk/sources/android-36/android/view/SurfaceControl.java` (`setSecure`, `setSkipScreenshot` hidden annotations), `SurfaceView.java` (secure surface flags and BLAST layer construction), `View.java` (hosting-window sensitivity), and `WindowManager.java` (initial recording state and UID scope). Newer installed `android-37.2` SurfaceView source was inspected only for composition-order semantics; it is not a supported/tested runtime claim.

## Isolated prototypes

The alternate Dart entry point is `example/lib/main_research.dart`. Native harness classes live only under the example's `src/debug`; the research Activity and recording permission are in the debug manifest. Nothing is exported from the package library. Modes are engineering controls, not an end-user protection design. The native factory accepts only two fixed fixture indices and a validated composition name, never arbitrary real values.

### A — secure compositions

`default`: standard below-window SurfaceView. `media`: `setZOrderMediaOverlay(true)`. `top`: `setZOrderOnTop(true)`. All use explicit Hybrid Composition, fixed synthetic native Canvas text, and `setSecure(true)` before attachment. None ever clears security. There is no texture copy or unprotected native fallback. Failed draw hides/disposes the region. Surface creation/destruction gates posting; recreated surfaces redraw the fixture. Engine cleanup disposes every owned region.

Samsung ADB PNGs exclude both fields and retain the transaction text. The saved outputs are black rectangles, **not the requested asterisk replacements**. The public secure-surface API does not give the app a separate replacement image for the system compositor. A placeholder underneath a blacked-out secure layer cannot be assumed visible.

Samsung native recorder: FAIL for default, media, and top. No MP4 was saved by those refused attempts. ADB recordings saved and excluded values in all inspected decoded frames: default 2 frames, media 1 frame, top 3 frames. The three-second commands produce sparse encoded frames on a static screen; these are not three seconds of independent 60 Hz security samples. Native Samsung screenshot: BLOCKED on physical interaction. Normal Samsung live secure-pixel visibility: BLOCKED on direct observation, despite successful buffer posts.

Rotation and foreground checks were limited to media-overlay: portrait ADB output after returning from Home excludes both fields. Landscape ADB output excludes both visible fields, but the transaction is below the viewport; this is **not** a full landscape-layout acceptance pass. General scrolling/clipping, top-layer overlap, repeated physical capture, Activity recreation, and hot restart remain unqualified for the new variants.

API 34 shell `screencap` produced zero-byte files for default/media/top, including a direct on-device file write for top. This is a capture failure, not protection success; the exact shell failure cause is unverified. Its saved System UI default and top screenshots succeeded, demonstrating another path-dependent result. Empty files are not retained as PNG evidence.

### B — input diagnostics

The debug Activity logs only monotonic receipt time, key code, action, and Android event time for Power/Volume Up/Volume Down, then calls `super.dispatchKeyEvent` unchanged. It logs lifecycle and after-capture screenshot callbacks separately. It does not consume volume input, mask on volume keys, assume Power delivery, or delay capture. No Accessibility Service or privileged permission is used.

ADB-injected Volume Down and Up produced down/up events. That verifies instrumentation only; it says nothing about the real chord. Physical-button event ordering and legitimate physical volume behavior are BLOCKED. The Android system can recognize/consume a chord before Activity dispatch, and screenshots can originate without volume keys. Even a delivered event gives no public atomic relationship between app drawing, buffer latch, and screenshot capture. **NO-GO for a guaranteed pre-capture input solution.** No misleading timing-based masking implementation was added.

### C — automatic recording masking

Ordinary Flutter fixture text is deliberately used for this negative experiment. Real secrets must never enter this mode. Startup, unsupported API, stop/background, malformed state, or channel failure render placeholders. API 35+ registration reads the initial return value and subsequent callbacks on the main executor. Inactive (`0`) reveals fixtures; visible (`1`) masks them. Registration is re-established on resume; removal increments a generation before unregistering so obsolete callbacks cannot revive state. The isolated `RecordingProbe` is JVM tested for initial active state, duplicate start, stop/restart, denied registration, and removal failure.

A post-frame diagnostic acknowledges Flutter frame work only. It is **not** an Android compositor/encoder presentation fence. Monotonic callback receipt and KeyEvent uptime use different clock domains; do not subtract them as a capture latency measurement.

Three completed Samsung recordings were tested. Runs 1 and 2 preceded extraction of the same registration logic into `RecordingProbe`; run 3 used the final rebuilt APK:

1. First run: 345 decoded frames, last PTS 43.194967 s. Initial inspected frames were masked. It included notification-shade and a rapid Home/return transition; only selected start/end frames were visually reviewed. This is not a full no-exposure certification. The raw file remains `/tmp/fsp016/recording-callback-1.mp4` because it also contains unrelated system UI.
2. Second run: **98 decoded frames**, PTS 0 through 8.028411 s. All 98 field crops inspected. Frame 0 at **0.000000 s exposes both fixture values** with displayed state `0`; frame 1 at approximately **0.005511 s** is masked. Subsequent inspected frames, including the last frame, are masked. Original file: Samsung `Screen_Recording_20261109_140615.mp4`; preserved as [recording-callback-2.mp4](evidence/FSP-016/recording-callback-2.mp4). [First frame](evidence/FSP-016/recording-callback-2-first.png) is direct proof of leakage. This is not merely a UI preview.

3. Final rebuilt harness run: **100 decoded frames**, last PTS 12.019878 s. Inspected frames 0, 1, 2, and 99 were masked. [Contact sheet](evidence/FSP-016/third-contact.png) and [original MP4](evidence/FSP-016/recording-callback-3.mp4) retained. This confirms functional operation after the extraction; it does not repair the race demonstrated in run 2, nor establish that every frame in run 3 is safe.

Shell recording produced one decoded static frame containing both values and displayed state `0`: [callback-adb.mp4](evidence/FSP-016/callback-adb.mp4), [decoded frame](evidence/FSP-016/callback-adb-first.png). ADB screenshots in inactive recording mode likewise expose the values by design. This experiment provides no screenshot protection.

**Result: FAIL for secure selective recording.** Successful recording admission and eventual masking are useful functional observations, not a security PASS. Holding a mask for an arbitrary delay or masking on a screenshot callback would not repair the missing contract. A single exposed frame is sufficient to reject the guarantee.

### D — other architectures

No additional public architecture with a credible guarantee was identified. Separate windows still introduce secure layers in the full-display target; SurfaceControl reparenting or relative Z does not remove security classification. Texture rendering removes the required exclusion boundary. Content sensitivity secures a window. No hidden methods, reflection, OEM private API, root, or capture bypass was implemented. Untested alternatives are distinguished from experimentally failed ones; this research is not a mathematical impossibility proof for every future OS/OEM.

## Devices and validation matrix

| Device | Build | This run |
| --- | --- | --- |
| Samsung SM-S936B, API 36 | `samsung/pa2qxxx/pa2q:16/BP4A.251205.006/S936BXXSCCZH1_OXMCCZH1:user/release-keys` | ADB captures, native recorder through actual Quick Settings UI, lifecycle subset, input instrumentation |
| Android 15 emulator, API 35 | `google/sdk_gphone64_arm64/emu64a:15/AE3A.240806.043/12960925:userdebug/dev-keys` | Live host export, ADB PNGs, System UI screenshot after injected chord |
| Android 14 emulator, API 34 | `google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.050/12077443:userdebug/dev-keys` | Live host export, secure screenshot subset |
| Android 10 emulator, API 29 | `google/sdk_gphone64_arm64/emulator64_arm64:10/QSR1.211112.011/13135432:userdebug/dev-keys` | Safe unavailable fallback, no secure surface or recording registration |

| Required check | Result and scope |
| --- | --- |
| Normal rendering | PASS: inspected emulator host exports, API 34 default and API 35 media. Samsung secure live appearance BLOCKED; callback fixture visible in ADB output. |
| Physical Samsung screenshot saved with only fields excluded | BLOCKED this run. User-supplied FSP-015 result is FAIL (capture blocked). |
| ADB screenshot | PASS for inspected Samsung A variants and API 35 emulator captures only. API 34 shell screencap FAIL: zero-byte output with secure variants. Black exclusion, not asterisk replacement. |
| Repeated physical screenshots | BLOCKED; no physical-button operator. |
| Landscape screenshot | Partial media-overlay ADB evidence only; full surrounding-content layout NOT TESTED. |
| Samsung recorder allowed with secure fields | FAIL for all A variants: recorder refuses. |
| Samsung recorder allowed with callback masking | Functional admission PASS; protection FAIL (saved first-frame leakage). |
| ADB recording | A exclusion PASS for inspected frames; C FAIL. |
| Initial recording frames | C FAIL; do not generalize sparse A shell samples to all start races. |
| Background/foreground | A-media ADB exclusion after return PASS; C observations collected but full transition exposure audit NOT TESTED. |
| Activity recreation | NOT TESTED for new variants; prior FSP-015 evidence is historical only. |
| Hot restart | NOT TESTED on device for new variants; Dart delayed-create/disposal and native teardown covered by tests. |
| Android 10 | PASS safe fallback; normal-visible selective protection unavailable, therefore not acceptance PASS. |
| Android 14/15 | Limited compatibility PASS for inspected outputs, not blanket qualification. Recording C on API 34 unavailable; API 35 native recorder NOT TESTED this run. |
| Android 16 | Physical Samsung used for ADB and real native recorder UI; physical buttons remain BLOCKED. |

## Reproduction and pending manual work

Build from `example/` using the configured Flutter:

```sh
flutter build apk --debug -t lib/main_research.dart
adb -s DEVICE install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s DEVICE shell am start -n com.naseralomosh.flutter_screen_protection_example/.CaptureResearchActivity
```

The standard `MainActivity` does not register the research channel. Launch the named Activity explicitly. The alternate entry point keeps placeholders on unsupported platforms or a missing native harness. Release/profile builds cannot use the debug Activity. Ordinary example use remains `lib/main.dart`.

For each A variant, a human must confirm both values are legible on the device, press physical Power + Volume Down, confirm a new actual media file exists, and leave the app open for collection. Record the toast verbatim if rejected. Repeat ten times in portrait and landscape, after background/foreground, Activity recreation, region replacement, and Flutter hot restart. Include a non-sensitive transaction in the viewport. If Samsung saves JPEG rather than PNG, preserve its original encoding and record the format; never rename JPEG bytes as PNG. Confirm whether a PNG is actually saved if that is a literal requirement.

Pull the precise newly created file; never substitute `adb screencap` for the hardware-produced image. Inspect every output for both fields and surrounding content. A blocked capture is FAIL even if an independent ADB screenshot has black rectangles. Compare system gestures separately from buttons.

For recording, use Samsung Quick Settings → Screen recorder → Full screen, audio None → Start recording. Inspect the saved MP4 from its first decoded frame through the last, including app return, recorder stop, and initial-active registration. Repeat app-only/partial-screen scope separately. The current C counterexample already rejects secure protection; more successful runs cannot erase it.

For B, compare physical Volume Down alone, Power alone, their chord in both orders, and available screenshot gestures. Collect only `FSP016` diagnostics; correlate receipt ordering with system capture evidence without assuming the app receives Power or confusing clock domains. Do not add masking or consume keys based on ordinary volume input.

## Evidence and inspection limits

Selected durable files are in [evidence/FSP-016](evidence/FSP-016/). `MANIFEST.sha256` lists every retained evidence file. Images with `adb` are shell captures; `system` are actual emulator System UI saved PNGs; `live-host` are emulator host-display exports and **are not protected capture tests**. They intentionally show secure content for normal-view validation.

- Samsung A: `default-adb.png`, `media-adb.png`, `top-adb.png`, corresponding MP4s and decoded frame images; recorder logs `media-recorder.txt` and `top-recorder.txt` include fresh preflight refusal timestamps. The media log also includes the earlier default refusal.
- Samsung lifecycle subset: `media-landscape.png`, `media-foreground.png`.
- C counterexample: original second MP4, first frame, four contact sheets covering all 98 field crops; labels are frame index then PTS in seconds. The original MP4 is authoritative.
- C shell exposure: `callback-adb.mp4` and decoded first frame.
- Emulator qualification: API 34 default/top and API 35 media system PNGs and live-host exports; API 29 unavailable screens.
- Automated logs and test counts are retained with the evidence. Temporary exploratory logs and rejected/early screenshots remain under `/tmp/fsp016` and are not accepted evidence.

No real customer values were used. Diagnostics contain only event metadata. Retained recordings cover the synthetic example. Captured exclusion does not prove GPU-protected memory, protection from privileged extraction, external cameras, or immunity to OEM bugs.

## Automated validation

| Check | Result |
| --- | --- |
| `flutter analyze` (package and example) | PASS, no diagnostics after the prototype import fix |
| `flutter test` package | PASS, 76 tests |
| `flutter test` example | PASS, 12 tests: 6 existing + 6 research |
| Android plugin JVM | PASS, 24 tests |
| Example debug JVM | PASS, 7 tests: 3 surface lifecycle/security + 4 recording observation |
| Debug baseline APK | PASS |
| Debug research APK | PASS |
| `git diff --check` | PASS |
| `dart format --output=none --set-exit-if-changed .` | FAIL, five pre-existing files would change; no writes made by this check |
| Changed Dart files format check | PASS |

Formatting failures: `example/integration_test/plugin_integration_test.dart`, `lib/flutter_screen_protection_method_channel.dart`, `lib/flutter_screen_protection_platform_interface.dart`, `test/flutter_screen_protection_method_channel_test.dart`, `test/flutter_screen_protection_test.dart`. These were not changed by FSP-016. Initial prototype compilation failed on a missing `flutter/rendering.dart` import; it was fixed and subsequent builds/analysis passed. A root-directory build invocation also failed because the APK target belongs to `example/`; it was rerun there. No automated test failure was excluded. Hardware/button and recording-visibility behavior cannot be established by JVM mocks.

## Changes and recommendation

Modified by this task: `TASKS.md`, `IMPLEMENTATION_MASTER_PLAN.md` (FSP-016 append only), `example/android/app/build.gradle.kts` (test-only dependencies), and `example/android/app/src/debug/AndroidManifest.xml` (debug Activity and recording permission).

Created: this report; `example/lib/main_research.dart`; `example/test/capture_research_test.dart`; debug Kotlin `CaptureResearchActivity.kt` and `RecordingProbe.kt`; debug JVM `ResearchSurfaceTest.kt` and `RecordingProbeTest.kt`; and the evidence files enumerated in `MANIFEST.sha256`. All are Android-specific or host-side research evidence. The FSP-015 files, public Dart API, original example dashboard, and iOS code are preserved.

**Recommendation: NO-GO for production delivery of the requested behavior on this Samsung firmware.** FSP-015 remains the most credible secure rendering candidate, but no tested composition makes Samsung's recorder admit capture, and hardware-button acceptance is still pending. Recording callbacks must be described as best effort; do not expose the proposed `SensitiveContent` as guaranteed protection based on C.

Next implement only an evidence-driven qualification step: retain this isolated harness, complete the physical-button matrix, and use the secure-layer admission reproducer to seek a documented OEM/platform capability that permits selective capture. Do not add another timing workaround or remove security from a surface containing values. If the immutable requirements remain, there is no justified production implementation to ship from these findings. Keep FSP-016 BLOCKED, not DONE.
