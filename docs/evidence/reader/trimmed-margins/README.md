# Trimmed margins in the Original view (tb-valc)

These screenshots show the Original view of a PDF before and after ticket tb-valc. In the "after" build, each page shows only its book crop. The epic is boo-fval. The design is `docs/plans/pdf-word-image-reflow.md`, section "The Original view".

## How they were taken

- The device was a new Android 36 emulator, `bookfin-tb-valc`, with a Pixel 8 screen of 1080 by 2400 pixels. It was driven only through the T3 device tools.
- The book was Windfall from `tool/showcase_fixture.dart`, started as `dart run tool/showcase_fixture.dart 8197 --pdf=test/reader/fixtures/reflow/margins-book.pdf`. So its ebook is the 13-page margins book.
- The "before" build was a debug APK of commit `0f4ee11`, the base of this ticket. The "after" build was a debug APK of this ticket's branch, installed over it with the same data and download.
- Each screenshot shows the reader in full screen, after a tap in the middle of the page hid the controls.

## The screenshots

| Page | Before | After | What changes |
| --- | --- | --- | --- |
| 3, a body page on the right | `before-page-3.png` | `after-page-3.png` | The running header "Falling Bodies", the folio "2" and the white margins are gone. The text is larger and fills the screen's width. |
| 5, a body page on the right | `before-page-5.png` | `after-page-5.png` | The same crop as page 3, so the text has the same size and place. |
| 10, a page with a wide table | `before-page-10.png` | `after-page-10.png` | The header "A Short Book of Motion" and the folio "9" are gone. The crop grows to hold the whole table. |
| 3, after the app restarts | | `reopen-page-3.png` | A reopened book shows its page cropped, because the kept survey gives the crop within 300 ms. The reader's controls are visible here. |

## What was seen

- The first open in the "after" build resumed at page 10 and showed it uncropped. The crop of page 10 was not known within 300 ms, so the page showed whole, as the design says. The next page, 11, showed cropped. A turn back to page 10 then showed it cropped. Ticket ta-go9x measures the time that a kept survey takes to read at an open.
- The table on page 10 touches the screen's left and right edges. A crop that grows for content outside its side's box gets no white edge around that content. Ticket ta-3g8x asks whether it needs one.
