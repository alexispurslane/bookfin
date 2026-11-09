# Whole-book page numbers and a page-exact scrub bar (boo-jglf, boo-ok9i)

Date: 2026-11-09. The images come from a disposable emulator (AVD `bookfin-jglf`, Android 36, Pixel 7 profile, deleted after the check), with a debug build of the branch. The app signed in to the synthetic server `tool/showcase_fixture.dart` through `adb reverse`. The server ran with `--long-ebook=.cache/epub-trial/books/se-frankenstein.epub`, so the ebook of "Salt and Lantern" is the public-domain Standard Ebooks Frankenstein. It has 468 pages at the reader's default text size on this screen. A debug build reads and writes no kept page maps, so each open lays out the whole book.

| Image | What it shows |
| --- | --- |
| `01-chapter-numbers-before-layout.png` | The book opens at the saved place in Chapter IX. Before every section is laid out, the label counts the chapter's pages: "Chapter IX · Page 5 of 13". |
| `02-whole-book-numbers.png` | About three seconds later, every section is laid out. The same page now shows "Chapter IX · Page 187 of 468". |
| `03-scrub-to-far-page.png` | A drag toward the end of the book. The label names the page under the finger, "Chapter XXII · Page 386 of 468". The front card is still blank, because the finger moves on. |
| `04-landed-on-far-page.png` | The drag ended near the end, and the reader shows "Walton, in Continuation · Page 443 of 468". |
| `05-finger-rests-on-page-439.png` | A slow drag rests on "Page 439 of 468". The front card shows that page. |
| `06-release-lands-on-page-439.png` | The release lands on the page that the card showed, "Page 439 of 468". |

The check also found and fixed one problem on the device. Frankenstein's title page hides its title and author before its image, so its saved place has text progress 1. The bar's thumb then sat at the start of the next section and announced "Imprint". The book map now reads a place as one character, at most the section's last one, so the thumb announces "Titlepage".
