---
id: boo-hjal
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---

## Launch — 2026-11-13

Astra xhigh lead launched from eb64fe705198fba0563df0a188939f6e57e16f35. Running, stage uncertain; branch not yet reported. Exactly one fresh read-only Astra high reviewer authorized. Both latest PDF and EPUB integrations are committed prerequisites; parent combined verification is running independently.

- clientRequestId: bookfin-boo-hjal-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hjal-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hjal-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-hjal-astra-20261113-1>

# Send each EPUB section prepare only the style sheets that the section uses

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible. This is worker time, not UI time. lib/reader/epub/page_source.dart:1524-1535 and lib/reader/epub/prepare.dart:1142-1220. Each section prepare copies the text of every style sheet and every image size into a new isolate and parses the linked sheets again. A book with 300 sections and 300 KB of CSS copies about 90 MB and parses the same sheets 300 times for each page settings value. Record the sheets of each section at admission, as `sectionFaces` already does. Measure before a long-lived worker caches parsed sheets.


## Parent caller audit and settled scope — 2026-11-13

At 15942f1c, PageSource supplies the entire Publication.bookStyles map to whole-section preparation, partial preparation and sampled main-text measurement. SectionSource.styleSheets already promises the sheets reachable through links and imports. StyleSheet.parse resolves imports under the current media settings; collecting only reads under one media setting would miss dependencies after a width or day/night change. The survey's 90 MB copying estimate is not measured evidence: inspect Dart isolate transfer semantics before claiming CSS string bytes are copied.

Use the existing publication/admission and section-input owners. Keep one authoritative CSS text per publication resource, with section dependencies derived off the UI isolate and retained with the admitted publication. Reuse existing parsing, path resolution and import rules instead of a second CSS parser. Every production preparation path must receive only the sheets needed for its section or sampled sections, including reachable imports across supported settings. Preserve inline styles, import order, duplicate/cyclic/deep import handling, malformed or missing references, relative paths, current media behavior, fonts, main-text measurements, and original/admitted EPUB and MOBI reopening. Validate saved dependency facts through the existing record revision and invariant rules. Preserve boo-hd47 chapter facts and boo-rcgf measurement/excerpt ownership.

This is stylesheet dependency work. Image-size pruning, persistent workers, a parsed-stylesheet cache, global caches and new indexing frameworks are separate work unless a concrete prerequisite makes a narrow change necessary. Do not adopt them from the survey's estimate. Use real-book behavior plus controlled operation/input-size counts to establish reduced irrelevant work; no timing threshold or Android speed claim. A genuinely different user-visible result or cost remains a fork for the parent.

Required verification when launched: meaningful red-green tests for actual whole/partial/sample paths, linked and imported styles including conditional imports, unchanged visible styling and chapter labels, saved-record round trip/reopen and malformed records. Run affected publication/admitted-book/MOBI/EPUB tests, reader/crossings suites, affected analysis/format and full Flutter suite through Nix, concurrency two, one heavy command per owner. One Astra xhigh lead and exactly one fresh read-only Astra high reviewer; no second review, device/browser work, coverage, mutations, publication or closure. Parent integrates and closes. The boo-23ji handoff recovered on the same provider. This scope is ready for launch after parent integration commits are available.

## Implementation evidence — 2026-11-13

Worktree `t3-fbb08cd5`, branch `t3/section-css-dependencies`, original review
base `eb64fe705198fba0563df0a188939f6e57e16f35`.

Publication retains sorted CSS dependency paths per spine section, derived in
admission with the existing document-link and CSS-import parser. CSS text stays
in `bookStyles`. Whole, partial and sample workers receive detached section
maps. Imports remain available across width and day/night changes, including
shorter routes hidden by an earlier conditional deep route. Record revision 6
rebuilds old admissions. Decode validates dependency list structure and the
on-demand invariant checker compares it with the admitted documents.

Evidence, caller audit, exact commands, failures and transfer-semantics sources:
`tool/evidence/boo-hjal/README.md`. Core tests proved meaningful red before the
implementation. Tests observe actual worker map inputs and reject a captured
Publication. Real Alice conversion and admitted reopen preserve prepared output.
ChapterTitles and paragraph/excerpt production lifetimes remain unchanged.

The survey's 90 MB CSS-copy estimate is withdrawn: Dart shares immutable
strings. The controlled whole input drops from 48 map entries to five, partial
plus whole replacement from 96 to ten, and the sample worker from 48 to seven.
The old sample map was shared across its three sections. Parsing the linked
sheets remains unchanged. No Android or timing claim is made.

The first broad focused run exposed three ChapterTitles test-wrapper failures
after the query changed. The wrapper now forwards the query; all eight
ChapterTitles tests pass. No production ChapterTitles changes were needed.

Integration, user acceptance, hardening and ticket closure remain with the parent.

Verification before review: reader/crossings passed 1,706 tests with 21 skips;
the full rerun passed 3,535 tests with 27 skips; affected analysis reports no
issues; eight changed Dart files pass formatting; `git diff --check` is clean.
The first full run had one intermittent failure in the unchanged scheduled-frame
test. The unchanged targeted frame suite and full rerun passed. Ticket `tf-il7u`
tracks the unresolved cause. Both full logs are retained. No threshold or delay
was changed, and no command was interrupted.

## Sole review completed — 2026-11-13

The fresh read-only reviewer inspected the complete original-base-to-head diff
at `513a112c9161363719a9d836be78d9173adcb435`, real callers and saved evidence.
The original correctness, ticket-fulfillment and software-design verdicts are
all `pass`, with no findings, required changes or user decisions. The unchanged
original report is saved in `tool/evidence/boo-hjal/review.json`; the evidence
README links the completed review thread.

The report retains its validation gaps: the frame failure's cause is still
unverified under `tf-il7u`; skipped platform/opt-in checks and independent
reviewer execution were not performed; the semantic invariant rejection branch
has static evidence but no direct injected-record test. Decode performs
structural validation, with semantic comparison on demand, as scoped.
Performance evidence is limited to worker map entries for the measured books.
Coverage and mutations remain with the parent after acceptance.

All owned commands and the sole reviewer have finished. The final follow-up
commit records review evidence only; it does not change implementation or tests.
The ticket remains in progress for parent integration, acceptance and closure.
