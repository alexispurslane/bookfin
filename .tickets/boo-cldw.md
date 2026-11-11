---
id: boo-cldw
status: in_progress
deps: []
links: []
created: 2026-11-11T00:07:15Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Explain the Flutter EPUB renderer and measured engine performance on the homepage

User requests a dedicated root index.html section about the built-in Flutter EPUB reader/renderer, a performance table comparing it to WebView and KOReader, and the shared cross-platform Flutter implementation. Use repository benchmark evidence with exact metric/hardware/method scope; do not fabricate apples-to-apples timings or imply all platforms ship. Preserve PDF/History sections and cream style. User has deferred live Tangled Sites investigation.

## Updated measurement scope

The user now requests fresh same-emulator measurements of Bookfin, Android WebView, and KOReader in minimal shell apps. The parent owns those benchmarks. This leaf prepares the EPUB section and table with results pending, without publishing historical host timings or waiting for benchmark completion. No device or benchmark work is in this leaf's scope.

## Prepared implementation

- Added a dedicated EPUB chapter, navigation link, contents row, established feature bullets, and an accessible horizontally scrollable comparison table.
- Verified production Flutter EPUB layout, drawing, selection/Copy, links/notes, size/theme controls, and touch/keyboard/trackpad page turns. Explained shared code separately from Android/macOS delivery and the remaining platform ports.
- Added `docs/marketing/epub-renderer/README.md` with exact implementation sources, primary WebView/KOReader sources, and the pending measurement method. No historical performance numbers or rankings appear in the table.
- Preserved the PDF reflow, Nihil Unbound comparison, shared History, and existing installation/source links. No app, deployment, or sibling-ticket changes.
- Applied software-design for a scoped extension of the existing model, impeccable for the existing cream/sepia visual system and responsive table, and simple-English for the evidence note. No design fork or subagent was needed.

## Verification and remaining work

- `nix develop --command python3 .cache/boo-cldw/check_and_prepare.py` passed balanced markup, IDs, local links, evidence references, all 12 image dimensions, and table semantics. It also confirmed unchanged PDF/History/reader sections, existing external links, and installation commands. The checker and logs are ignored scratch, not added tests that mirror copy.
- Actual T3 `html_preview` checks passed at 390 px and 1280 px in Cream, plus 390 px in Night. Both bundled fonts loaded from data URIs. Page widths stayed within the viewport; the phone table scrolled inside its 350 px region. Night also confirmed keyboard focus and 322 px of horizontal scrolling. No server or device was used.
- `git diff --check` passed. No app code changed, so no Flutter build, full suite, or performance rerun was needed. All commands finished before handback.
- The timing cells remain pending the parent's fresh same-emulator results. The parent owns final full-page review, integration, and ticket closure; this ticket remains in progress.
