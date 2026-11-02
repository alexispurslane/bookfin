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
