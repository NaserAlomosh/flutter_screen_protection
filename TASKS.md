# Engineering backlog

P0 gates implementation or release. P1 is core scope. P2 is optional. Status vocabulary is TODO, IN PROGRESS, BLOCKED, DONE. Review-pending tasks show their prerequisites explicitly.

| ID | Priority | Status | Depends on | Deliverable |
| --- | --- | --- | --- | --- |
| FSP-000 | P0 | DONE | None | Audit scaffold and write review drafts. |
| FSP-010 | P0 | TODO | FSP-000 | Approve core decisions and platform floors with maintainer and security reviewer. |
| FSP-001 | P0 | BLOCKED | FSP-010 | Define typed events, state, capability reasons, errors and shared wire fixtures. Preserve version lookup. |
| FSP-006 | P0 | TODO | FSP-001 | Build controller and fake platform. Test snapshot ordering, lifecycle invalidation, retry and disposal. |
| FSP-002 | P1 | TODO | FSP-001 | Bind Android Activity and implement screenshot callback with API and permission checks. |
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

After Phase 0 approval, start with **FSP-001**. Agree on the meaning of unknown, initial state, capture scope and invalidation before either platform emits events.
