---
id: boo-wokk
status: closed
deps: []
links: []
created: 2026-11-09T12:56:52Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Draw the note back link as text, and leave it out of the note sheet

Seen in docs/evidence/reader/native/footnotes/02-note-sheet-cream.png (tc-406m): the note's back link (Standard Ebooks writes U+21A9, a leftwards arrow with hook) draws as a color emoji, because the reader font lacks the glyph and the fallback reaches the emoji font. Chromium draws it as a text glyph. In the sheet the back link is plain text that does nothing, so leave it out there (an a element whose epub:type or role is backlink, doc-backlink, or whose href points back at the reference). On the page, draw U+21A9 and similar arrows with a text presentation (for example append U+FE0E or put a text-style symbol font before the emoji font in the fallback).

