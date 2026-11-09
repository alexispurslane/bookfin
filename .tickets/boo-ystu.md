---
id: boo-ystu
status: in_progress
deps: []
links: []
created: 2026-11-09T17:13:34Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Research a disk cache for layout results

Requested by the user on 2026-11-09: if layout results can be cached on disk, work hard to do it. Research what can be kept between opens and launches: the true page starts of each section for each page settings value, prepared sections (styled runs, hyphenation points), and anything else that makes an open, a jump or the whole-book layout of t7-bbv1 faster. Find what makes a cached result valid (book identity, page settings, viewport size, text scale, fonts, hyphenation patterns, the layout code's version, Flutter's text engine version) and whether layout is deterministic enough for a cached page start to equal a fresh one. Measure size, load time and saved time on real books, and propose a design. No product code.


## Notes

**2026-11-09T18:18:48Z**

Research done in docs/research/epub-layout-cache.md. Keep the page map (true page starts per section and layout settings): 3 bytes a page, deterministic across processes and launches, equal when laid from a kept start for all 124,643 corpus pages. Do not keep prepared sections. Follow-up: t5-9tbu, t5-4lbx, t5-4l4d, t5-q0hs, t5-s1vy.
