---
id: boo-3huo
status: open
deps: []
links: []
created: 2026-11-12T12:41:26Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Load a book's own font only for characters that the reader font lacks

User decision 2026-11-12: "I agree with the lazy font loading planned by the way. I definitely want that." It follows boo-iv7q (always draw in the reader font) and replaces t0-sx00.

Model. Admission (at download completion, in the worker) already reads every chapter. During that pass it finds runs whose style names one of the book's embedded faces and checks each character against the reader font's character coverage, which is known ahead because the font ships with the app. A face is needed by a chapter when it covers a character of such a run that the reader font lacks. The admitted record keeps only the needed font files and, per chapter, the needed faces. Most books need none.

At open nothing new runs for a book that needs no face. A chapter that needs faces loads only those faces (registration on the UI isolate, conversion off it) before it lays out, and only those characters draw in the book's face; all other text stays in the reader font. The kept last page is still shown in the first frame unless the shown page uses a book face; key it on the face files if that is cheap, else skip only those pages.

Known limits, accepted: ornament fonts that map shapes onto ordinary letters are not detected, and only the reader font's coverage is checked, not Android's system fonts.

Costs: a new Publication.revision, so every downloaded book is admitted again once and its page maps are rebuilt. t0-sx00 (drop unused font files from the record) is folded in here.

