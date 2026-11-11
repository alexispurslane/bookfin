---
id: boo-oegx
status: closed
deps: []
links: []
created: 2026-11-11T11:20:16Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Restore homepage opening and keep PDF reflow as a feature section

Restore the approved general-app intro, hero placement, Why copy and navigation. Move PDF reflow into the feature chapters; retain NU captures, shared History and measured EPUB tables.

## Acceptance Criteria

Original opening restored; coherent chapter order; mobile and desktop previews checked; benchmark numbers unchanged.


## Notes

**2026-11-11T11:21:55Z**

Restored exact hero, Why copy, title/description and header navigation from 1fd94309. Hero artwork is back inside the opening. PDF reflow is a normal feature chapter after Reader; contents and later headings are renumbered. NU captures, shared History, Reader and EPUB benchmark tables retained. Verified through Nix: balanced markup, 12 image dimensions, 54 references and 3 accessible tables. Exact-copy checks passed for original opening and all 45 median/p90 pairs against measured summary. T3 html_preview with embedded bundled fonts and loaded local images: 1280px light and 390px dark opening, plus desktop and phone PDF section; no horizontal page overflow. git diff --check passed. Content-only change; no Flutter or device changes. Live deployment investigation remains deferred under boo-qf93.
