---
id: tc-klz2
status: open
deps: []
links: []
created: 2026-11-08T22:37:50Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Let Next chapter skip a chapter on the first page after opening at a saved place

When the pager opens at a saved place, it reports the saved address object itself, unchanged (design rule 1 of "Places / Data safety"). A saved address has no page end (ReadingLocation.end is not saved), so BookMap.chapterStep steps forward from the page start only. On the first page after opening at a saved place, a chapter that starts in the middle of that page makes the Next chapter arrow stay on the same page, as in t6-0cjf. A turn, a seek or any other move reports a fresh address with its end, so the fault lasts only until the first move. Two ways out: the pager reports a copy of the saved address with the shown page's end added (the saved JSON stays identical, because toJson leaves end out, but the object is no longer the same one), or the session asks the pager for the shown page's end. Found in tc-zevb.


## Notes

**2026-11-08T22:42:56Z**

Decision (orchestrator, 2026-11-08): the second option. The pager keeps reporting the saved address object unchanged (design rule 1), and the chapter step reads the shown page's end from the pager, because the shown page owns its end. Done together with tc-1yif.
