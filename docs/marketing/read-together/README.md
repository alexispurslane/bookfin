# Reading and listening together: capture notes

These six images show cross-edition Go to (epic `boo-z3is`) on the homepage.
They were captured on November 11, 2026, from Bookfin revision `fb1ec8f0`.

## What they are

The images are host widget captures of the real `ReaderScreen` and History sheet.
Flutter's test runner on a Mac drew them at 1080 by 2400 pixels.
They are not Android screenshots, and they are not HTML reconstructions.
The homepage copies are scaled to 822 pixels wide and saved as WebP.

The book behind the sheet is the Standard Ebooks EPUB of *The Time Machine*, a public-domain text.
The capture harness gives it an audiobook edition with chapters "Chapter 1" to "Chapter 12" and "Epilogue".
The history entries are demonstration records made by the harness.
No personal library, server address, or account data is involved.

## The images

| File | What it shows |
| --- | --- |
| `landing-cream.webp`, `landing-night.webp` | History over the reader. A listening move is open, and its tiles name pages of the ebook, marked "about". |
| `after-go-to-cream.webp`, `after-go-to-night.webp` | The reader after Go to on the After tile, with the Undo note. |
| `mapped-move-cream.webp`, `mapped-move-night.webp` | History after the jump. The new reading entry, "From audiobook", sits on the reading track. |

The capture harness is kept outside the repository, in `~/.cache/bookfin/previews/boo-z3is/capture_test.dart`.
