# FSP-015 Android native secure region

**Status:** Experimental proof of concept. Samsung Android 16 ADB captures showed selective exclusion. Samsung’s built-in full-screen recorder refused to start with the secure layers visible. Physical-button screenshot acceptance remains open.

## Architecture and rendering

`SecureText` creates an `AndroidViewSurface` using `PlatformViewsService.initExpensiveAndroidView`. This requests Hybrid Composition. The engine registers `flutter_screen_protection/secure_text` through the plugin's Platform View registry. The factory creates an application-context `SurfaceView` and sets `setSecure(true)` before returning it for attachment. The installed Android 36 framework source sets the secure flag on the native buffer layer when constructing it. The public documentation also calls out early configuration. Because Flutter inserts the view into an existing Activity window, the embedding and OEM combination still needs direct qualification. [Android SurfaceView](https://developer.android.com/reference/android/view/SurfaceView#setSecure(boolean)), [Flutter Hybrid Composition controller](https://api.flutter.dev/flutter/services/PlatformViewsService/initExpensiveAndroidView.html).

The view uses Android's standard below-window SurfaceView ordering, where the view hierarchy opens a rectangular area for the separate surface. It renders the full opaque background and text into a locked Canvas on the UI thread, then posts the buffer. `SurfaceHolder.Callback2` handles surface creation, sizing, redraw, and destruction. A surface recreated for the same view draws the latest configuration. Dispose unregisters the holder and channel handlers, hides the view, and clears its stored text. Android and Flutter own release of the SurfaceView's buffers and removal from the hierarchy. Flutter also disposes Platform Views during a hot restart. The plugin releases its live views on engine detach. [SurfaceHolder](https://developer.android.com/reference/android/view/SurfaceHolder), [SurfaceHolder.Callback2](https://developer.android.com/reference/android/view/SurfaceHolder.Callback2).

An Android OS eligibility check on the existing command channel gates creation at API 34. After creation, Flutter sends text, font size, ARGB colors, and alignment over a per-view MethodChannel. Changes use the existing view ID. There are no creation arguments containing the text. Native status reports **Active** after a successful Canvas post, **Unavailable** while waiting for a live surface or on unsupported Flutter hosts, and **Error** on creation, configuration, or drawing failure. On failure the native view is hidden or disposed and Flutter reserves its layout space. There is no capture-event dependency. The plugin leaves window flags under host ownership.

```dart
SizedBox(
  height: 40,
  width: 260,
  child: SecureText(
    text: '15,750.00 JOD',
    fontSize: 28,
    textColor: Color(0xFF2E7D32),
    alignment: SecureTextAlignment.center,
  ),
)
```

## Platform coverage and limitations

- Android’s secure-surface API starts at API 17. This experiment requires API 34 or later because the API 29 emulator refused to save the entire screenshot when the secure surface was visible. The plugin still installs from API 24. Earlier Android versions and other Flutter hosts reserve empty space and report **Unavailable** without creating a native view or sending its text. The secure-region and screenshot-observation API gates are independent.
- The widget requires a bounded box. It renders a single clipped line with physical left, center, or right alignment, vertical centering, logical-pixel font size, and an opaque background. Multiline layout, system text scaling, bidirectional layout, selection, and screen reader access to the value are outside this experiment. The value is omitted from Flutter semantics and the Android accessibility tree. Surrounding safe labels are ordinary Flutter widgets.
- Qualify clipping, scrolling, overlapping views, route transitions, resizing, and frame pacing on target devices. A separate SurfaceView has composition and stacking rules of its own. Use simple rectangular layouts for this experiment. Hybrid Composition adds main-thread and compositor costs. The tested embedding has an explicit incompatibility between this controller and Hybrid Composition++ when HC++ is enabled. Texture-based composition and virtual display composition are outside the qualified design. [Flutter Android Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views).
- The captured Flutter buffer must contain only safe surrounding UI. A native secure view cannot redact a duplicate of the value in Flutter, another window, or an overlay. Values travel in Dart and native memory and through the in-process display channel. The plugin omits them from debug messages, observation events, status, and error replies. This mechanism addresses ordinary OS capture on qualified devices. It provides no protection from external cameras, privileged host display capture, compromised devices, app-side copies, or memory inspection.
- Screenshot, app-only recording, full-display recording, cast, and Recents preview are distinct capture paths. Each requires its own validation. **Active** describes a posted native buffer and cannot detect OEM capture behavior or prove that the user sees an unobscured surface.

## Screenshot procedure

1. Run the debug example on the target Android device. Record model, API, build, Flutter version, and renderer.
2. With the native section on screen, verify that both synthetic values are legible and both fields are marked **Active** by the combined indicator. Keep **Normal Content** visible as the control.
3. Press physical **Power + Volume Down**, then open the saved image from the device. Verify it contains the regular Flutter content and field labels and excludes both values. Record the appearance of both regions and confirm that Android saved the file. Check the observation counter separately.
4. Repeat after the screenshot overlay disappears. Run in portrait and landscape and after switching apps, removing and adding both views, hot restart, and Activity recreation. Check live rendering before each screenshot and inspect the saved files. Capture startup or transition frames separately.
5. In an emulator, record an injected System UI chord separately from physical buttons. Compare the OS-saved PNG with the emulator host display export. A host display export can contain the visible values and serves as a live-view reference.

## Recording procedure

1. Start the built-in Screen Record quick setting in full-screen mode, return to the demo, and keep the normal reference and both regions on screen.
2. If practical, exercise removal and re-addition, rotation, and app switching while recording. Stop and open the actual saved video. Inspect the first app frame, steady-state frames, and frames around each transition.
3. Repeat in single-app mode where supported. Record the recorder, scope, OS build, inspected frames, and whether the regular Flutter content and either value appear. Keep the result separate from screenshot evidence.

## Validation record

Flutter 3.35.7 and Dart 3.9.2 ran the debug example on API 34 (`UE1A.230829.050`) and API 35 (`AE3A.240806.043`) emulators with Impeller OpenGLES. The emulator host display exports showed both synthetic values and surrounding Flutter content. The System UI PNGs saved after ADB-injected Power + Volume Down chords kept **Normal Content** and showed black rectangles in place of the values. The first post-restart API 35 screenshot shows a counter of zero before event delivery. The dashboard subsequently recorded one event per screenshot in the new session, sequences 1 through 3, without recreating the native views. An independent ADB `screencap` image on API 35 showed the same selective exclusion.

| Check | Result | Evidence |
| --- | --- | --- |
| Android debug APK | PASS | Built with the example’s pinned Gradle configuration and JDK 17. |
| Package and example analysis | PASS | No diagnostics. |
| Dart package and example widget suites | PASS | 76 package tests and 6 example tests. |
| Android JVM suite | PASS | 24 tests, including factory registration and engine cleanup, OS eligibility, surface lifecycle and property redraw, and safe failures. |
| API 34 and 35 live rendering | PASS | Host display exports showed both values with ordinary Flutter content. |
| API 34 System UI screenshot and API 35 repeated System UI screenshots | PASS | Inspected a saved API 34 PNG and three consecutive saved API 35 portrait PNGs after hot restart. Both values were absent while ordinary Flutter content remained visible. |
| API 35 landscape | PASS | Live display and saved System UI PNG confirmed correct layout and selective exclusion after rotating and scrolling the test section into view. |
| API 35 lifecycle | PASS | Removed and re-added both views, switched to Android Settings and back, hot restarted, and recreated the Activity with `am start -R 2`. The Activity instance changed in the same process. Inspected live display exports and saved screenshots after re-addition and app switching, hot restart, and Activity recreation. |
| API 35 full-display System UI recording | PASS | Opened the saved MP4 from the built-in Quick Settings recorder. Frames inspected at the start, in steady state, and around removal and re-addition kept ordinary Flutter content visible and excluded both values. This run exercised the same renderer before the OS gate and example key were added. |
| API 29 ungated prototype | FAIL | On build `QSR1.211112.011`, both values rendered live. Power menu **Screenshot** saved no file with the native regions visible, and `screencap` returned zero bytes. Both capture paths worked after removing the regions. |
| API 29 final fallback | PASS | The Android 14 minimum prevented region creation. The example showed **Unavailable**, and the saved Power menu screenshot retained ordinary content and empty field areas. |
| Samsung API 36 ADB screenshots and lifecycle | PASS | ADB captures preserved ordinary Flutter content and excluded both secure regions in portrait and landscape, after re-adding the views, after foreground restoration, after Flutter hot restart, and after Activity recreation. |
| Samsung API 36 ADB recording | PASS | Inspected frames from the saved shell `screenrecord` MP4. Normal content remained visible, with two black rectangles. |
| Samsung API 36 built-in full-screen recorder | FAIL | Samsung rejected recording with the secure regions visible and saved no MP4. With both regions removed, the same recorder started and saved an MP4 containing the regular dashboard. |
| Samsung API 36 physical-button screenshots and direct live appearance | NOT TESTED | No hardware-button PNG or direct live-display observation available in this run. The active surface status and ADB capture cannot establish either result. |
| Other physical Android devices | NOT TESTED | No FSP-015 evidence. |
| Other Android versions, single-app recording, external displays, Recents and cast | NOT TESTED | No FSP-015 evidence. |

### Samsung Android 16 physical-device run

On 2026-11-09, the example ran on a Samsung SM-S936B, API 36, build `BP4A.251205.006`, firmware `S936BXXSCCZH1`, with Impeller Vulkan and Hybrid Composition. Samsung’s Quick Settings recorder in full-screen mode reported `Secure layer detected. Screenshot failed` and error `-50004` during preflight. No media projection started and no video was saved. Removing the secure views allowed the same recorder to start and save a control MP4. This behavior differs from the Android shell recorder on the same phone. Samsung recognized an ADB-injected screenshot chord in its key gesture handler without saving a file, so that injection supplies no evidence about the physical button chord.

## Production readiness

The evidence supports continuing the prototype for capture paths that permit selective exclusion. Samsung’s built-in full-screen recorder fails that requirement on the tested firmware. Production banking use requires physical-button screenshot and recording qualification on supported OEM and Android builds, lifecycle and transition-frame review, an accessibility design, and performance and embedding qualification. Keep FSP-015 open until its physical screenshot acceptance criteria are met.
