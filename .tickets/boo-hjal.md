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
# Send each EPUB section prepare only the style sheets that the section uses

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible. This is worker time, not UI time. lib/reader/epub/page_source.dart:1524-1535 and lib/reader/epub/prepare.dart:1142-1220. Each section prepare copies the text of every style sheet and every image size into a new isolate and parses the linked sheets again. A book with 300 sections and 300 KB of CSS copies about 90 MB and parses the same sheets 300 times for each page settings value. Record the sheets of each section at admission, as `sectionFaces` already does. Measure before a long-lived worker caches parsed sheets.


## Parent caller audit and settled scope — 2026-11-13

At 15942f1c, PageSource supplies the entire Publication.bookStyles map to whole-section preparation, partial preparation and sampled main-text measurement. SectionSource.styleSheets already promises the sheets reachable through links and imports. StyleSheet.parse resolves imports under the current media settings; collecting only reads under one media setting would miss dependencies after a width or day/night change. The survey's 90 MB copying estimate is not measured evidence: inspect Dart isolate transfer semantics before claiming CSS string bytes are copied.

Use the existing publication/admission and section-input owners. Keep one authoritative CSS text per publication resource, with section dependencies derived off the UI isolate and retained with the admitted publication. Reuse existing parsing, path resolution and import rules instead of a second CSS parser. Every production preparation path must receive only the sheets needed for its section or sampled sections, including reachable imports across supported settings. Preserve inline styles, import order, duplicate/cyclic/deep import handling, malformed or missing references, relative paths, current media behavior, fonts, main-text measurements, and original/admitted EPUB and MOBI reopening. Validate saved dependency facts through the existing record revision and invariant rules. Preserve boo-hd47 chapter facts and boo-rcgf measurement/excerpt ownership.

This is stylesheet dependency work. Image-size pruning, persistent workers, a parsed-stylesheet cache, global caches and new indexing frameworks are separate work unless a concrete prerequisite makes a narrow change necessary. Do not adopt them from the survey's estimate. Use real-book behavior plus controlled operation/input-size counts to establish reduced irrelevant work; no timing threshold or Android speed claim. A genuinely different user-visible result or cost remains a fork for the parent.

Required verification when launched: meaningful red-green tests for actual whole/partial/sample paths, linked and imported styles including conditional imports, unchanged visible styling and chapter labels, saved-record round trip/reopen and malformed records. Run affected publication/admitted-book/MOBI/EPUB tests, reader/crossings suites, affected analysis/format and full Flutter suite through Nix, concurrency two, one heavy command per owner. One Astra xhigh lead and exactly one fresh read-only Astra high reviewer; no second review, device/browser work, coverage, mutations, publication or closure. Parent integrates and closes. The boo-23ji handoff recovered on the same provider. This scope is ready for launch after parent integration commits are available.
