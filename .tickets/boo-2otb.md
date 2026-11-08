---
id: boo-2otb
status: closed
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Move whole-file and large-list work off the UI isolate

Audit P12, P14, P15: PDF open hashes the whole file twice on the UI isolate; every catalog notification rebinds Downloads, which hashes every source; the 2.4 MB city list parses on the UI isolate. Use compute or skip redundant work.


## Notes

**2026-11-08T02:52:41Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
