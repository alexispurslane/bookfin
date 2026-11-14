---
id: boo-f2gn
status: closed
deps: []
links: [t8-oitu, t1-jh0y]
created: 2026-11-08T03:16:28Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Listen on a book that is not downloaded looks ready but only shows an error

Found on the Pixel 8 on Nov 7 (build 1abdb6b). The book page of an audiobook that is not downloaded shows an enabled Listen button next to the download button. A tap shows 'Download every file in this audio edition before listening.' and nothing else happens. Check the plan (docs/plans/bookfin.md) for whether streaming is intended. If playback needs a download, the primary button must say so and do it, for example 'Download to listen' that starts the download and plays when it is done, or show the download progress in place of Listen. Do not show an enabled action that can only fail.


## Notes

**2026-11-14T17:02:38Z**

Fixed by boo-qgt6: Listen on an audiobook that is not downloaded shows a download icon and downloads it.
