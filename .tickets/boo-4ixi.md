---
id: boo-4ixi
status: open
deps: [boo-mx5i, boo-suhu, boo-sthf, boo-3oq0, boo-61vt, boo-ohud, t6-t9po, t2-00a4]
links: []
created: 2026-11-03T20:25:52Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Simplify and unify the UI after functional acceptance

User request November 3: UI feels overcrowded and distended with controls in places. After all acceptance tests are complete, perform a UI coherency and simplification pass without losing features. Do not interrupt or redesign the current acceptance candidate. Start from the actual running Android screens, including large text, small viewports, reader controls, library/details/downloads and account/sync states. Review control density, redundant presentation, spacing, typography, hierarchy and consistency across screens. Preserve every capability and its discoverability, accessibility, saved records and established behavior. Keep approved cream/sepia identity. This request authorizes reconsidering presentation/layout after acceptance; it does not select a particular navigation redesign.

## Design

docs/plans/bookfin.md. At the start of this later pass, inventory features and actual screens, then present two concrete design alternatives for genuine user-visible tradeoffs. Do not choose hidden controls or extra navigation costs without showing the tradeoff. Preserve settled product decisions.

## Acceptance Criteria

Begin only after all functional acceptance checks have completed and their blockers are resolved; dependencies are a minimum, not permission to skip remaining acceptance. Demonstrate a less crowded and coherent Android UI with before/after evidence, feature-to-control mapping proving no capability loss, and user approval of changed interaction choices. Recheck affected flows, large text, accessibility, and compact screens after changes.

