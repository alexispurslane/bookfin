---
id: boo-klgn
status: closed
deps: []
links: []
created: 2026-11-11T11:31:14Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Tighten homepage sections and average EPUB benchmarks

Review the whole homepage against the original structure. Remove repetition from added History, PDF and EPUB content; group reader features coherently; replace three book tables with one equally weighted average across books. Retain original intro and established aesthetic.

## Acceptance Criteria

Concise nonrepetitive feature copy, one reader explanation, PDF comparison stays in its section, one benchmark table verified against raw evidence, mobile and desktop visual checks.


## Notes

**2026-11-11T11:36:11Z**

Reorganized new material within the existing chapter structure: Reader owns EPUB implementation, controls and performance; PDF owns its comparison and scan/view details; History has three action bullets beside its real capture. Removed duplicate reader explanations and redundant screenshot captions, from 1,235 to 408 words across changed sections. Original hero, Why, Shelf, Player, Sync and Setup content preserved (chapter numbering updated). One table shows arithmetic mean elapsed time, each book equally weighted. Derived from 1,404 accepted raw samples; all 15 displayed values independently matched Decimal pooled means with equal counts. Per-book counts/sums and source hash retained in averages.json. Nix-hosted markup/asset checks pass: 14 image/source dimensions, 42 references, one accessible table. Full-page T3 previews at 1280px Cream and 390px Cream/Night loaded fonts/images with no page overflow; table focus and contained horizontal scrolling checked. Details in docs/marketing/epub-renderer/verification.json. No application code, new benchmark run or device work.
