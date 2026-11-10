---
id: tb-a07f
status: open
deps: []
links: []
created: 2026-11-10T02:34:02Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Find PDF words that a line-end hyphen splits

Found while designing boo-fval (docs/plans/pdf-word-image-reflow.md, Rejoined hyphens). The PDF reading text keeps a line-end hyphen and a space, as in 'philo- sophy', so search for 'philosophy' finds nothing on that page, and copy gives the split word. The word view joins the halves only on screen. A fix must not change PdfText.source or its digest, because saved places name its characters. Search and copy can match and give the joined form through the reflowed text and its source offsets.

## Acceptance Criteria

Search for a word that a line-end hyphen splits finds it on extracted and recognized pages. Copy of a selection over a hyphen pair gives the joined word. Saved places and digests do not change.

