---
id: te-c2tc
status: in_progress
deps: []
links: [t3-5o5r, td-bz4y]
created: 2026-11-09T23:25:19Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Give every test EPUB builder a fixed entry time

Found in boo-02sx. The archive package stamps each ZIP entry with the time of the encode, which a ZIP file keeps to two seconds. So a test book built twice can get other bytes and another digest, and the reader then refuses a place saved in the first build. This made the time_left_test speed store test flaky under load. session_native_test.dart now builds its books through one helper with a fixed time. These builders still stamp the current time: epub() in test/reader/publication_test.dart, book() in test/reader/epub/page_source_test.dart, test/reader/epub/admission_test.dart, test/reader/epub/epubjs_fixtures.dart, test/reader/epub/corpus/book.dart and tool/showcase_media.dart. Give them a fixed time too, or share one builder.

## Inventory after the t3-5o5r investigation — 2026-11-13

t3-5o5r fixes only `epub()` in `test/reader/publication_test.dart`. A
controlled two-second change of the archive entry times reproduced its reader
restart assertion failure after a successful save. The payload hashes were
equal, but the original-file digests differed. Holding the entry times equal
restored the place. Production source-identity checks remain unchanged.
The exact schedules of the historical failures remain unknown.

The shared helper now gives every entry a fixed local calendar time.
`test/reader/session_native_test.dart` already fixes its entry times.
The following builders still construct new entries without a fixed time:

- `test/reader/epub/page_source_test.dart`: `book()`.
- `test/reader/epub/admission_test.dart`: `archive()`.
- `test/reader/epub/epubjs_fixtures.dart`: replacement entries.
- `test/reader/epub/corpus/book.dart`: `madeUpEpub()`.
- `tool/showcase_media.dart`: generated showcase books.
- `test/reader/epub/damaged_chapters_test.dart`: `_book()`; newly inventoried.
- `test/reader/epub/section_styles_test.dart`: `styledBook()`; newly inventoried.

This inventory comes from searching `ArchiveFile` and `lastModTime` under
`test/reader` and in `tool/showcase_media.dart`; the source evidence is in
`docs/evidence/t3-5o5r/source-audit.txt.gz`. The `showcase()` wrapper in
`admission_test.dart` and `showcaseBooks()` in `corpus/book.dart` already
override the encoder's modification time; those paths are fixed. These seven
remaining builders were not changed by t3-5o5r. This wider ticket remains open; the parent owns integration and
closure.

## Settled follow-up scope — 2026-11-13

t3-5o5r is integrated as 8cbc5ec3 and bcf02ea6. Its controlled evidence
establishes that equal EPUB entry payloads with different ZIP timestamps can
produce different publication identities after a successful save. Extend its
fixture correction to the seven builders inventoried above. Inspect remaining
ArchiveFile/ZipEncoder creation sites for this same class and record the
complete inventory. Keep fixture contents, ordering, source-change cases and
production identity rules intact. Do not rebuild checked-in corpus assets or
change production code. Use the existing fixture owners and fixed-time pattern;
add no generic builder framework merely for this cleanup.

Use controlled evidence for identical-input archive stability across encode
times, and retain sensitivity to changed content. Do not wait for wall-clock
boundaries, add sleeps, inflate fixtures, relax assertions or change timing
thresholds. Reuse t3-5o5r's cause proof where it applies; any new test must cover
behavior, not merely mirror a timestamp constant. Run focused fixture/caller
tests, one appropriate affected suite, the required full suite, affected
analysis, formatting and original-base-to-final whitespace checks. Retain all
results and skips with complete compressed logs and hashes.

One ticket lead builds/fixes; exactly one fresh read-only reviewer assesses the
complete diff and evidence for correctness, fulfillment and design. Parent owns
integration, acceptance, coverage, mutation testing and closure. No device or
browser interaction, PR, push, deployment or worktree removal.

## Parent launch record — 2026-11-13

Original base: `5c8c92ecd348a7fb7c51ab176da6e616cfd2aa1c`.
Lead: codex/gpt-6-astra, xhigh. Sole fresh read-only reviewer: same model, high.
Client request ID: `bookfin-te-c2tc-astra-20261113-1`.
Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-te-c2tc-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-te-c2tc-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-te-c2tc-astra-20261113-1>

Launch accepted. T3 owns the new worktree; branch not yet reported. Lead builds,
starts one read-only review, resolves findings and returns evidence. Parent owns
integration and closure. No result or acceptance is claimed at launch.

## Implementation and verification — 2026-11-13

The ticket lead corrected all seven settled fixture owners. Every newly created
entry uses the existing fixed local-calendar pattern. The two named showcase
wrappers retain their original date and identities. Contents, ordering, fixture
interfaces, missing entries, deliberate CRC damage and production identity
checks are unchanged. No checked-in corpus assets were regenerated.

A private copy of archive-4.0.9 supplied controlled default times two seconds
apart. Before the correction, all seven stability assertions failed with equal
payloads and order, while all seven changed-content checks and the clock control
passed. After the correction, all 15 checks passed. The diagnostic dependency
configuration and temporary test access were restored before final checks; the
shared package cache was never edited. This reuses the earlier t3-5o5r restart
cause proof without claiming a reconstruction of historical failures.

Focused checks: 99 passed, 8 existing skips. The 89-file transitive caller suite:
1,195 passed, 18 existing skips. Required full suite: 3,768 passed, 27 existing
skips, no failures. Complete commands, compressed logs, source snapshots, skip
reasons and hashes are retained under `docs/evidence/te-c2tc/`. Analysis,
formatting and original-base whitespace results are in `commands.jsonl`.

The repository audit found additional independent research EPUB creators,
recorded in td-bz4y. SVG-only ZIP security probes are not EPUB builders. The
complete inventory and scope decisions are in `inventory.json`.

One fresh read-only reviewer follows implementation. The parent owns integration,
acceptance, hardening and ticket closure. The ticket remains in progress.

## Sole review completed — 2026-11-13

The fresh read-only reviewer assessed correctness/regressions, fulfillment and
design separately: all pass; no material unverified requirements. Its original
report is preserved unchanged in `docs/evidence/te-c2tc/review-original.json`
and as a compressed exact text copy. Review metadata records its thread link.

F1 was a low-severity audit wording error: the isolated raster-fallback probes
create fresh SVG/JPEG ZIP entries rather than preserving original ZipInfo.
The lead checked both writer sites and corrected only `inventory.json`. The
resolution and updated hashes are retained. No runtime source changed after
the passing final checks, so no broad/full suite was repeated. Ready for parent
integration; acceptance, hardening and closure remain parent-owned.
