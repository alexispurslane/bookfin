---
id: t9-ftlz
status: closed
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

## Launch — 2026-11-13

Astra xhigh lead launched from 0f1b55762aef7ea17c2460242203cd972d767014. Running,
stage uncertain; branch not reported. Exactly one fresh read-only Astra high
reviewer authorized. boo-hwoz is integrated and closed with 1,665 affected
tests passing and three existing skips. Its full-suite tf-il7u failure and
D1 runtime work remain explicit limits. The independent tf-il7u lead owns
frame-test investigation. Parent integrates and closes.

- clientRequestId: bookfin-t9-ftlz-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t9-ftlz-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t9-ftlz-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t9-ftlz-astra-20261113-1>

## Parent frame-test coordination — 2026-11-13

tf-il7u is integrated as 2a9df513 and 96eb86b5 and closed after parent EPUB
verification: 666 passed, 20 existing skips. It corrects a test completion
assumption; production is unchanged. Its child full suite passed 3,676 with
27 skips. Evidence: `tool/evidence/tf-il7u/integration.json`.

The running collection lead received this update. Its original base retains
the old frame assertion: record any recurrence with this correction noted,
without editing the frame test or repeating runs merely to get a pass. Parent
will verify the combined result at collection integration. t5-rplx remains
unexplained. Collection CPU work, scope and ownership are unchanged.

## Implementation lead evidence — 2026-11-13

Bound checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c3dea442`,
branch `t3/offload-collection-processing`, original clean HEAD
`0f1b55762aef7ea17c2460242203cd972d767014`.

Collection reads now use the existing undecoded transport and IsolateHop /
compute mechanism. Native workers parse and validate each bounded page, then
reduce discovery and direct membership. JellyfinClient retains request-local
ownership, network/credential guards and cancellation. Compact page contents
cross once into each whole-list reduction; no growing accumulation is sent
per page. Browser compute still has no native isolation. Refresh cadence,
queries, catalog retention (boo-8xyn) and source-backed loopback fixtures are
unchanged. Programming Errors propagate; ordinary optional metadata failures
still drop series names. A separate red test also fixed cancellation precedence
when a pending worker returns an ordinary infrastructure exception after close.

Meaningful red/green native-worker evidence, transfer/operation counts,
controlled cancellation and account replacement (including controller adoption
and persistence), exact commands, hashes, failures and skips are retained in
`docs/evidence/t9-ftlz/`. The fixture reports eight native worker invocations
for six pages and two reductions, not latency or total-heap measurements.
Compact child pages remain in request-local memory until the final reduction.

The first full suite completed with 3,688 passed, 27 skipped and the known
`tf-il7u` idle-layout failure at page_source_frames_test.dart:188. Its exact
failure and original-base equality of the frame test and scheduler are saved;
no cause or correction is claimed. Final verification and the one fresh review
are recorded alongside the evidence. No device/browser/live-server checks,
credentials, coverage/mutations, merge, push, PR, deployment or closure.
Parent owns integration, acceptance, hardening and ticket closure; status
remains `in_progress`.

Parent update during final verification: the tf-il7u test-only correction is
already integrated on main as `2a9df513d398ba86f0a6142abe1c7240e43e570e`, with
evidence `96eb86b5726891b9d6a89e24c72536d3cfbe1109`. This worktree intentionally
retains the old assertion from its original base; no frame work is edited or
cherry-picked. Parent verifies the combined changes at integration. Any old
assertion recurrence is retained, not retried toward green. t5-rplx remains
separate and unexplained.

Final tests: 39 focused collection passes; 1,681 affected-suite passes and
three plugin integration skips; full suite 3,689 passes, 27 skips and exactly
the old tf-il7u assertion failure. All commands finished with no interruptions.
The full run is explicitly failing, with the parent's integrated test-only
correction identified above. No t5-rplx failure was observed or claimed fixed.

## Fresh review and parent handoff — 2026-11-13

The one fresh codex / gpt-6-astra / high read-only review passed correctness
and regressions, ticket fulfillment, and software design separately. It
reviewed the entire original-base diff through implementation commit
`563f1f3d4e69354a8f7a64df4bb2f51e33f6a4bc`, including saved validation.
There were no findings, required changes, material in-scope gaps or user
decisions, so no fix stage was required. The exact original review and its
hash/launch metadata are in `docs/evidence/t9-ftlz/review-original.json` and
`docs/evidence/t9-ftlz/review.json`.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Af8b8b853-3e09-4e43-b6d9-7201d51b3662%3Adelegate-task%3At9-ftlz-review-astra-high-20261113-1>

Only review evidence and these notes follow the reviewed implementation.
The final complete diff whitespace and clean-checkout verification are saved
at `/tmp/bookfin-t9-ftlz/final-check.json` and reported in the handoff. All
owned commands and the reviewer have finished. Parent still must verify the
combined collection change with its integrated tf-il7u test correction; the
recorded full suite here remains failing. Parent owns integration, acceptance,
hardening and closure. Status remains `in_progress`.

## Parent integration and closure — 2026-11-13

Integrated 563f1f3d as 08b083c5 and 6aa1594b as 1bf2d597. The only conflict
was appended ticket history; parent launch/coordination and child evidence
were both retained. The reviewed collection code and tests are unchanged.
The integrated lib/test tree differs from the child's tree only by the
separately reviewed tf-il7u frame-test correction already on main.

Parent inspection verified all 18 archive/raw-log hash pairs, 18 command-log
hashes, four source hashes, the red-seam patch and original review hash.
The child's final affected pass and failing full suite were independently
counted from their structured events. Both old-frame failures remain recorded.

Combined verification at 1bf2d597 passed through Nix: 3,692 full-suite passes,
27 existing skips, zero failures and structured completion success. This
includes all 16 collection-worker tests and seven corrected frame tests.
Analysis of lib, test, integration_test and tool/showcase_fixture.dart found
no issues; three-file formatting changed nothing; the complete integration
diff passed its whitespace check. No runtime suites were repeated after this
successful combined run. Only ticket and integration evidence changed next.

Commands, commit mapping, counts, limits and hashes are in
`docs/evidence/t9-ftlz/integration.json`; all four parent logs are archived
under `integration-logs/`, with the full failure/skip inventory in
`integration-full-suite.json`. The original review remains unchanged.
Its combined-verification condition is now satisfied by this parent run.

Closed after integration and verification. This addresses boo-hwoz D1's
execution-location issue; it does not establish device latency or heap savings.
Browser execution, live Jellyfin, million-record stress and device acceptance
remain unverified. Native input copies and request-local compact pages remain.
The 27 skips remain explicit; t5-rplx remains unexplained. General coverage
and mutation testing remain after user acceptance. No newly unblocked tickets.
boo-p6w1 still waits for the freshness choice; every-refresh fetching remains.
