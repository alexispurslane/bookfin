---
id: tb-m8xo
status: in_progress
deps: [tb-lnak, tb-0mex]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Leave running headers and folios out of the PDF word view

T5 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: Page words). layoutColumn skips the lines that the page analysis marks as header or folio. Their text stays in the reading text, so search still finds it. A place inside a skipped line resolves to the first shown piece after it.

## Acceptance Criteria

Behavior tests, red first: the word view of the fixture book shows no running header and no folio; footnotes and figures still show; search for a header word opens the page's first screen; a place inside a header opens the screen of the next shown word; the screens of a page do not change when its text arrives.


## Notes

**2026-11-10T16:45:11Z**

Built (2026-11-10). ReflowPage.column marks the analysis with the frozen profile's templates through ReflowPage.templateReading (text layer text only; a scanned page's recognized text never counts), which BookSurvey._survey now also uses, so the word view and the crop agree. layoutColumn skips running lines and running regions (and their captions). ReflowColumn.screenAt(character, ranges, analysis) gives the screen of a place: the first shown word whose range holds or follows it, else the last screen. For tb-22fu: a column asked for after the profile freezes leaves out lines that an earlier column showed, so keep the shown page's column until a turn or a new size. Tests: test/reader/column_running_lines_test.dart.
