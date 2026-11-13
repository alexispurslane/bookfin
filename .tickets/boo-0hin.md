---
id: boo-0hin
status: in_progress
deps: [boo-f9xa]
links: [boo-f9xa, boo-p9s3, td-rbtc, td-ez6p, te-t5oi]
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give the PDF a pager that the reader session owns

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `_PdfViewportState` (lib/reader/pdf_viewport.dart:94) implements `DocumentNavigator`. The widget State loads pages, requests text and OCR, runs the whole-book search, draws previews and keeps the place, and the shown place has three copies. The EPUB has an `EpubPager` that the session owns. The session branches on the format in about 12 places. `onReady` runs 2 to 3 times for each page turn. Each call builds `pageCount` contents entries and fires `documentChanges`, which rebuilds the viewport, the scrub bar and the dock (pdf_viewport.dart:277, 309, 335, lib/reader/session.dart:206-218). Create a `PdfPager` that the session builds at open, attach the navigator and the contents once, and let `PdfViewport` only draw and report gestures. Closed ticket t9-3n2m set this target.


## Notes

**2026-11-13T02:49:40Z**

The boo-f9xa review fix adds DocumentNavigator.reportPendingPlace(). The session calls it before a background save or book release. Keep this interface when the session owns the PDF navigator. The viewport holds these states today only because it is the navigator: the 50 ms late-report timer (_latePlace), the reported flag (_placeReported), and the place that waits (_address). It also keeps the last reported address and screen (_reported) to suppress repeats while distinguishing word screens whose text is still missing. Move these states to the PDF pager with the navigation work. This change does not start boo-0hin.

The final boo-f9xa correction also keeps the requested page's visibility in the navigator. _pageShown becomes true only after a content frame (or the word renderer's existing shown-screen callback). _appearance lets navigation wait for that frame, and completes on abandonment or draw failure as well. These belong with the navigation state when it moves into PdfPager. The view must report what it actually displayed; a requested page or a completed raster alone is insufficient.

Integration correction 9a5a13f9 refines the failure rule above: a raster failure alone cannot end navigation while recognition may still produce usable text. `_finishUnavailablePage()` waits for text to settle without usable text or word content before releasing failure. Usable text must appear and report History before navigation completes. Preserve the held-raster regression and all displayed-page tests during extraction.


## Astra implementation launch

Review base: 3e345a1737fd0312e3fb6b5575eddf7de9ea2df1. Separate T3 worktree; implementation and direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. One fresh read-only reviewer is authorized with the same provider/model and reasoningEffort high. No other stage agents. Required checks include affected suites/analysis and the full Flutter suite through nix develop with concurrency at most two. Parent owns integration and closure.

Client request ID: bookfin-boo-0hin-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-0hin-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-0hin-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-0hin-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.
**2026-11-13T04:06:40Z**

Implementation in t3/pdf-reader-pager, starting from review base 3e345a1737fd0312e3fb6b5575eddf7de9ea2df1. ReaderSession now creates PdfPager at PDF open, attaches navigation and source-page contents once, applies PDF preferences directly, and disposes the pager before its document. PdfBook still owns document text and recognition. PdfViewport draws pager data, subscribes to the pager's pageChanges signal, reports measured layout and actual completed frames, and sends gestures/retry/copy upward. It has only selection and zoom state. Search, preview rendering, requested versus displayed state, pending-place timer, report suppression by address AND screen, and the appearance wait moved together into PdfPager. The raster-failure rule still waits for text to settle without usable content. Interfaces and on-demand invariants document ownership.

Five new tests cover navigation/contents before any viewport, page updates without document notifications or new contents, view replacement retaining a pending place and text request, detached navigation waiting for an actual frame, and a viewport swipe reporting intent without moving on its own. The real-session word-screen History regression now runs through ReaderScreen and its session-owned pager. Existing standalone viewport fixtures use a test-only controller that owns their pager; no fixture option was added to production. The word-view probe was migrated to own its pager too.

Initial red evidence: /tmp/boo-0hin-red-ready.log: 0 passed, 2 assertion failures (ready=false before mounting; one page turn emitted 2 document notifications). /tmp/boo-0hin-red.log could not run before Flutter dependencies were resolved, and is not red evidence. First extraction attempt /tmp/boo-0hin-extraction-first.log had 2 load failures from a missing WordSettings import; corrected before behavior verification. /tmp/boo-0hin-extraction-green.log: 50 passed, including all existing pdf_place tests. /tmp/boo-0hin-boundary.log: 67 existing viewport/text/word tests passed; new test file had one load failure from two misnamed test calls. Corrected /tmp/boo-0hin-boundary-fixed.log: all 5 new tests passed.

First complete reader/crossings run /tmp/boo-0hin-reader-crossings.log completed: 1623 passed, 21 skipped, 4 failures. Three were load failures from old viewport setting getters in fixtures. The other was landing_words_test expecting audio-time fallback until a PDF viewport mounted. The session now attaches its PDF map at book open, so History can name the estimated source page and chapter before mounting; navigation still waits for the content frame. Updated this test to verify that earlier metadata and preserve its real Go to/History checks. /tmp/boo-0hin-consumers.log: all 75 tests in landing_words_test, pdf_word_view_test, session_reflow_test, screen_rebuild_test and pdf_preferences_store_test passed after these fixture updates. Final complete reader/crossings and full suite checks remain to be recorded below.

Affected analysis initially reported 7 style infos; fixed. Broad analysis of lib/reader, test/reader, test/crossings and tool/reader/word_view_probe.dart then reported no issues (/tmp/boo-0hin-analysis-final.log). Its subsequent format check found one test helper requiring formatting; applied it before the final runs. No device work, coverage, mutation campaign, push or ticket closure. Host tests emit nonfatal missing iPhone SDK diagnostics; these are not device acceptance.

Preferences are unchanged. The base and the November 10 plan supersede the earlier per-app-run choice with per-book durable PDF view/margin preferences. This extraction preserves that existing behavior and all preference tests; it does not alter settings or sync event timing. td-rbtc, boo-p9s3 and t8-dqir remain out of scope. Existing whole-page synchronous text layout remains tracked by boo-yzvv. New te-t5oi records the existing whole-page PDF search matching on the UI isolate, moved unchanged by extraction; no timing measurement is claimed.

**2026-11-13T04:14:05Z**

Final build verification completed through nix develop on 2026-11-12, one command at a time with Flutter concurrency 2:
- flutter test --no-pub --concurrency=2 --reporter expanded test/reader test/crossings: 1652 passed, 21 skipped, zero failures, 2m54s. Log /tmp/boo-0hin-reader-crossings-final.log.
- flutter test --no-pub --concurrency=2 --reporter expanded: 3201 passed, 25 skipped, zero failures, 4m44s. Log /tmp/boo-0hin-full.log. This is baseline 3196 plus five ownership tests.
- dart analyze lib/reader test/reader test/crossings tool/reader/word_view_probe.dart: no issues. dart format --output=none --set-exit-if-changed on all 17 changed Dart files: zero changes. git diff --check: clean. Log /tmp/boo-0hin-checks-final.log.
All owned commands finished successfully. Existing opt-in corpus/benchmark and external fixture skips remain limitations. No Android or iOS verification was attempted. The one authorized independent Astra review is next; the ticket remains in progress and only the parent integrates/closes it.
