---
id: boo-cldw
status: in_progress
deps: [boo-kf2g]
links: []
created: 2026-11-11T00:07:15Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Explain the Flutter EPUB renderer and measured engine performance on the homepage

User requests a dedicated root index.html section about the built-in Flutter EPUB reader/renderer, a performance table comparing it to WebView and KOReader, and the shared cross-platform Flutter implementation. Use repository benchmark evidence with exact metric/hardware/method scope; do not fabricate apples-to-apples timings or imply all platforms ship. Preserve PDF/History sections and cream style. User has deferred live Tangled Sites investigation.


## Notes

**2026-11-11T00:08:31Z**

Continued Sol xhigh homepage leaf on t3/foreground-pdf-reflow. taskId node:delegated-task:command%3Amcp%3Aff882773-a396-4499-bcf0-cd83fba58315%3Athread-send%3Asol-xhigh-homepage-epub-comparison-20261110-1; childThreadId thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-54l1-homepage-1; clientRequestId sol-xhigh-homepage-epub-comparison-20261110-1. Evidence-led comparison and cross-platform renderer claims; no heavy benchmark jobs, devices or live-site deployment. Parent handles release build in parallel.

**2026-11-11T00:14:43Z**

User requests new same-emulator shell-app comparison for KOReader engine, Android WebView and current Bookfin EPUB engine. Supersedes historical timing table plan. Writer steered to continue section layout/verified architecture copy while leaving numeric comparison pending boo-kf2g. Parent will supply reviewed results; no live-site troubleshooting.

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

**2026-11-11T00:32:07Z**

Integrated prepared section from 432bdcc after parent inspected complete diff and implementation/platform sources. Resolved ticket-only merge conflict by preserving benchmark dependency and both sets of notes. Parent Nix markup/assets check passed:12 images,46 references, one accessible table, preserved PDF/History/reader sections and existing source/install links. Full-document T3 previews at390px Cream and1280px Night visually inspected with embedded bundled fonts and all image paths resolved; desktop check reports pageWidth1280,fonts loaded,12 images loaded,table1180px with no overflow. Phone EPUB section retains horizontal table scrolling within the page. No app code changed or Flutter suite rerun. boo-cldw remains in_progress pending boo-kf2g new emulator measurements and final numeric table; this is integration of the prepared section only. Live-site investigation remains deferred.
