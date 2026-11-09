# Decision register

The maintainer approved the core choices below for Phase 1. Security-sensitive defaults and optional policies still require review of device evidence before release.

| ID | Context | Alternatives | Proposed selection and rationale | Risks | Status |
| --- | --- | --- | --- | --- | --- |
| ADR-001 | Channel commands and asynchronous observations | Methods only, events only, split channels | Preserve the existing MethodChannel and add EventChannel. Initial state and live updates share ordering. | Handshake and schema mismatch | Approved for Phase 1 |
| ADR-002 | State and ownership | Static singleton, per-widget observers, host controller | One owned controller per supported host with typed status and a shared broadcast stream. Explicit lifecycle avoids leaked observers. | Embedded engines and concurrent hosts need validation | Approved for Phase 1 |
| ADR-003 | Startup and signal loss | Reveal until capture, caller-only policy, mask on uncertainty | Opaque fallback for unknown and unavailable, explicit reveal override, always-mask option. | Visible behavior changes on older Android or transient detach | Approved for Phase 1 |
| ADR-004 | Selective protection | Replacement, blur, native surface, secure text-field hierarchy | Use mask or replacement for hiding content and blur for visual obfuscation. Keep arbitrary compositor exclusion out of scope and exclude undocumented hacks. | Initial capture frames and blur exposure | Approved for Phase 1 |
| ADR-005 | Whole-window policy | Automatic secure flag, host-only control, explicit lease | Evaluate optional leases that preserve pre-existing flags. Require coordination with other flag writers. | Host conflicts and Activity replacement | Pending optional scope and ownership |
| ADR-006 | Switcher privacy | Flutter-only cover, native hooks, defer | Evaluate Android Recents API and native iOS window overlays separately. Android Recents requires explicit host ownership. | Snapshot races and policy restoration | Pending physical evidence |
| ADR-007 | Platform floors and signals | Preserve scaffold floors, qualify explicit support floors, raise detection floors | Approved Flutter 3.35.4 and Dart 3.9.2, Android API 24 installation with API 29 support floor, and iOS 15.0 deployment. Android uses compile SDK 36, JDK 17, Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20, and JVM target 11. iOS uses Swift 5 language mode. Feature gates stay separate. | Runtime-floor and current Flutter qualification require direct evidence. | Approved and applied. Qualification open. |
| ADR-008 | Multiple iOS scenes and Android hosts | Global state, one supported bound host, independent host contexts | Validate one bound host per controller first and report ambiguous hosts as unknown. Add independent contexts only after explicit design and evidence. | Misattribution and scene changes | Approved for Phase 1 |
| ADR-009 | Android screenshot permissions and lifecycle | Library manifest, host declaration | The library declares the normal screenshot permission with a host manifest override. Use Flutter’s Activity lifecycle bridge for started/stopped observation. | Downstream permission and lifecycle bridge version constraints | Implemented for FSP-002. Runtime qualification open. |

## FSP-010 approval record

- **ADR-001.** Start unknown. Accept known capture state through a synchronized EventChannel snapshot. Use session generations and ordered sequences, discard stale and duplicate packets, and explicitly invalidate state on lifecycle or transport failure.
- **ADR-002 and ADR-008.** Use one controller and native subscription per supported host. Share concurrent initialization, allow controlled retry, and make disposal terminal. Ambiguous hosts stay unknown. Independently owned simultaneous hosts require separate design and evidence.
- **ADR-003 and ADR-004.** Default to opaque masking while capture is unknown, unsupported, detached, or failed. Reveal under uncertainty requires host opt-in. Blur is visual obfuscation. Replacement removes the sensitive child from the protected presentation. Rendering belongs to FSP-007.
- **Capabilities and compatibility.** Report screenshot and continuous capture support separately with typed reasons and scope. Preserve the existing version method and native build settings. Published compatibility requires verification. Optional window and switcher policies remain unapproved.

The maintainer approved ADR-007 on 2026-11-08. The approved settings are applied. FSP-010 remains blocked on [qualification evidence](PLATFORM_COMPATIBILITY.md#remaining-qualification).

## ADR-009 Android screenshot permission and lifecycle

The library declares `android.permission.DETECT_SCREEN_CAPTURE`. Android grants this normal permission at install time when it is present in the app’s merged manifest. A consuming app can use the screenshot API through the controller without an extra manifest edit or a runtime permission prompt. On API 34+, the adapter checks the grant before calling Android and reports `permissionMissing` if the host removes it or registration is denied. The example debug and release manifest merger reports trace the permission to the library. The debug APK declares it. An example debug manifest override was verified to remove it. [Android screenshot detection](https://developer.android.com/about/versions/14/features/screenshot-detection).

Inspect the app variant’s **Merged Manifest** tab in Android Studio or its Gradle `outputs/logs/manifest-merger-<variant>-report.txt`. To opt out, add the `tools` namespace and a removal marker to the higher-priority app or variant manifest. [Manage manifest files](https://developer.android.com/build/manage-manifests).

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission
        android:name="android.permission.DETECT_SCREEN_CAPTURE"
        tools:node="remove" />
</manifest>
```

The Flutter embedding directs plugins that observe Activity lifecycle through AndroidX to use `flutter_plugin_android_lifecycle`. This bridge lets observation follow Android’s started/stopped boundary and provides lifecycle catch-up when an engine attaches to a started host. The plugin accepts compatible 2.x releases starting at 2.0.29. The example locks 2.0.34, verified with Flutter 3.35.4 and the ADR-007 pins. The host’s applied AGP 8.11.1 also applies to the lifecycle bridge in that build. [Flutter ActivityPluginBinding](https://api.flutter.dev/javadoc/io/flutter/embedding/engine/plugins/activity/ActivityPluginBinding.html).
