# Implementation master plan

Planning baseline only. Phase 0 review gates all implementation. Android and iOS work can proceed independently after the common contract is approved. Optional policies can be deferred without blocking the core release if omitted from public claims.

| Phase | Scope and deliverables | Dependencies | Acceptance and required tests | Risks | Definition of done |
| --- | --- | --- | --- | --- | --- |
| 0 · Audit and approval | Repository inventory, platform research, threat model, and decision register | Current scaffold | Check claims against official references and SDK headers. Review scope, SDK floors, fallback policy and host ownership. Verify documentation links and diff scope. | Stale availability or implied security claims | Maintainer signs off the planning baseline and core decisions. |
| 1 · Dart contracts | Typed model, controller, capability and event contracts, channel schema, fake platform | Phase 0 | Test legacy version API, initial snapshot, concurrent initialization, unsupported states, malformed payloads, cancellation and session ordering. | Stale inactive state or breaking callers | Shared wire fixtures and API review accepted. |
| 2 · Android | Activity binding, screenshot and recording callbacks, optional window controls | Phase 1 | Mock API floors, visibility sync, lifecycle and permission failures. Smoke-test API 34 and 35+ with physical gestures and recording. Validate manifest merge. | OEM behavior, UID scope, Activity replacement | Detection works at both boundaries. Optional policies have ownership and output evidence or are deferred. |
| 3 · iOS | Host binding, screenshot notifications, scene and screen capture state, optional privacy overlay | Phase 1 | XCTest for notification cleanup, initial read and stale callbacks. Physical tests on fallback and scene branches. Build and run scene-based example on current SDK. | Ambiguous scenes, snapshot timing, iOS 27 launch | Single-host contract verified on both branches. Optional overlay gated separately. |
| 4 · Widget | Mask, clipped blur, replacement, safe fallbacks and accessibility | Phase 1; native demo verification after 2–3 | Test all state and mode combinations, subtree removal, accessibility, focus, rebuild counts and controller swaps. Profile multiple fields. | Data visible in blur, layout jump, first frame | Widget suite passes and behavior and limits are documented. |
| 5 · Example | Capture dashboard, synthetic fields and supported policy controls | Phases 2–4 | Widget tests for UI and fake state. Run native event flow, unsupported fallback and policy toggles on representative devices. | Misleading simulation or credentials | Example is runnable with repeatable capture steps and synthetic data only. |
| 6 · Qualification | Automated regressions, physical matrix, output inspection, privacy review | Phases 2–5 | Run the [test strategy](docs/TESTING_STRATEGY.md), including relaunch mid-capture, foreground and rapid navigation. Inspect screenshots, recording and previews using synthetic data. | Coverage gaps and capture timing | Required device evidence and security review recorded. Narrow or defer unsupported claims. |
| 7 · Release preparation | Metadata, license, docs, CI and package dry-run | Phase 6 | Test clean checkout, minimum and current toolchains, package contents, links, and dry-run. | Placeholder metadata, SDK drift, unsupported claims | Release candidate evidence accepted. Distribution remains a separately authorized action. |

## Example application

Build a dashboard with a live capture-state chip, a capabilities panel with reason text, and an in-memory event timeline capped at 20 entries. Show a synthetic balance (`12,450.75 JOD`), a deliberately invalid card (`0000 0000 0000 0000`), and a non-routable IBAN-shaped placeholder (`JO00 DEMO …`). Assign mask, blur, and replacement to those fields simultaneously, with a mode selector to compare them. Leave a nonsensitive label visible as a capture reference.

Provide on-screen instructions to take a hardware screenshot, start a system recording, return to the app, stop recording, and inspect the output. Show disabled controls with the capability reason on unsupported hosts. A local preview may demonstrate the widget modes on any host, with a distinct preview label and no synthetic entries in the native event timeline. If approved and shipped, add a separate Android secure-window toggle and a switcher privacy toggle where supported. Direct users to compare captures and background previews separately.

## FSP-015 Android native secure region

Evaluate a dedicated secure Android surface for single-line text as a separate experiment. Keep capture observation and the planned masking widget independent. The prototype uses explicit Hybrid Composition with an engine-registered Android Platform View. Qualification requires normal viewing and inspection of actual saved screenshots on physical Android hardware. Record screen recording and switcher evidence separately. Keep the feature experimental until the physical matrix, accessibility design, embedding behavior, and performance are reviewed. [FSP-015 implementation and qualification](docs/FSP-015_NATIVE_SECURE_REGION.md).

## FSP-016 Android selective capture feasibility gate

Retain FSP-015 and isolate composition, input diagnostics, and synthetic recording-response experiments in the debug example. [FSP-016 research](docs/FSP-016_SELECTIVE_CAPTURE_RESEARCH.md) records Samsung secure-layer recorder refusal and actual first-frame exposure with reactive masking. Do not ship a guaranteed selective-capture API from these results. The task remains BLOCKED on physical-button qualification and a documented platform/OEM capability satisfying the unchanged acceptance criteria. ADB and emulator evidence cannot substitute for hardware-button capture. No iOS work is included.

## FSP-017 research revalidation

[Revalidation](docs/FSP-017_SELECTIVE_CAPTURE_REVALIDATION.md) preserves FSP-016 and adds a foreground guard against late recording callbacks while inactive. Execute the strengthened regression and rebuild when the toolchain can access its caches; complete the physical-button matrix before any qualification change. This does not address the previously observed first-frame recording leak. Keep the production feasibility decision NO-GO and the task BLOCKED.
