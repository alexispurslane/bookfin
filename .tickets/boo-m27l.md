---
id: boo-m27l
status: open
deps: []
links: []
created: 2026-11-09T21:51:13Z
type: epic
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Give ebooks the same bookmarks, reading history and jumps through history as audiobooks

Requested by the user on 2026-11-09: add bookmarks, location history and jumping between history entries to ebooks, like audiobooks have, reusing as much of the same interface as possible. Today an ebook has reading bookmarks (TextBookmark, the bookmarks tab of the contents sheet, the shared bookmark editor), but no reading history, no history timeline, no Undo after a jump, no quick bookmark tool and no bookmark marks on the scrub bar. The audiobook design is in docs/plans/bookfin.md ("Quick bookmarks, history timeline, and stacked glass", and the personal record store and sync sections). The design doc for this epic is docs/plans/reading-history.md.


## Design (2026-11-09)

Design doc: docs/plans/reading-history.md. A correction to the request text above: the reader already saves an untitled bookmark with one tap, and its scrub bar already shows bookmark marks. The new work is the Bookmarked state, reading history, the timeline and Undo.

Three product decisions are open and listed at the top of the doc: one timeline per book or per medium, whether reading visits appear in history, and where History opens in the reader. The orchestrator asks the user.

Order of work: t9-of05 and t9-mdsj, then t9-mqtx, t9-nnon, t9-4vsl, t9-9ffz, t9-7fxw, t9-gtps. The dependencies are recorded with tk dep.
