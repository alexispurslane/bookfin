---
id: boo-p58t
status: in_progress
deps: [boo-gxm8, ta-qobz, t3-7fv1, boo-dez0]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove Jellyfin catalog media and extra-record storage

Inspect the actual Jellyfin version and representative book libraries. Test ordinary-user access, chapters, downloads, per-item progress, ebook discovery, and custom display preferences in a disposable namespace.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Record a decision for existing storage versus plugin. Prove concurrent writes, discovery, deletions, isolation, retry, size limits, and restart behavior. Do not promise full sync from a successful single-device round trip.


## Notes

**2026-11-01T23:02:12Z**

Target Jellyfin server supplied by user: https://jellyfin.example.com. Discover its version during integration. Request credentials only through T3 private secret input.

**2026-11-01T23:45:22Z**

Research head e9dacdf4698f086d2aba741e5c5da36a0b84cb97 is awaiting independent review. Public evidence reports server 12.4.0; authenticated checks remain unproven. Parent has not selected a new plugin: existing advertised JellyfinEnhanced routes must be assessed before declaring existing server capabilities inadequate. Private login requested through T3; no credentials stored in this ticket.
**2026-11-01T23:36:36Z**

Scoped feasibility research: public server info and served OpenAPI both report 12.4.0. Inspected upstream v12.4 commit 83d0d0e7f76e23e2e085c8ff67d28b772d35967d. Private ordinary-user token request timed out; no authenticated live requests, media transfers, preference writes, playback reports, or server changes ran. docs/research/jellyfin.md separates live public, upstream source, local HTTP fixture, and file-backed model evidence. Source supports recommending the accepted small-plugin fallback for full extra-record sync: CustomPrefs has no caller revision check or arbitrary-scope listing; whole-set transaction/retries do not remove stale-snapshot loss. Model counterexamples cover lost edits, device registry loss, stale-retry resurrection, and bounded synthetic persistence through file reopening, not Jellyfin restart. New ticket td-4nvl records HTML/Markdown acquisition gap because the checked ebook resolver omits those extensions. Validation: 16 research behavior tests, plus 3 existing Flutter tests, pass; scoped Dart analysis has no issues and format verification passes. Ticket remains in_progress; parent owns integration, live follow-up, design decisions and closure.

**2026-11-01T23:43:00Z**

Final verification supersedes the earlier count: 18 research tests (14 HTTP/CLI safety tests and 4 whole-set model tests), plus 3 existing Flutter tests, all pass in nix develop. Added a red-then-green failure-path check that identifies the disposable client and preference scope without printing a token or raw error response. Scoped Dart analysis reports no issues; final format check passes. No SDK shell test, Android build, coverage, mutation test, or authenticated live validation was claimed. Public schema also advertises non-core JellyfinEnhanced bookmark/settings routes; only their schema was inspected and no other client storage was touched. Their suitability and implementation remain unproven.

## Parent review corrections and partial integration

Addressed review F1 with a total 20-second request deadline and forced connection cancellation. The new continuously trickling HTTP test failed against the original implementation after 22 seconds, then passed with the deadline and peer-observed disconnection. Each request owns its connection so cleanup can still run after a timeout.

Addressed F2: a new plugin is only a candidate fallback. The report now makes assessment of the advertised JellyfinEnhanced implementation, authorization, isolation, coexistence, semantics, limits and persistence an explicit transport-decision gate. This supersedes the earlier plugin recommendation.

Verification through nix develop: SDK-link safety checks, 3 application tests, and 19 research tests passed; scoped Dart analysis found no issues. git diff --check passed. Keep this ticket in progress: authenticated integration and the storage decision remain outstanding. Supplied login JSON was privately validated; no credential values are recorded here.

**2026-11-02T02:50:25Z**

t3-7fv1 follow-up resolves exact GET /Items/{id} payload isolation on a fresh synthetic fixture. New report docs/research/jellyfin-playlist-protocol.md records live lost-ack logical deduplication, owner-management data exposure, offset-page omissions during mutation, sampled limits, scan preservation, and clean restart. A complete transport is not approved: normal-playlist management protection is a measured limitation; retention, stale-replica admission, checkpoint compaction and upgrade compatibility remain unsettled/unproved. Product decisions tb-887c and tb-5fyd now gate boo-3oq0. No plugin is selected and lower-risk claims are not established. Keep boo-p58t and t3-7fv1 open for parent review.

**2026-11-02T05:28:20Z**

t3-7fv1 continuation measured one finite existing-storage checkpoint candidate, viable batching (1,240 actions → 16 objects before collection → one 45,948-byte checkpoint), and the exact pinned 12.3.0→12.4.0 pair plus clean new-version restart. See docs/research/jellyfin-finite-checkpoint.md for runtime/model boundaries, page-size-dependent search omissions and corrected unfiltered discovery, exact deletion/gap-growth blockers, and user-visible costs versus the accepted but unbuilt small-plugin fallback. No production transport or lower-risk plugin claim is approved; keep this ticket open.

**2026-11-02T00:37:15Z**

Continued from integrated main 31953f9. Private JSON password login is now supported with meaningful red-green tests; credentials and tokens stay out of output and repository files. The actual account is an administrator, so ordinary-user isolation remains unproven and all storage-write safeguards remain enabled. Final sanitized capture (2026-11-02T00:27:41.554903Z; November 1 America/New_York) reports one books library, 1,485 AudioBook entries, zero indexed Book/Audio entries, and five folders. First 30 audio items: 22 MP3, eight M4B, 27 with chapters, no provider IDs/track indexes/multiple sources. Representative MP3/M4B have 21/four ordered nonnegative chapter starts and one source each; eight 64-byte /File and /Download ranges returned 206 with matching Content-Range, 512 bytes in the final run. Item user data was unchanged. Final run issued 28 requests including login/logout, metadata GETs and ranges; no progress reports, storage tests, server changes or accounts were created. Two earlier inspection runs used four MP3 ranges each, bringing all media reads to 1,024 bytes. Subsequent logouts succeeded; an initial token-header mistake caused 401 for user lookup and logout, so one initial synthetic research session may remain registered, with its token discarded from memory. No session/device deletion was attempted.

Enhanced 12.14.0.0 is active. Public version agrees with plugin-list version. Both deployed bookmarks.js and config.js exactly match release tag 12.14.0.0 at 9bbf16c0de6662baeaa23e51c71505c15c560381. Source project/manifest still say 12.13.0.0, so exact backend DLL provenance remains open. Assessed source authorization, per-user ownership, locked add/delete, whole-document replacement, generated retry IDs, discovery, missing deletion markers, limits, persistence, compatibility and deployed-client coexistence. Existing frontend still posts whole snapshots and supports delete-all/orphan cleanup. No safe independent Bookfin namespace was established, so no authenticated bookmark/settings GET or storage write ran. A public synthetic-user bookmark GET returned 401. No new plugin is selected; existing-storage protocols are not all rejected. New linked ticket ta-qobz defines a disposable matching server/two-ordinary-account fixture, while boo-p58t retains the transport decision/proof and td-4nvl retains the HTML/Markdown acquisition choice. Catalog/download implementation can use the proven interfaces independently if the parent separates the dependency gate.

Final checks through nix develop: flutter test test tool/research/jellyfin --reporter expanded passes all 30 tests (27 research + 3 app); dart analyze tool/research/jellyfin reports no issues; dart format --output=none --set-exit-if-changed tool/research/jellyfin inspects four files with zero changes. git diff --check passes. The raw-socket deadline fixture initially exposed an expected connection-reset sink error; fixed the fixture without weakening the total deadline or peer-disconnection assertion, then the focused deadline test and two full suites passed. No SDK checks, Android builds, devices, preview, coverage or mutation work were run in this continuation. Relevant code/output paths and sanitized evidence reviewed for sensitive data. Keep ticket in_progress; parent owns integration, remaining choices and closure.


Parent correction: the live-research media probe now rechecks explicit account download permission, requires item CanDownload=true, and completes Download range checks before any File checks. A denial or invalid Download result stops File acquisition. Five regressions first failed; the old-checkout application and research suite passes 35 tests. Documentation now names authenticated evidence and its limited eight 64-byte range capture accurately. No new live requests or token cleanup occurred; initial-session revocation remains unproved. Full transport proof stays open.

**2026-11-02T12:06:06Z**

User chose dedicated storage and history retained until explicit deletion. boo-dez0 now owns the bounded plugin storage proof. Existing playlist research is complete as a rejected production direction; production sync still requires validated storage and application integration.

**2026-11-02T13:19:12Z**

Dedicated server-storage proof boo-dez0 is reviewed and integrated. User rejects ordinary-playlist storage; the minimal dedicated plugin is the selected implementation direction for extra records. Evidence docs/research/jellyfin-dedicated-storage.md separates real server transport from Python merge semantics. Production Flutter sync remains boo-3oq0; existing account/catalog/download acceptance is separately documented. Review remaining feasibility acceptance before closure.
