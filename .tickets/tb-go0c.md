---
id: tb-go0c
status: open
deps: [tb-lnak, tb-zx7r]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fval
---
# Leave running headers and folios out of the PDF text view

Found while designing the trimmed margins of docs/plans/pdf-word-image-reflow.md. The text view still shows the words of running headers and folios between pages' text, while the Original view and the word view drop them. The text view can skip the characters of marked lines in what it draws while the reading text and its offsets stay unchanged, so places keep their meaning.

## Acceptance Criteria

The text view of the fixture book shows no header and no folio words; search and places are unchanged; a place inside a header opens the screen of the next shown character.

