---
id: boo-ystu
status: open
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

