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
| ADR-009 | Android permissions and dependency scope | Declare in library, require host opt-in, heuristic detection | Use only the two normal permissions needed for supported detection. Decide manifest ownership after reviewing host opt-out and merged behavior. Reuse existing dependencies and evaluate lifecycle integration explicitly. | Downstream manifest surprises | Pending review |

## FSP-010 approval record

- **ADR-001.** Start unknown. Accept known capture state through a synchronized EventChannel snapshot. Use session generations and ordered sequences, discard stale and duplicate packets, and explicitly invalidate state on lifecycle or transport failure.
- **ADR-002 and ADR-008.** Use one controller and native subscription per supported host. Share concurrent initialization, allow controlled retry, and make disposal terminal. Ambiguous hosts stay unknown. Independently owned simultaneous hosts require separate design and evidence.
- **ADR-003 and ADR-004.** Default to opaque masking while capture is unknown, unsupported, detached, or failed. Reveal under uncertainty requires host opt-in. Blur is visual obfuscation. Replacement removes the sensitive child from the protected presentation. Rendering belongs to FSP-007.
- **Capabilities and compatibility.** Report screenshot and continuous capture support separately with typed reasons and scope. Preserve the existing version method and native build settings. Published compatibility requires verification. Optional window and switcher policies remain unapproved.

The maintainer approved ADR-007 on 2026-11-08. The approved settings are applied. FSP-010 remains blocked on [qualification evidence](PLATFORM_COMPATIBILITY.md#remaining-qualification). ADR-009 manifest ownership and lifecycle dependency review remain pending for Android integration.
