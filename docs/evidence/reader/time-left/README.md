# The time left in the chapter and in the book (boo-02sx)

Date: 2026-11-09. The images come from a disposable emulator with a debug build of the branch. The emulator was AVD `boo-02sx`, Android 36, Pixel 7 profile, deleted after the check. The app signed in to the synthetic server `tool/showcase_fixture.dart` through `adb reverse`. The server ran with `--long-ebook`. So the ebook of "Salt and Lantern" is the public-domain Standard Ebooks Frankenstein. It has 468 pages at the default text size on this screen.

The reader went to Letter IV from the contents. The emulator then turned seven pages. The last six turns came about 20 seconds apart. The speed shows after the fifth counted page.

| Image | What it shows |
| --- | --- |
| `01-label-time-left-in-chapter.png` | The bottom bar label: "Letter IV · Page 50 of 468 · 3 min left in chapter". |
| `02-contents-time-left-in-book.png` | The glass contents sheet over the same page, with "2 h 20 min left in book" above the contents. |

The book has 418 pages after page 50. At about 20 seconds a page, they take about 2 h 20 min. So the estimate agrees with the pace of the turns.
