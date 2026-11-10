# One History timeline for listening and reading (t9-9ffz)

Date: 2026-11-09. The images come from a disposable emulator with a debug build of the branch. The emulator was AVD `t9-9ffz`, Android 36, Pixel 7 profile, deleted after the check. The app signed in to the synthetic server `tool/showcase_fixture.dart` through `adb reverse`. The book is First Frost, which has an audiobook and a short EPUB of 5 pages.

The person played the audiobook, jumped ahead 30 seconds, paused, and used Undo. Then they read the EPUB and added a bookmark on page 3, in chapter two. The reader does not record reading jumps yet (t9-nnon), so the only reading entry is the bookmark.

| Image | What it shows |
| --- | --- |
| `01-mixed-timeline-in-player.png` | The History sheet in the player, opened over the reader. The bookmark on "p. 3" has a book glyph on the rail. The listening entries have a headphones glyph. The player behind the sheet steps back. |
| `02-reading-entry-page-chapter-quote.png` | A tap on the bookmark shows its chapter and its quote, then "Go to p. 3", "Name" and Delete. |
| `03-rename-reading-bookmark.png` | Name opens the shared glass bookmark editor over the sheet, with the place line "On p. 3 · Two. The Ledger in the Barn". |
| `04-renamed-reading-bookmark.png` | The timeline after the save. The choice now reads Rename. |
| `05-go-to-opens-reader-there.png` | The reader showed page 1 under the player. "Go to p. 3" in the player's History closed the sheet and the player, and the reader shows page 3. |
| `06-book-page-reader-closed.png` | The History of the book page, with no book open in the reader. The bookmark, now named "The ledger", reads as the first words of its quote, because no book map gives its page. |
| `07-go-to-from-book-page-opens-reader.png` | The saved reading place was page 1. Go to on the bookmark opened the reader at page 3. Back then returned to the book page. |

Two flaws show in these images:

- The saved quote joins the chapter heading and the first paragraph without a space ("BarnHer"). t5-bmal records it.
- Go to that opens the reader records no move and offers no Undo yet. t5-wyvf records it, after t9-nnon.
