---
id: tc-y4ij
status: in_progress
deps: []
links: []
created: 2026-11-07T23:04:53Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Decide what a sign-in over a saved access denial reports

From t4-lvhh. CatalogController.connect adopts the saved catalog of the account, which can hold accessBlocked from an earlier denial. If Jellyfin then lists the libraries and they contain the saved selection, connect sets _verified to true but keeps _accessBlocked. The status then says reach accessRevoked and verified true at once, and the library stays empty until the next refresh. AccountBinding asks record sync to run, but sync is bound to no account because access is blocked, so it does nothing. Reproduce: sign in, refresh with selection, refresh with CatalogFailureKind.forbidden, sign out, sign in again as the same user. Decided by the orchestrator on November 7, 2026: the catalog reports the latest answer from Jellyfin. A sign-in that lists the selected libraries clears the saved denial and saves the cache without it, so the library appears at once. The other option left the library empty until the next refresh with no gain. Former choice: either a sign-in that lists the selected libraries clears the saved denial (and saves the cache without it), or a sign-in over a saved denial is not verified. Owned file: lib/catalog/controller.dart and its tests.

## Acceptance Criteria

After a sign-in over a saved denial, statusNotifier never says accessRevoked and verified true at once. A test covers the chosen behavior and a restart after it.

