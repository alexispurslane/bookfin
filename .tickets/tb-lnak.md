---
id: tb-lnak
status: in_progress
deps: [tb-z9h5]
links: [ta-ukpf]
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Survey a PDF's pages in the background for one book crop, and keep it on disk

T2 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: The book crop, The survey). PdfBook owns a background survey: it analyzes pages at the lowest priority (behind the shown page, its next page and search), in an order that first samples the book evenly (up to 32 body pages for each side), then the rest. Scanned pages get their layout pass on the recognition worker, and the record is kept. From the sample it freezes the book profile: header and folio templates, the side phase, and one box for left-hand and one for right-hand pages, from the 5th and 95th percentiles of the body pages' content edges, padded by half a body line height. Blank pages, pages with fewer than 5 text lines and pages that are more than half picture are outliers and do not count. Each page's crop is the union of its side's box and its content box. Profile and page boxes are kept in a new DerivedBookFiles directory of the download, written atomically in batches; the survey resumes where it stopped at the next open and pauses while the book is closed or the app is in the background.

## Acceptance Criteria

Behavior tests, red first: a cover, a plate and a blank page in the fixture book do not change the side boxes; every body page of a side gets the same crop; a page with a wide table or a margin figure gets a larger crop that holds all its content; a page whose parity is flipped by an inserted plate takes the other side's box when only that box fits it; the profile does not change after it freezes; a kill during a write leaves the old or the new file; a reopen resumes the survey and runs no page twice; the survey never delays the shown page's layout pass or recognition. checkInvariants: every page crop holds its content box, and every body page's crop equals its side box.


## Notes

**2026-11-10T15:22:46Z**

From tb-z9h5: findRunningTemplates(pages) runs in a hop and gives RunningTemplates; templates.mark(page) gives the PageAnalysis with runningLines, and analysis.contentBox(geometry) the content box. The templates are public fields (texts, folioOffsets, shapes, lineHeight) for the profile on disk. Limits: (1) a chapter's running header gets a text template only if the sample holds 3 of its pages within 20 source pages, so a sparse sample misses per-chapter headers, and those pages keep the header as content and grow their crop; (2) on pages with text only the text and folio templates apply, not the geometry ones; (3) a page whose text arrives after the profile freezes is marked by text, not geometry, so its marks can differ from its earlier marks. See docs/plans/pdf-word-image-reflow.md, Running headers and folios.

**2026-11-10T16:01:39Z**

Built: lib/reader/book_crop.dart, book_survey.dart, survey_files.dart; PdfBook.survey; background requests in PdfBook.reflowPage and in the recognition queue; ReaderSession.suspend/resume and surveyStore. For tb-valc: PdfBook.survey.cropOf(page) gives a page's crop or null, and survey.crops notifies when crops become known. For tb-m8xo: survey.profile.templates marks running lines. Limits are in docs/plans/pdf-word-image-reflow.md, after 'The survey'.
