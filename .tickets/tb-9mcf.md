---
id: tb-9mcf
status: in_progress
deps: [tb-22fu]
links: [te-rtok]
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Choose original pages, word view or text view for PDFs in Reading settings

W7 of docs/plans/pdf-word-image-reflow.md (The switch to the text view, decision 1 of 2026-11-10). Replace ReaderSession's reflow bool with one enum of three values that lasts for the run of the app (t9-3n2m). The user chose design A: the Pages row in the glass Reading settings sheet has three segments, Original, Page words and Text. Make the shared PillChoice usable at large system text sizes for every caller: when its segments do not fit the width, it first hides the icons and keeps the full labels, and if they still do not fit, it stacks the segments in a column in the same pill shape, each with a touch target of at least 48 by 48 logical pixels. Labels are never cut or shortened.

## Acceptance Criteria

Behavior tests, red first: the choice lasts through closing and opening books in one run and a new run starts on the original page; the Pages row shows Original, Page words and Text, and only for PDFs; at the largest system text size on a narrow phone, the row first drops its icons and then stacks, and every label stays whole and every segment can be tapped; the Theme row gets the same behavior; turning reflow on shows the word view; the text view shows the reading text in the reader's font. The sheet stays glass. Existing reflow tests pass with the enum.

