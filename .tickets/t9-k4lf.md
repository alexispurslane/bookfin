---
id: t9-k4lf
status: in_progress
deps: [boo-7o92]
links: []
created: 2026-11-02T04:06:10Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Manage retained downloads outside the selected catalog

Downloaded files remain account-private when an item is removed from Jellyfin or its library is deselected. Current catalog screens intentionally hide these sources and never silently evict them. Provide an explicit account-scoped storage view that can remove retained files no longer reachable from the active catalog, without deleting unrelated files or another account files.

## Design

docs/plans/bookfin.md; docs/downloads.md

## Acceptance Criteria

Show retained storage separately from current edition availability. Tests prove account isolation, safe explicit removal, unreadable metadata handling, and no silent eviction.

## Notes

**2026-11-02T10:58:00Z**

Start independent implementation from integrated history main337a70f. Provide explicit same-account retained-download management using existing download/storage owner. Reader proof owns emulator; this build uses host verification and leaves device acceptance explicit. No automatic eviction or cross-account storage access.

**2026-11-02T11:24:48Z**

Implemented from original base 72996e4fe51d43639a08127ad3fdf0f1a74ef2f3. LocalDownloads derives current-account retained inventory directly from existing durable records/files; no second index. Separate Downloads storage section, including with no selected libraries, confirms removal and fails closed for unknown identity. Added retention, explicit-removal, source/account/server isolation, restoration, in-flight cancellation, metadata and path-containment tests. Meaningful red evidence and green host checks are recorded in docs/acceptance/retained-downloads.md. All 269 app tests, analyzer, formatting, SDK-link and diff checks pass. Android ARM64 debug and JavaScript web release builds pass. Build logs retain Java 8, dependency WebAssembly and Cupertino font warnings; no WebAssembly support is claimed. No device/browser operations, production Jellyfin calls, credentials, coverage/mutation, PR or ticket closure. Parent owns independent review, integration and runtime acceptance.

**2026-11-02T11:45:40Z**

Parent reproduced cancellation durability failure during account switch, then fixed immutable record account ownership and restoration ordering behind accepted commands. Containment/symlink guards remain intact. Tests cover multi-file cancellation while switching away and immediately back, and no transfer after Wi-Fi returns. All271 app tests, analyzer, format and Android ARM64 debug build pass. No new runtime/web acceptance; correction review pending, no closure.

**2026-11-02T11:53:06Z**

Independent correction review approved 4d409098b48eab2e37113b0ac05382f4d5435b20 with no blocking correctness or design finding. Parent integrated the feature and cancellation correction into main without conflicts. Application, tests, Android, tools and Nix files match the tested correction head; no test rerun was needed for this merge. Prior parent verification: 271 application tests, clean analysis and formatting, Android ARM64 debug build. Keep in_progress: Android retained-storage interaction and relaunch acceptance remain unobserved, and no user acceptance or hardening is inferred.

**2026-11-02T12:21:24Z**

Fresh Android attempt on integrated main756ae5f stopped before sign-in after my invalid Settings activity argument and its failed advised retry. Retained-storage visibility/removal/relaunch remain unobserved. New normal APK builds but was not installed; all271 app tests, analyzer and SDK-link checks pass through Nix. No code change, application regression, cross-account access or runtime acceptance claim. Own resources cleaned. See docs/evidence/playback/personal-records-fresh-attempt.md. Leave in_progress.

**2026-11-02T14:13:50Z**

Current-main APK82faf07d observed Alice retained398040 bytes outside catalog after all libraries deselected. Retained source survived process relaunch; Keep files preserved it; explicit Remove files cleared storage. Bob saw no Alice files before removal. Screenshots10-12 and full limits in docs/evidence/playback/current-main-android.md. Restoring library after removal encountered missing fixture route then failed navigation retry, so no later acceptance. Signed out, native media root empty, own resources cleaned. No code change or closure.
