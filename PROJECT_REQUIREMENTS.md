# Project requirements

Draft for review. Platform requirements describe intended behavior. See the [repository audit](docs/ARCHITECTURE.md#repository-audit) for the current baseline.

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| FR-001 | Deliver screenshot notifications from public Android and iOS APIs. | Android API 34+ reports a supported physical screenshot while the bound Activity is visible. iOS reports a UIKit screenshot notification while the host is eligible. Events carry metadata only. Unsupported paths register nothing and expose a capability reason. Lifecycle teardown removes callbacks. |
| FR-002 | Observe whether the host's content is included in capture. | Initialize or resume during active capture and obtain the correct initial state. On supported hosts, observe each active/inactive transition once. Unbinding, pausing, or channel failure invalidates stale state. Android visibility and iOS capture are identified by scope. |
| FR-003 | Provide reusable `SensitiveContent` with opaque mask, clipped blur, and custom replacement. | Multiple fields update independently. Mask and replacement remove the sensitive subtree. Blur suppresses child interaction and semantics. Mode and policy changes apply immediately. Widget disposal removes its listener without affecting siblings. |
| FR-004 | Provide typed events, current state, and capabilities. | Listeners share one native subscription per supported host. Initial state is readable independently of broadcast events. Timestamps, error codes, unknown state, and reinitialization behavior follow the API contract. Existing version lookup still works. |
| FR-005 | Evaluate and optionally ship separately scoped window and app-switcher policies. | Verify the actual capture output and Overview or switcher snapshot separately. Route changes and overlapping owners cannot clear another owner's protection. iOS reports full-window blocking as unavailable. |
| FR-006 | Publish an evidence-based compatibility matrix. | Cover Android 10–17 and iOS 15–27, identifying public API floors, planned build support, unavailable signals, and device evidence. Recheck the newest stable releases at release time. |
| FR-007 | Provide a runnable synthetic-data example. | Show live state and capabilities, screenshot and capture history, all widget modes, simultaneous fields, unsupported behavior, and optional controls when included. |
| NFR-001 | Limit registration and rendering overhead. | One observer per signal and host, no polling, and no protected-field rebuild from a screenshot or an unchanged effective policy. Profile several simultaneous blurred fields in a profile build and document the device, frame timings, and the accepted budget before release. |
| NFR-002 | Handle lifecycle and channel failures deterministically. | Repeat attach/detach, cancel, rotation, resume, and retry without leaked observers, duplicate state changes, or callbacks mutating a newer session. |
| NFR-003 | Keep the implementation portable and maintainable. | Use existing Flutter channels and platform interface. Review any new dependency explicitly. Build and test the declared minimum and current supported toolchains before release. |
| NFR-004 | Preserve accessibility and predictable layout. | Masked fields expose a safe placeholder or label. Focus, selection, tap, and semantics tests pass. Document layout and child-state behavior when swapping content. |
| SEC-001 | Keep capture handling metadata-only and local. | Review channel payloads, manifests, logs, sample storage, and dependencies. No screenshot pixels, widget values, customer data retention, upload, or detection network requirement. |
| SEC-002 | Minimize permissions. | Android declares only approved normal detection permissions for shipped features. Inspect the merged release manifest. iOS uses system observations with no capture permission prompt. |
| SEC-003 | Use conservative defaults for protected widgets. | Startup, unsupported, detached, and failed detection render an opaque safe placeholder by default. Reveal under uncertainty requires an explicit host decision. |
| SEC-004 | Document boundaries and test claims against output. | Explain post-capture notifications, initial-frame risk, blur leakage, platform scopes, and out-of-band capture. Security review signs off claims against physical-device evidence. |
| SEC-005 | Use documented platform contracts. | Exclude private APIs, secure text-field reparenting, screenshot-file monitoring, and any attempt to acquire recording content to infer capture. |

## Scope

- Android 10–17 and iOS 15–27 are the planning and validation ranges. Current build settings and supported feature floors are separate. Older scaffold targets carry no release support commitment pending review.
- Android detection is per Activity for screenshots and per UID for recording visibility. iOS screenshots are application notifications. Capture is scene-scoped on the preferred path and screen-scoped on the fallback.
- Capture source attribution, universal interception, arbitrary Flutter-widget compositor exclusion, recording creation, web and desktop detection, remote reporting, fraud scoring, and protection from external cameras or a compromised OS are outside scope.
- Multiple widgets in one Flutter host are required. Independent simultaneous hosts/scenes need evidence and explicit approval before being advertised.
