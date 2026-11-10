---
id: boo-54l1
status: in_progress
deps: []
links: []
created: 2026-11-10T21:56:07Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Foreground PDF word reflow and shared position history on the homepage

User asks to update repository-root index.html: foreground PDF reflow that retains original word images and figures/charts while adapting text size and theme. Include a real before/after of the same public page in Original and Page words. Emphasize position history for audiobooks and ebooks. Inspect implementation and tickets before claiming both histories and current locations are accessible from either medium’s navigation. Preserve visual identity and responsive accessibility. Do not imply arbitrary source layouts remain pixel-identical after reflow or promise unsupported unlimited font sizes. Use actual renderer evidence with clear provenance, no private book assets. Implementation documentation/copy task; parent checks final result.

## Acceptance Criteria

Homepage leads with accurate PDF reflow value and a meaningful same-page comparison; history claims map to implemented behavior; responsive layout and asset paths verified; no private content or fabricated app screenshots.


## Notes

**2026-11-10T21:58:23Z**

Launched Sol xhigh writer from c9200c0; taskId node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-54l1-homepage-1; childThreadId thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-20261110-boo-54l1-homepage-1; clientRequestId sol-xhigh-20261110-boo-54l1-homepage-1. Root homepage/public captures only; no devices, children or app changes. Parent inspects content and browser result. Confirmed shared history ticket closed; no separate combined current-location rows in timeline, so exclude that claim.

**2026-11-10T22:17:20Z**

Implemented the settled homepage emphasis at base c9200c085612a0978dd56d4fa1ac943c1f92a67d. Root index.html now leads with PDF word-image reflow, a same-page Original versus Page words comparison, and both listening and reading histories. Kept cream/sepia styling, local bundled fonts, the original showcase art and feature sections, and source/build links. Added a skip link and main landmark. No changes to web/index.html, application code, reader plans, or sibling tickets.

Generated genuine production PdfViewport host-renderer captures of the same public-domain Library of Congress Raven scan page 9: Original, Page words Cream size 24, and Page words Night size 28. Recorded source PDF/geometry/text SHA-256 hashes, output hashes, capture settings, and provenance under docs/marketing/pdf-reflow/. Public source metadata fetched again and confirmed title, year 1873, and public-domain reuse rights. Three WebP assets total 202570 bytes; no private assets, HTML screenshot recreations, devices, or emulators used.

Verified shared-history claims by inspecting lib/playback/timeline.dart, ReaderSession.timeline(), Playback.timeline(), all three entry points, shared_timeline_test.dart, reading_timeline_test.dart, and history_test.dart. t9-9ffz and t9-7fxw are closed. The copy advertises combined action/bookmark histories and Go to opening the chosen medium, not a pair of live/current resume rows. Adjustable size is bounded by the existing controls (14–40). No durable per-book view/trim claim was added.

Verification: Nix host capture harness passed (1 test, 3 captures). General markup/asset check passed (12 images with dimensions and alt text, 39 links/asset paths, 14 unique IDs, balanced tags). git diff --check passed. T3 html_preview targeted header/intro/comparison at 390 CSS pixels and Night comparison at 1280 pixels showed no horizontal overflow and loaded both images. Those targeted previews used fallback fonts because absolute local font URLs were blocked; parent still owns the final full-page browser check with bundled fonts. Full Flutter suite was not run for this HTML/content task. Optional missing iOS SDK notices did not prevent the host capture run.

Applied ultracode-orchestration (leaf ownership only, no children), software-design, impeccable (preserve existing visual system), plain-English guidance, and PDF guidance. No design fork. Ignored capture/check scripts and raw PNGs remain in .cache/ for parent inspection; no temporary capture test enters the test suite. Ready for parent inspection and integration; ticket remains in_progress.
