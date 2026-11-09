# Engineering backlog

P0 gates implementation or release. P1 is core scope. P2 is optional. Status vocabulary is TODO, IN PROGRESS, BLOCKED, DONE. Review-pending tasks show their prerequisites explicitly.

| ID | Priority | Status | Depends on | Deliverable |
| --- | --- | --- | --- | --- |
| FSP-000 | P0 | DONE | None | Audit scaffold and write review drafts. |
| FSP-010 | P0 | BLOCKED | FSP-000 | Phase 1 core decisions approved. [ADR-007](docs/DECISION_REGISTER.md) approved and applied. Android API 29 runtime qualification passed on Flutter 3.35.4 and 3.47.7. iOS 15 runtime evidence and Flutter 3.47.9 native checks remain open. See the [evidence and gaps](docs/PLATFORM_COMPATIBILITY.md#remaining-qualification). |
| FSP-001 | P0 | DONE | FSP-010 core approvals | Define typed events, state, capability reasons, errors and shared wire fixtures. Preserve version lookup. |
| FSP-006 | P0 | DONE | FSP-001 | Build controller and fake platform. Test snapshot ordering, lifecycle invalidation, retry and disposal. |
| FSP-002 | P1 | IN PROGRESS | FSP-001 | Android screenshot observation implemented. API 29 and 31 fallback and API 34 and 35 emulator screenshot delivery passed. Samsung API 36 physical-button screenshots incremented the dashboard once per capture. Remaining hardware lifecycle and detection notice checks are documented in the [example README](example/README.md#samsung-validation-on-2026-11-09). |
| FSP-003 | P1 | TODO | FSP-002 | Add Android UID recording visibility, initial read and lifecycle removal. |
| FSP-004 | P1 | TODO | FSP-001 | Bind iOS host and implement screenshot observation and cleanup. |
| FSP-005 | P1 | TODO | FSP-004 | Implement scene trait and bound-screen fallback. Validate scene migration on current Xcode. |
| FSP-007 | P1 | TODO | FSP-006 | Implement and profile the three widget modes, fallback policies and accessibility tests. |
| FSP-008 | P2 | TODO | FSP-003, optional policy approval | Prototype Android secure-window leases and assess Recents ownership. |
| FSP-009 | P2 | TODO | FSP-005, optional policy approval | Validate a native iOS per-window snapshot overlay. |
| FSP-011 | P1 | TODO | FSP-003, FSP-005, FSP-007 | Build the synthetic dashboard, capability reasons, timeline and capture instructions. |
| FSP-012 | P0 | TODO | FSP-011, any shipped optional policies | Run physical matrix and inspect capture output and lifecycle evidence. |
| FSP-013 | P0 | TODO | FSP-010 | Resolve license, version, metadata, release ownership and CI targets. |
| FSP-014 | P0 | TODO | FSP-012, FSP-013 | Produce release evidence and successful package dry-run. |

FSP-001 and FSP-006 passed Dart codec, channel, controller, and version-lookup tests. **FSP-002** uses the approved v1 contract and the Android manifest ownership and lifecycle decision in [ADR-009](docs/DECISION_REGISTER.md#adr-009-android-screenshot-permission-and-lifecycle). See the [Android screenshot validation record](docs/TESTING_STRATEGY.md#fsp-002-android-screenshot-validation).
