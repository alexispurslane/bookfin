---
id: boo-iv7q
status: in_progress
deps: []
links: []
created: 2026-11-12T03:24:46Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Always draw EPUB and MOBI text in the reader font, never the book's embedded fonts

User decision 2026-11-12: "Override book fonts all the time. That's the easy solution there." This replaces the earlier option of keying the kept page on font files.

Today the reader registers a book's `@font-face` fonts (lib/reader/epub/fonts.dart, BookFonts; loaded in page_source.dart before a section lays out) and draws runs in them. boo-sy2d keeps no last-page picture for such books, so they reopen with about 35 ms of blank paper.

Build:
- Text that names an embedded family draws in the reader font. The book's font files are never read or registered.
- Remove the code that only served embedded fonts (BookFonts, the font wait before layout, the faces carried in a prepared section, the kept-page exclusion for books with own fonts), and its tests. Keep CSS parsing of `@font-face` only if something else still needs it.
- Generic families that the reader already maps (for example monospace for code) keep their current behavior.
- Kept pages then apply to every EPUB and MOBI. The text engine fingerprint changes, so old kept pages and page maps are rebuilt, never misused.

## Notes

**2026-11-12T12:17:36Z**

Built on t3/0d731f4f: the prepare worker passes over a family that the book embeds like any family that the reader lacks; BookFonts, the font wait, PreparedSection.fonts, SectionSource.fontPrefix, @font-face parsing and the kept-page family check are gone. No fingerprint code change: the Android fingerprint holds lastUpdateTime, so the update that ships this gives new page map and kept page keys (test/reader/update_forgets_layout_test.dart). Follow-up: t0-sx00 (font files still in the admitted record).
