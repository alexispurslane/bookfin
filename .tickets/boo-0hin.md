---
id: boo-0hin
status: in_progress
deps: [boo-f9xa]
links: [boo-f9xa, boo-p9s3, td-rbtc, td-ez6p]
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
