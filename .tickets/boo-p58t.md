---
id: boo-p58t
status: in_progress
deps: [boo-gxm8]
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

**2026-11-01T23:36:36Z**

Scoped feasibility research: public server info and served OpenAPI both report 12.4.0. Inspected upstream v12.4 commit 83d0d0e7f76e23e2e085c8ff67d28b772d35967d. Private ordinary-user token request timed out; no authenticated live requests, media transfers, preference writes, playback reports, or server changes ran. docs/research/jellyfin.md separates live public, upstream source, local HTTP fixture, and file-backed model evidence. Source supports recommending the accepted small-plugin fallback for full extra-record sync: CustomPrefs has no caller revision check or arbitrary-scope listing; whole-set transaction/retries do not remove stale-snapshot loss. Model counterexamples cover lost edits, device registry loss, stale-retry resurrection, and bounded synthetic persistence through file reopening, not Jellyfin restart. New ticket td-4nvl records HTML/Markdown acquisition gap because the checked ebook resolver omits those extensions. Validation: 16 research behavior tests, plus 3 existing Flutter tests, pass; scoped Dart analysis has no issues and format verification passes. Ticket remains in_progress; parent owns integration, live follow-up, design decisions and closure.

**2026-11-01T23:43:00Z**

Final verification supersedes the earlier count: 18 research tests (14 HTTP/CLI safety tests and 4 whole-set model tests), plus 3 existing Flutter tests, all pass in nix develop. Added a red-then-green failure-path check that identifies the disposable client and preference scope without printing a token or raw error response. Scoped Dart analysis reports no issues; final format check passes. No SDK shell test, Android build, coverage, mutation test, or authenticated live validation was claimed. Public schema also advertises non-core JellyfinEnhanced bookmark/settings routes; only their schema was inspected and no other client storage was touched. Their suitability and implementation remain unproven.
