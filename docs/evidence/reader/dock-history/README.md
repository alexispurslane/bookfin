# History, Bookmarked and Undo in the reader dock (t9-7fxw)

Date: 2026-11-09. The images come from a disposable emulator with a debug build of main at commit 3ac7734. The emulator was AVD `t9-7fxw-accept`, Android 36, Pixel 7 profile, deleted after the check. The app signed in to the synthetic server `tool/showcase_fixture.dart` through `adb reverse`. The book is First Frost, which has an audiobook and a short EPUB of 4 pages in three chapters.

All input went through the T3 Device panel's `agent-device` command. Before the reader check, the person downloaded the EPUB edition, started the audiobook and paused it. An open audiobook adds the round cover button to the dock.

## Checks

| Check | Result | Image |
| --- | --- | --- |
| The dock tools in order: Contents, Search, Aa, Bookmark, History, then the cover button. | Pass | `01-dock-tools.png` |
| A tap on Bookmark saves a bookmark, and the tool reads Bookmarked with a filled icon. | Pass | `02-bookmarked.png` |
| A second tap opens the glass "Edit bookmark" editor with the place line "On p. 1 · One. The Grafted Trees". The person named the bookmark "The grafted rows". | Pass | `03-edit-bookmark.png` |
| After a page turn to page 2, the tool reads "Bookmark this place" again. The scrub bar keeps the bookmark mark at page 1. | Pass | `04-after-page-turn.png` |
| A search for "ledger" and a tap on a result jumps from page 2 to page 4. The Undo row "Your previous place is saved" shows above the place label. | Pass | `05-search-results.png`, `06-undo-row-after-search.png` |
| Undo returns to page 2, and the row closes. | Pass | `07-after-undo.png` |
| The contents sheet has no tabs. It lists the three chapters. | Pass | `08-contents-no-tabs.png` |
| A jump through Contents from page 2 to chapter three shows the Undo row. Dismiss hides the row, and the reader stays on page 4. | Pass | `09-undo-row-after-contents.png`, `10-after-dismiss.png` |
| The Undo row coming or going does not move the page. | Pass | `11-page-still-with-and-without-row.png` |
| History opens the shared glass timeline. It lists the reading entries: the bookmark, the search jump, the Undo and the chapter change, with the listening entries. | Pass | `12-history-timeline.png` |
| A tap on the bookmark entry shows "Go to p. 1", Rename and Delete. | Pass | `13-history-entry-go-to.png` |
| Go to moves the reader to page 1 and offers Undo. A tap on that Undo returned to page 4. | Pass | `14-go-to-offers-undo.png` |

## How the page check works

`11-page-still-with-and-without-row.png` puts the lower part of images 09 and 10 side by side. The text lines are at the same pixel rows in both images. A pixel comparison of the screen from y = 100 to y = 1850 found differences only from y = 1799 to y = 1850. That band is where the taller dock covers the last line of the page, "Now she was not so sure.", while the row shows. The dock lies over the page, so the row covers text but does not lay out the page again.

## Flaws found

- The contents sheet has no heading. The Contents tab used to name the sheet, and the tabs went away. ta-ycs0 records it.
- In the bookmark editor, the floating label "Title (optional)" overlaps the bottom of the place line. The t9-9ffz images show the same overlap. ta-2hat records it.
- The saved quote joins the chapter heading and the first paragraph without a space ("TreesWren"), in image 13. t5-bmal already records it.
