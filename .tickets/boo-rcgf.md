---
id: boo-rcgf
status: closed
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Own EPUB paragraph segment measures by content width, not in a global table

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed by static trace, not executed. lib/reader/epub/layout.dart:2147-2224. `_found` is a static Expando keyed by the paragraph object, with no width in the key. `pager.note` (lib/reader/epub/pager.dart:310-335) lays out a note excerpt at the sheet width, and `without(item)` (lib/reader/epub/prepare.dart:354-366) shares the later paragraph objects with the page. A note whose second or later paragraph exceeds about 1,024 code units overwrites the segment starts of that paragraph. A later page-width run that starts inside the paragraph then cuts a page at the wrong text (skipped or repeated lines). In a seeded section `agrees()` fails and the kept page map is deleted. No test covers a note with a long paragraph. Reproduce it first with a test. Then make the measures a value that the owner of the run holds, keyed by item and width, and lay a note out through the page source.


## Astra implementation scope

Start from the integrated catalog migration and PDF frame fixes on main. The current integrated catalog suite is running; the previous main baseline was 3,231 passes and 25 skips, and the catalog branch reported 3,252 passes and 25 skips. Build and direct fixes use codex/gpt-6-astra, reasoningEffort xhigh. One fresh read-only reviewer uses the same model with reasoningEffort high. No other children. The parent integrates and closes.

Reproduce cross-width contamination through a long note paragraph shared with a page and a later page-width run starting inside that paragraph. Use one explicitly owned measurement model for layout, position search, kept measures, and notes, keyed by the actual paragraph and content width. Preserve resumable work budgets, correct kept-map validation/rejection, and place continuity. Route note layout through its existing page-source ownership. No new product choice or wholesale EPUB engine redesign is intended.

Required checks include meaningful failing regression(s), all EPUB tests and crossing tests, affected analysis/format, and the complete Flutter suite with concurrency at most two. Builds and tests use nix develop, one heavy command at a time. Leave coverage, mutations, device acceptance, integration and ticket closure to the parent.

## Delegated task

Original base: adb8c2bfc190fd7c6db9de166deecbf1baa6cba8.
Client request ID: bookfin-boo-rcgf-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rcgf-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.

## Implementation evidence — 2026-11-13

Checkout identity before edits: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-9eb5d50c`, branch `t3/epub-width-owned-measures`, HEAD and original review base `adb8c2bfc190fd7c6db9de166deecbf1baa6cba8`, clean status. No checkout changes. Implementation uses codex/gpt-6-astra at xhigh; one fresh review uses the same model at high.

Reproduced before implementation with actual prepared paragraphs, layout runs, the pager's note path and a retained page map. The long later paragraph remains the same object in the excerpt. The retained page expected character offset 20,188 but opened at 13,554 after notes at other widths. Nested content failed both at a narrower sheet width and at the original outer width with different surrounding padding. Command: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_map_open_test.dart test/reader/epub/layout_run_test.dart --name 'a narrower note preserves|a note at width'`. Three meaningful failures in `/tmp/boo-rcgf-red.log`; the same three passed in `/tmp/boo-rcgf-green.log`.

`_SectionLayout` now owns `LayoutMeasurements`. Page runs, cell runs, line searches, invariant checks, excerpts, and kept-map import/export/rejection use that owner. Paragraph segments are keyed by paragraph identity and actual content width. Intrinsic table extents use the same owner. Weak item/section keys let cached content and its measures leave together. The section index refers to the same segment objects for map export; kept segments bind to a content width when first reached, without measuring whole paragraphs or walking all enclosing boxes during import. Already-bound searches reuse that width. Width-independent immutable text indexes remain unchanged.

The pager asks the page source to lay out its note excerpt. The source preserves bounded steps and gives the finished page to the note's existing drawing/image lifetime. It disposes interrupted runs and unfinished pages. A delayed excerpt cannot recreate an owner for page settings already dropped. Backlink removal, paragraph sharing, and the kept-map format remain unchanged. No measurements are reset when a note opens.

Additional evidence: existing search tests caught an initial implementation error that read a first paragraph's width before entering its enclosing boxes. The corrected search still yields between segments. Tests that intentionally share measurements now pass the owner explicitly. The nested-note regression also bounds the text laid out when reopening a late page and searching its saved place. The retained-map regression opens widths 240, 340, and 240 pixels, checks the original saved place and no map rejection, and reopens from disk with no line search. Source lifecycle tests cover abandoned settings, cancellation between steps, and a returned excerpt remaining readable after source disposal.

Verification history: initial test setup lacked this new worktree's `.dart_tool` package metadata; copied `package_config.json` and `package_graph.json` from the existing project cache without installing packages. Test API/nullable typing mistakes and a test assumption that a layout step returns exactly its requested page count were corrected. The first four-file focused run had 125 passes, one skip, and three failures: the two first-paragraph search regressions plus the table reuse test that still relied on global state. All eight focused search/table/note checks then passed in `/tmp/boo-rcgf-search-green.log`. The first reader/crossing run had 1,661 passes, 21 skips, and only the new dropped-settings regression failing (`/tmp/boo-rcgf-reader-crossings.log`); seven focused lifecycle/search/note checks passed after its fix (`/tmp/boo-rcgf-lifecycle-green.log`). These were implementation/test-setup failures, not claimed as pre-existing failures.

Final checks and fresh review follow below. Coverage, mutation testing, device acceptance, integration, and ticket closure remain with the parent.

The caller audit also updated the existing cache probe and corpus/survey helpers to share an explicit measurement owner where their old timing or reconstruction depended on global reuse. No device probe was run.

Before review, a further ownership regression showed that an excerpt which disproved retained table extents consumed the validation check without rejecting the source's map. `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_map_open_test.dart --plain-name 'a note that disproves kept table widths'` failed with zero map rejections instead of one (`/tmp/boo-rcgf-note-rejection-red.log`). The source now stops and releases that excerpt run, rejects the retained measurements through its existing transition, and rebuilds the excerpt in bounded steps. The regression compares the returned note with a fresh layout and checks disk-map removal. The three-file check `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_map_open_test.dart test/reader/epub/page_source_test.dart test/reader/epub/pager_test.dart` passed 94 tests with 2 configured skips (`/tmp/boo-rcgf-note-rejection-green.log`).

The complete reader/crossing check `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader test/crossings` passed 1,662 tests with 21 configured skips (`/tmp/boo-rcgf-reader-crossings-final.log`). The first full check passed 3,258 tests with 25 configured skips (`/tmp/boo-rcgf-full.log`); the full check is repeated after the additional note rejection fix.

Final affected analysis: `nix develop --command flutter analyze --no-pub lib/reader/epub test/reader/epub test/research/epub_layout_cache_test.dart tool/reader/layout_cache_probe.dart` — no issues (`/tmp/boo-rcgf-analysis-final.log`).

Final full check: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded` — 3,259 passed, 25 configured skips, no failures, 4m27s (`/tmp/boo-rcgf-full-final.log`). Formatting check: `nix develop --command dart format --output=none --set-exit-if-changed lib/reader/epub/layout.dart lib/reader/epub/page_source.dart lib/reader/epub/pager.dart test/reader/epub/corpus/check.dart test/reader/epub/kept_measures_test.dart test/reader/epub/layout_run_test.dart test/reader/epub/page_map_jump_test.dart test/reader/epub/page_map_open_test.dart test/reader/epub/page_source_test.dart test/reader/epub/table_test.dart test/reader/epub/step_budget_test.dart test/research/epub_layout_cache_test.dart tool/reader/layout_cache_probe.dart` — 13 files, no changes (`/tmp/boo-rcgf-format-check.log`). `git diff --check` passed (`/tmp/boo-rcgf-diff-check.log`). Fresh read-only review is the next stage; the ticket stays in progress for parent integration.

## Review and direct fixes — 2026-11-13

The single authorized reviewer completed on `74bd228c94f7a806cf987487921542f118a91f88`, reviewing the entire diff from original base `adb8c2bfc190fd7c6db9de166deecbf1baa6cba8`, real callers and verification logs. Provider/model/effort: codex/gpt-6-astra/high. Task: `node:delegated-task:command%3Amcp%3A81634629-6aeb-4e14-b6c2-c9c508dd372d%3Adelegate-task%3Aboo-rcgf-review-astra-20261113-1`. All three assessments (correctness, fulfillment, design) were changes-required; no material assessment was unverified. Reviewer performed no edits, builds, tests, commits or checkout changes and started no children. Direct fixes use codex/gpt-6-astra/xhigh; no second reviewer.

- C1, P2: An excerpt already between steps could return after its settings were dropped. Reproduced by starting a long excerpt with a zero step budget, then changing settings twice. Expected `PageRequestStopped`; received a page.
- C2, P2: Another page could reject retained table extents while an excerpt retained the old column widths. Reproduced through actual preparation, retained map import, a long first table row and a concurrent later-row page request. The returned note used a 198-pixel first column instead of the fresh layout's 72 pixels.
- D1, P2: Active excerpts were outside the source's registered requests and section-owned run transitions. Sources: User's single owner and coherent transitions; Ousterhout's information hiding; Muratori's reuse of existing paths. This was the shared cause of C1/C2, not another independent behavior defect.

Red command: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_source_test.dart test/reader/epub/page_map_open_test.dart --name 'dropping page settings stops|an active note rebuilds'` — both failed for the predicted behavior (`/tmp/boo-rcgf-review-red.log`). After the first direct fix, the six focused lifecycle/rejection checks passed (`/tmp/boo-rcgf-review-green.log`): `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_source_test.dart test/reader/epub/page_map_open_test.dart --name 'dropping page settings stops|an active note rebuilds|an excerpt|disposing the page source stops|a returned excerpt|a note that disproves'`.

Excerpts now use the source's existing registered request lifetime, so settings drop and disposal stop their waits and active requests protect preparation from cache eviction. `_SectionLayout` owns active excerpt runs and their source preparation. Its existing run-release transition disposes unfinished cell content and pages before retained measures are forgotten. Resumed excerpts rebuild after another run's rejection; finished pages transfer to the caller and remain usable after source disposal. The on-demand checker includes active excerpt ownership. Pending source disposal now reports the same `PageRequestStopped` as other registered requests; calls on an already disposed source retain their ordinary guard.

A related eviction case was reproduced during the same fix stage: a caller can retain old preparation while backlink lookup lets other sections fill the cache. Rejecting the delayed note's table measures returned a 4,758-pixel note instead of the correct 2,415 pixels. `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_map_open_test.dart --plain-name 'a delayed note rejects kept widths'` failed meaningfully (`/tmp/boo-rcgf-review-eviction-red.log`). The rejection transition now includes the preparation held by every active excerpt, including preparation that left the cache before its request began.

Focused final check: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader/epub/page_source_test.dart test/reader/epub/page_map_open_test.dart test/reader/epub/pager_test.dart` — 97 passed, 2 configured skips (`/tmp/boo-rcgf-review-focused.log`). This resolves C1/C2 with red-green behavior evidence and D1 with one registered request lifetime and section-owned release transition. Full final checks follow. The ticket remains in progress; the parent integrates and closes it.

Final reader/crossing check after direct fixes: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded test/reader test/crossings` — 1,666 passed, 21 configured skips, no failures, 3m04s (`/tmp/boo-rcgf-review-reader-crossings.log`).

Final full check after direct fixes: `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded` — 3,262 passed, 25 configured skips, no failures, 4m49s (`/tmp/boo-rcgf-review-full.log`). Final affected analysis: `nix develop --command flutter analyze --no-pub lib/reader/epub test/reader/epub test/research/epub_layout_cache_test.dart tool/reader/layout_cache_probe.dart` — no issues (`/tmp/boo-rcgf-review-analysis.log`). Nix continues to print the existing missing iOS SDK warnings; the host checks completed successfully. No pre-existing test failure is claimed, and all intentional red reproductions and intermediate implementation failures are recorded above.

Final formatting repeated the exact 13-path `nix develop --command dart format --output=none --set-exit-if-changed` command recorded before review: 13 files, zero changes (`/tmp/boo-rcgf-review-format-check.log`). `git diff --check adb8c2bfc190fd7c6db9de166deecbf1baa6cba8` and `git diff --check` passed (`/tmp/boo-rcgf-review-diff-check.log`). C1, C2 and D1 are resolved with the evidence above; no product forks or material unverified review assessments remain. The single reviewer and all verification commands have finished. No second review, coverage, mutations, devices, package installation, checkout changes, push, PR or ticket closure were performed.

## Parent integration and closure — 2026-11-13

Integrated implementation `74bd228c94f7a806cf987487921542f118a91f88` as `00a91bc8` and direct review fixes `4e59d18a864df8488fd8813e19a0813f37de76ab` as `a0f23625c8a4aad1f83c272ef0e72041d029f09a`, on combined main after `5fea3b49ff9b998793e955376500c4c869907c94`. The only cherry-pick conflict was this ticket; both launch notes and child evidence were retained. All affected source, test and probe files match the completed child exactly. The parent inspected the complete implementation, the review and the documented direct fixes; no additional integration blocker was found. All three review findings have recorded resolutions with evidence. No redundant second review was launched.

Combined verification at `a0f23625c8a4aad1f83c272ef0e72041d029f09a`:

- `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded`: 3,294 passed, 26 existing/opt-in skips, zero failures, 4m43s. Log: `/tmp/boo-rcgf-integrated-full.log`.
- `nix develop --command flutter analyze --no-pub lib/reader/epub test/reader/epub test/research/epub_layout_cache_test.dart tool/reader/layout_cache_probe.dart`: no issues, 3.0s. Log: `/tmp/boo-rcgf-integrated-analysis.log`.
- The exact 13-file format-check command recorded above: 13 files, zero changes. Log: `/tmp/boo-rcgf-integrated-format.log`.
- `git diff --check 5fea3b49ff9b998793e955376500c4c869907c94 HEAD`, working-tree diff check, and equality with the completed child's affected files all passed.

Closed after local integration. Parent commands finished. Device acceptance remains blocked by the existing Device panel failure; coverage and mutation testing await user acceptance. No device, push, PR, publication or live deployment was performed.
