---
id: boo-hwoz
status: in_progress
deps: []
links: [boo-p6w1]
created: 2026-11-13T15:32:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Narrow collection queries while preserving refresh freshness

Common query improvement for boo-p6w1, independent of its pending refresh-freshness choice. Narrow collection enumeration to the shown book libraries where the supported Jellyfin API allows it. Request only AudioBook, Book and Audio children and omit optional image/user data that membership lookup does not use. Id is a core property, not a valid fields=Id option. Preserve all admitted series membership, account/credential/cancellation guards, mixed collections, duplicate collection discovery across libraries, and ordinary collection-failure fallback. Keep current refresh cadence and no retained membership cache.

Read the complete parent audit in .tickets/boo-p6w1.md. Crucial version boundary: the approved plan originally cited 10.11.0, but the research shell pins 12.4 and docs/research/jellyfin.md pins source 83d0d0e7f76e23e2e085c8ff67d28b772d35967d. On 12.4, a collection query with parentId for a library derives LinkedChildAncestorIds; 10.11 ignores that parent. Deduplicate collection IDs before reading children, so a server returning a broader set cannot duplicate membership. On 10.11 nonrecursive child filtering follows source pagination; a short or empty filtered page does not prove there are no later books. On 12.4 filtering/sorting precede paging. Preserve correct enumeration in both source-supported shapes. Do not silently truncate at the existing 1000-collection or 2000-child limits. Keep requests bounded and validate count/page data according to existing CatalogClient failure conventions. Do not change recursive membership semantics without equivalence evidence. Confirm source dispatch/callers rather than assuming the audit is an implementation recipe.

Own lib/catalog/jellyfin.dart and focused catalog query fixtures/tests, plus narrowly necessary production callers if the interface truly needs it. Reuse current CatalogClient request ownership, cancellation and catalog assembly; no new cache, controller, generic query framework or speculative API. Keep the catalog-worker retention model unchanged. Empty shown-library sets need no collection work. Preserve current user-visible series rules, saved-library startup, valid-catalog success when optional collection metadata is unavailable, and cancellation propagation. At a real product fork stop dependent work and report it.

Before implementation, write behavior fixtures using the real loopback HTTP server. Demonstrate meaningful original failure: unnecessary non-book child payloads, unbounded collection enumeration for shown book libraries on the new API, or lost membership beyond a source page. Exercise mixed collections, multiple shown libraries sharing a collection, multiple pages including an empty filtered middle page on the older behavior, late-page books, empty shown libraries, unavailable collections and cancellation/account transitions. Assert resulting catalog/series behavior and measured request/response work, not just a literal URL or source text. No latency, universal memory-saving or live-server claim from fixtures.

Run through Nix: focused Jellyfin/catalog behavior tests; affected catalog/settings/app/downloads/playback/sync suites; full Flutter suite; changed-file formatting, affected analysis and complete original-base diff whitespace checks. Flutter concurrency <=2 and one heavy command at a time. Keep failures, exact commands, skips and logs. No devices/browser, live account/secret access, coverage/mutations, timing changes, push/PR/deploy, merge or ticket closure. Exactly one fresh Astra high read-only reviewer after Astra xhigh build; lead fixes findings directly, no second review. Parent integrates and closes. Return clean committed work with original base, ordered commits, original review assessments, resolutions, and limits.
