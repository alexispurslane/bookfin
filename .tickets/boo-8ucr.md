---
id: boo-8ucr
status: open
deps: []
links: []
created: 2026-11-09T14:42:53Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Refine the footnote sheet's spacing and alignment

User request (2026-11-09): the footnote sheet still looks awkward, with uneven top and bottom spacing. Seen in docs/evidence/reader/native/glass-sheets/01-note-sheet-cream.png: a tall gap between the title row (Note, Go to note) and the note text, but a short gap below the text; the note text starts far right of the title (the list marker '2.' sits about where the title text starts, then a wide gap, then a first-line indent); the note text's left edge does not line up with the heading. Likely causes: PreparedSection.excerpt keeps the open boxes' margins (body, section, ol, li, p) at the top, while the bottom margins collapse or are cut; the paragraph's text-indent and the list's padding stay as on the page. Goal: even, deliberate spacing (the same space above and below the note text, chosen from the glass sheet's spacing scale), the note's text aligned with the sheet's heading, the list number placed so it reads as a label, not as a stray gap, and a sheet that looks finished for short and long notes, single and multi-paragraph notes, and notes without a number.

