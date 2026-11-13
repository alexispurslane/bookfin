---
id: boo-hwoz
status: closed
deps: []
links: [boo-p6w1, t9-ftlz]
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

## Launch — 2026-11-13

Astra xhigh lead launched from `0c0984d98f8d2e9b4be7f39e9a10769ddee0bf9c`.
Running, stage uncertain; branch not yet reported. Exactly one fresh read-only
Astra high reviewer authorized. Parent owns integration and closure.
The freshness preference remains with the parent; this ticket only implements
the shared query improvement and retains current every-refresh fetching.

- clientRequestId: bookfin-boo-hwoz-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hwoz-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hwoz-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hwoz-astra-20261113-1>

## Implementation evidence — 2026-11-13

Worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-92207740`, branch
`t3/narrow-collection-queries`, initial clean HEAD and original review base
`0c0984d98f8d2e9b4be7f39e9a10769ddee0bf9c`. No checkout changes. The ticket
remains in progress for parent integration and closure.

Audited both captured server versions and actual production dispatch/callers.
The current pinned research version is 12.4, source
`83d0d0e7f76e23e2e085c8ff67d28b772d35967d`; the older 10.11 source is used only
for compatibility. All ten source capture hashes match the parent manifests.

Collection discovery now uses each shown library, deduplicates collection IDs,
and pages every listing. Child queries accept AudioBook, Book and Audio and
omit optional image/user data. No fields=Id, recursive-membership change,
retained membership cache, controller change, worker-retention change or
refresh-cadence change. Empty selections make no collection requests. Counts,
starts, IDs and dense collection discovery are validated; sparse legacy child
pages advance through the source count. Request batches remain bounded.

Loopback HTTP fixtures prove the payload reduction and membership beyond the
old collection/child limits, including a short first page, empty middle pages
and a late book under older filtering. The existing Audio-track series rule
is preserved. Cancellation testing exposed an unhandled parallel collection
rejection; it is now observed immediately and still propagates to the caller.
An existing library-visibility fixture needed to honor BoxSet filtering.

Full source/caller audit, original failures, exact check commands, skips,
complete log paths, and review evidence are recorded under
`docs/evidence/boo-hwoz/`. Measurements are fixture-only, with no live-server,
latency or universal memory-saving claim. No device/browser checks, live
account access, hardening, merge, push, PR, deployment or closure was performed.

Verification before review: focused final catalog checks pass, affected
catalog/settings/app/downloads/playback/sync suites pass 1,665 tests with
3 existing plugin-integration skips, affected analysis passes, and changed-file
formatting passes. The full Flutter run has 3,673 passes, 27 existing skips,
and the known tf-il7u idle-layout failure. It also fails in the unchanged
focused frame suite and with all production code restored to the original
base for that check. The implemented file was restored afterward. The cause
remains unknown; no full-suite success or timing fix is claimed. Complete
original failure and skip inventories are saved in the evidence directory.

## Review and direct resolution — 2026-11-13

Exactly one fresh read-only codex/gpt-6-astra reviewer at high effort completed
against `5055f01314fe443e255efd14fbda49df282304dd`. Its original correctness
verdict is pass; ticket fulfillment and design are changes-required for D1.
The unchanged original report is `docs/evidence/boo-hwoz/review.json`.

D1 is resolved through the explicitly allowed follow-up-ticket route in
AGENTS.md:39 and the review remedy. New linked ticket t9-ftlz records the
large collection-result processing that remains on the UI isolate, its
ownership and possible scale, the unmeasured runtime cost, and acceptance for
moving that work away from drawing/input. No runtime fix or measurement is
claimed by this deferral. The original reviewer verdicts remain unchanged.
Per-finding and per-gap dispositions are in `resolutions.json`.

No production or test code changed after the reviewed HEAD. The existing
checks still apply; final whitespace checks cover the complete original-base
diff including review evidence and the follow-up ticket. No second review
was requested. All owned commands and the reviewer have finished. The known
tf-il7u full-suite failure and all other review limits remain explicit; parent
owns integration, acceptance, hardening and closure.

## Parent integration and closure — 2026-11-13

Integrated ordered child commits 5055f013, 5c051e90 and a39b2ce6 as
f688d00a, 5adbb4c8 and ff54cf27. The only conflict was appended ticket
history; both parent launch and child evidence remain. The three changed
Dart files match the reviewed child exactly. No integration implementation
or test edits were required.

Parent inspection covered the complete diff, callers, fixtures, original
review and resolutions. All 25 saved command-log hashes and ten source
capture hashes match. The child machine log independently counts 3,673
passes, 27 skips and one error, with done.success=false. Its tf-il7u failure
also occurs with original production; cause remains unknown.

Parent Nix checks passed, one command at a time:
- Formatting of the three changed Dart files: zero changes.
- dart analyze lib test integration_test tool/showcase_fixture.dart: no issues.
- flutter test --no-pub --concurrency=2 --reporter=expanded test/catalog
  test/settings test/app test/downloads test/playback test/sync:
  1,665 passed, 3 existing skips, zero failures.
- Complete integration-base whitespace check against 763511fd, repeated
  with closure evidence staged and after the closure commit.

Exact commands, results, commit mapping and parent log hashes are in
docs/evidence/boo-hwoz/integration.json. Raw logs are under
/tmp/bookfin-boo-hwoz-integration/. Follow-up scope commits made during
verification change no production or tests.

Closed for the integrated query scope with explicit limits. D1's linked
follow-up route is permitted by AGENTS.md and the review; collection CPU
work remains synchronous and unmeasured until t9-ftlz is implemented.
The original changes-required fulfillment/design verdicts are preserved;
no second review or reapproval is claimed. The child full suite did not
pass and no new full-suite pass is claimed. tf-il7u is now under independent
investigation. The catalog worker attribution in the child's validation
narrative should be boo-8xyn, not boo-zs5i.

Every-refresh membership fetching remains. Parent boo-p6w1 still waits
for the user's freshness choice. Existing skips, live-server compatibility,
device/browser acceptance, coverage/mutations and performance evidence remain
unverified. No push, PR, deployment or worktree removal.
