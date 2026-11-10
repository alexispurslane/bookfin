---
id: tb-9mcf
status: open
deps: [tb-22fu]
links: [te-rtok]
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Choose original pages, word view or text view for PDFs in Reading settings

W7 of docs/plans/pdf-word-image-reflow.md (The switch to the text view, open decision 1). Replace ReaderSession's reflow bool with one enum of three values that lasts for the run of the app (t9-3n2m). Build the control in the glass Reading settings sheet in the shape that the user picks in open decision 1. Do not start before the user settles decision 1.

## Acceptance Criteria

Behavior tests, red first: the choice lasts through closing and opening books in one run and a new run starts on the original page; the control shows only for PDFs; turning reflow on shows the word view; the text view shows the reading text in the reader's font. The sheet stays glass. Existing reflow tests pass with the enum.

