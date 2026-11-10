---
id: tb-fi98
status: in_progress
deps: [tb-22fu]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Float drop caps at the start of reflowed PDF paragraphs

W9 of docs/plans/pdf-word-image-reflow.md (Regions, drop caps). A drop cap is an ink region at a paragraph start, more than 1.8 body line heights tall, whose right edge touches the first word. It keeps the page's scale and floats at the paragraph start, and the paragraph's first lines (at most 3) get shorter beside it.

## Acceptance Criteria

Behavior tests, red first, on a fixture page with a drop cap (add one to the scanned or Typst fixtures): the drop cap shows whole at the paragraph start; the lines beside it are shorter and the line after it is full width; the paragraph's reading text and places do not change.


## Notes

**2026-11-10T14:59:40Z**

From tb-t8rh: on the Raven page, the drop cap O of 'ONCE' lies inside the layout word of its line (that line is 64 pixels tall at 1600 wide, the others 33). It is not a separate ink region, so a drop cap can come as an oversized first word of a line, not only as a region.

**2026-11-10T15:03:43Z**

From tb-t8rh: the Raven drop cap sits inside the first word's box, not in a region of its own.

**2026-11-10T20:32:18Z**

Launched from integrated base 2ef6bfa with codex/gpt-6.1-sol reasoningEffort=xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-fi98-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-fi98-1; clientRequestId: sol-xhigh-word-followup-20261110-tb-fi98-1. Separate T3 worktree; lead implements, one fresh read-only Sol xhigh reviewer, lead fixes. Parent integrates/closes and owns hardening. No physical-device UI input. Launch state: running; branch pending report.
**2026-11-10T21:09:03Z**

Implemented whole drop caps in the existing column model. Oversized opening words (including Raven's whole ONCE image) and ink regions share paragraph floating, at most three neighboring short lines, full width below the cap, and existing screen keep marks/band plans. No reading text, digest, attachment, page analysis, crop, viewport, settings, or record-storage code changes. Added public CC0 Typst/PDF opening-letter fixture and ten domain behavior tests. Red evidence: /tmp/bookfin-tb-fi98/red.log (four valid missing-behavior failures; initial OCR spelling assumption corrected), raven-red.log (expected two neighboring lines, got one), fit-red.log (a taller neighboring word split screens), full-test.log (ordinary ink anchored too early; expected region after piece 28, got piece 10). All fixed. Initial analysis found an unnecessary null assertion, unused import, and missing braces; fixed. Final Nix checks: dart format --output=none --set-exit-if-changed lib test tool integration_test: 395 files, zero changed; flutter analyze lib test integration_test: no issues; focused drop-cap tests: 10 passed; flutter test --concurrency=2 --reporter expanded: 2570 passed, 21 skipped, zero failures (4:05). Logs: /tmp/bookfin-tb-fi98/final-{format,analyze,focused,full-test}.log. Native code unchanged, so native OCR script not required. Flutter startup prints missing iPhone SDK notices; required host checks still pass. No devices operated, no coverage/mutation jobs. Independent review pending; ticket remains in progress for parent integration.

**2026-11-10T21:19:42Z**

Independent review complete for original base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f through implementation HEAD c162fe2d053bccea51129587f2158ebefce98cc5. Original verdicts: correctness pass, fulfillment pass, design pass; overall pass. No material findings, material unverified requirements, resolutions, or user-visible forks. The reviewer inspected the complete diff, fixture provenance and PDF hash, source/test ownership, meaningful red evidence, and final check logs under /tmp/bookfin-tb-fi98/. It confirmed reuse of the existing paragraph/column model and screen/band owners, both whole-word and separate-ink drop caps, the three-line limit, unchanged reading text and saved places, and preservation of the accepted surrounding behavior. Review was read-only with no independent builds, tests, devices, or delegates. Execution evidence remains the builder's completed Nix runs, corroborated by log inspection: format 395 files/zero changed, analysis no issues, focused ten passed, full suite 2570 passed/21 skipped/zero failures. Native OCR script remains not applicable because native code is unchanged. No performance claim is made. Parent owns sibling integration, device acceptance, coverage/mutation hardening, and ticket closure. This final review-note-only commit does not change the tested/reviewed implementation. Ticket remains in progress and ready for parent integration.

**2026-11-10T21:22:06Z**

Parent inspected complete implementation/test/design/fixture diff and review evidence. Fixture SHA256 matches documented provenance. Merged 1d151ac without production conflicts; combined both ticket histories. Parent Nix integration run passed all 89 tests across drop-cap, column, running-line, word renderer/view and Trim margins suites; /tmp/bookfin-drop-cap-integration.log. Production and test files exactly match tested/reviewed child HEAD; child full suite 2570 passed/21 skipped. No new device or performance claim. Phone installation will accompany the next combined reader update; user acceptance/hardening remain pending.
