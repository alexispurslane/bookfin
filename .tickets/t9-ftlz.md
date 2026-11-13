---
id: t9-ftlz
status: open
deps: [boo-hwoz]
links: [boo-hwoz]
created: 2026-11-13T16:04:25Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Move large collection result processing off the UI isolate

Review finding D1 from boo-hwoz at 5055f01314fe443e255efd14fbda49df282304dd. lib/catalog/jellyfin.dart:_collectionItems accumulates every page, then _collections reduces complete discovery and child results synchronously. CatalogController calls client.catalog before its catalog-worker handoff. Transport offloads large JSON decoding but returns maps to the UI isolate, which draws frames and handles input. The accepted count permits one million records per listing and up to eight collection-child reads concurrently; 200-item network pages do not bound the final whole-list reduction. Move large collection processing off the UI isolate while preserving request ownership and cancellation. This is static structural evidence; runtime cost is unmeasured and it does not explain tf-il7u. AGENTS.md permits recording a follow-up for touched-code engine violations. This ticket records the reviewer-authorized deferral rather than claiming the CPU work is fixed.

## Acceptance Criteria

Large collection discovery and membership reductions execute away from the UI isolate, with meaningful behavior evidence and any performance measurements reported with limits. Preserve direct membership, both source-supported Jellyfin paging shapes, deduplication, optional-metadata fallback, account/credential/cancellation guards and bounded requests. Keep current refresh cadence, no retained membership cache, and the existing catalog-worker retention model unless separately authorized. Preserve all boo-hwoz loopback fixtures and run focused and affected checks through Nix. Do not weaken timing thresholds or infer the cause of tf-il7u.

## Parent caller audit and settled scope — 2026-11-13

boo-hwoz is integrated through ff54cf27; its final affected verification is
running separately. The parent verified D1 against actual code. Native
transport.send decodes responses above 8 KiB with compute but returns the
maps to JellyfinClient. _collectionItems then validates IDs and accumulates
all pages; _collections reduces whole discovery lists and child batches.
CatalogController._refresh calls client.catalog before its existing _build
worker. The controller's worker therefore does not cover this CPU work.
The catalog-retention work is boo-8xyn; the boo-hwoz validation narrative's
reference to boo-zs5i as the worker ticket is an attribution error.

Keep one request-local collection owner. Move nontrivial collection parsing,
validation and reduction through the existing native worker mechanism; keep
request cancellation and account/credential ownership on the client. Avoid
one worker hop per item or repeatedly sending an ever-growing accumulation
for each page. Choose the narrowest existing boundary that preserves the
bounded requests and both server count/filter orders; no retained membership
cache, new long-lived worker, generic framework, refresh-policy change or
controller-owned duplicate map. Ordinary malformed optional metadata retains
its existing fallback; never turn contract/programming bugs into recovery.
Browser compute cannot create native isolates; preserve the existing browser
behavior and state that limit instead of claiming browser off-isolate work.

Use the retained boo-hwoz behavior fixtures. Prove the worker boundary with a
real native-isolate test or a controlled worker invocation that establishes
where the reduction runs and what crosses it; do not substitute source-text
assertions, hardware timing thresholds or a synchronous test fake for that
proof. Retain meaningful red-before-green evidence for the boundary being
fixed. Protect cancellation and account replacement while worker work is
pending, failure classification, dense/sparse paging, direct membership,
shared collection deduplication, no work for no shown libraries, and fresh
membership on each refresh. Measure operation/transfer counts where they
support the claim; distinguish them from latency or total heap improvement.

Own lib/catalog/jellyfin.dart, narrowly necessary transport/worker interfaces,
focused tests and ticket evidence. Preserve current catalog retention and
all other work. Run focused collection/catalog tests, affected catalog/
settings/app/downloads/playback/sync suites, full Flutter suite, changed-file
formatting, affected analysis and complete original-base diff checks through
Nix, concurrency at most two, one heavy command per owner. Exactly one fresh
Astra high read-only reviewer after Astra xhigh build; direct fixes only.
No devices/browser, credentials/live-server access, coverage/mutations,
timing changes, push/PR/deployment or closure. tf-il7u is being investigated
independently; record any recurrence without changing its code or claiming
this CPU change fixes it. Parent integrates and closes.
