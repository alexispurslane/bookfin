---
id: t6-0cjf
status: closed
deps: []
links: []
created: 2026-11-08T16:46:14Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Next chapter can stay on the same page when a chapter starts in the middle of a page

The dock's Next chapter arrow (boo-bz3x) goes to the first chapter that starts after the visible place, which is the start of the shown page. When a chapter starts in the middle of the shown page, as in an EPUB section with several contents entries, that chapter's page is the shown page, so a tap does not move and the arrow seems stuck. The showcase books start each chapter in its own file, so it does not show there. A fix needs the end of the visible page as a text progress, which the epub engine reports for previews (PagePicture.end) but not for the visible location.


## Notes

**2026-11-08T19:23:53Z**

Absorbed by tc-zevb (epic boo-b2ey). The native pager reports the shown page's end (ReadingLocation.end), and moveChapter uses it. Close when tc-zevb merges.

**2026-11-08T22:37:51Z**

tc-zevb (branch t3/c351d7f2) fixes this for pages that the native pager reports: BookMap.chapterStep steps forward from the shown page's end (ReadingLocation.end), so a chapter that starts on the shown page is skipped. Tests: test/reader/book_map_test.dart 'the chapter arrows' and the session test 'next chapter skips a chapter that starts in the middle of the shown page (t6-0cjf)'. The app still uses the WebView reader until tc-1yif, which reports no end, so the arrow keeps the old rule there. The first page after opening at a saved place also has no end; ticket tc-klz2 covers that.
