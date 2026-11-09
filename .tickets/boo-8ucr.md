---
id: boo-8ucr
status: in_progress
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


## Notes

**2026-11-09T15:43:35Z**

Built. PreparedSection.excerpt lays a note out as a fragment of its own: the boxes around the note are left out, the note's box is the root without margins, top margins that meet the top are cut, the first paragraph has no first-line indent, and the list number comes before the first word as a label that no node owns (RaisedRun with node -1). BlockStart gains node, the element's order. glass.dart owns the text inset (20) and the space below text (28, the corner radius); the note sits right under the title row. A long note fades into that space and under the title row once it scrolls. The title row keeps its heading whole at large text sizes and moves the action under it. Measured on the device for note 2: 32.8 dp above, 30.5 dp below (before: 50.7 and 18.7). Page layout unchanged: fidelity results byte for byte, corpus for se-frankenstein and se-alices-adventures-in-wonderland the same. Evidence in docs/evidence/reader/native/footnotes/refined/. New ticket t6-dy2q.
