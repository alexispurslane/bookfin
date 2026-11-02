---
id: boo-u3cg
status: in_progress
deps: [boo-gxm8]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build book catalog series and edition relationships

Implement sign-in, book-only library selection, cached browsing, source identities, edition relationships, series order, and explicit corrections.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Behavior tests cover account separation, single/multi-file audio, distinct recordings, ambiguous title matches, ebook pairing, and offline browsing.


## Implementation unblocked

Appearance foundation is integrated at 3f84b54; its remaining city input is independent of catalog behavior. Public and authenticated research establish useful Jellyfin catalog routes and bounded download behavior, with admin-only and absent-ebook limits. Full storage proof stays in boo-p58t and continues to gate sync. Ordinary-user, denied-download, multi-file ordering and ebook-pairing integration acceptance is preserved in boo-2cgp, which gates release hardening. Catalog implementation can use synthetic behavior fixtures while those deployment checks remain open. Do not claim research endpoint permission enforcement is correct until parent fixes review F1.

User clarified production UI: one navigation system, bottom navigation anchored to screen edge, no gallery development labels or explanatory filler, immersive reading with controls available on tap. Preserve approved feature structure and aesthetics; the development gallery is not the production layout contract.
