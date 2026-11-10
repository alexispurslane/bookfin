---
id: tb-pchn
status: open
deps: []
links: []
created: 2026-11-10T16:01:39Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fval
---
# Skip the survey of scanned PDF pages where Bookfin has no recognition

Found in tb-lnak. On a platform without recognition (textSupply is null, as on macOS today), a scanned page has no word geometry. The survey asks for each such page at every open: one text layer hop each, with no result, and the book never gets a profile. The survey can skip a page whose text layer is not a candidate when the book has no text supply, and record nothing.

