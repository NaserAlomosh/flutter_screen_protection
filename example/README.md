# Screen Protection example

Run the dashboard from this directory with a connected Android device.

```sh
flutter pub get
flutter devices
adb devices
adb -s DEVICE_ID shell getprop ro.build.version.sdk
flutter run -d DEVICE_ID
```

Android screenshot detection requires Android 14 (API 34) or newer and the
`DETECT_SCREEN_CAPTURE` install-time permission in the merged manifest. The
plugin supplies that permission by default. On API 33 and below the dashboard
shows **Unsupported · unsupportedOs**. Continuous capture is a separate
capability and currently reports unsupported on Android.

## Qualify screenshot delivery on hardware

1. Keep the example visible and wait for **Plugin: Initialized** and
   **Screenshot detection: Supported · activity**. Start with a fresh launch
   to get a count of zero.
2. Briefly press the device's physical Power and Volume Down buttons together.
   Verify Android saves the screenshot and record whether it shows a detection
   notice. The count should rise by one, with a UTC timestamp and a
   **Screenshot detected** entry in **Recent events**. Repeat and check that
   each screenshot raises the count by exactly one.
3. Press Home, take a screenshot while the example is backgrounded, and return
   to the example. Check the count is unchanged and the history shows
   invalidation and a new observation snapshot. Take another screenshot and
   check that it increments once, with a newer session.
4. Rotate the device and take another screenshot. Check that the count
   increments once. In a debug run, press uppercase `R` in the Flutter
   terminal to hot restart. Confirm the dashboard starts at zero, then take
   another screenshot and check it increments once without replaying old events.
5. Record the phone model, OS build, trigger, count changes, system notice
   and event session and sequence. Debug logs include `[FSP][SCREENSHOT]`
   and observation status.

The callback reports an observation after capture and provides event metadata
without pixels. Android Studio's screenshot toolbar, `adb screencap`, and
instrumentation captures are outside the documented callback path. An
ADB-simulated key chord can exercise the System UI path on some builds.
Record it separately from actual button presses.
[Android screenshot detection documentation](https://developer.android.com/about/versions/14/features/screenshot-detection)

The dashboard retains the latest 30 history entries. Session and sequence
refer to delivered events. The controller applies snapshots to state and
capabilities without exposing the snapshot's session metadata. The platform
version API supplies the Android release string. Use the ADB command above
to get the API level.

See the [validation record](../docs/TESTING_STRATEGY.md#fsp-002-android-screenshot-validation)
for earlier emulator results and the controller integration test.

## Samsung validation on 2026-11-09

The debug APK built over `bd62005` ran on a Samsung SM-S936B with Android 16
(API 36, build `BP4A.251205.006`). The merged manifest declared
`DETECT_SCREEN_CAPTURE`, and the installed app had the permission granted.
With the dashboard in the foreground, the OS logged a key chord and saved a
screenshot at 12:12:24 local time. The dashboard received one activity-scoped
event (session 1, sequence 1), moved from zero to one, and showed the event in
history. This occurred separately from the two ADB-simulated chords, which
reached Samsung's key gesture handler but did not trigger a screenshot.
Backgrounding and reopening the app invalidated the old session and restored
**Supported · activity** while retaining the count.
Landscape rotation preserved the count and supported status. Hot restart
returned to an initialized dashboard with a zero count and no replayed
screenshot. A fresh key-chord capture at 12:17:40 after hot restart
was saved and delivered once in session 5, sequence 1.

In a later run, two confirmed physical Power + Volume Down presses saved
screenshots at 12:27:00 and 12:27:05 local time. Flutter logged one event per
save in session 1, sequences 1 and 2. After backgrounding and reopening, the
dashboard still showed **Screenshots detected: 2** and both history entries.
The remaining hardware checks are a screenshot while the example is
backgrounded, a fresh screenshot in landscape after rotation, and
confirmation of the system detection notice.
