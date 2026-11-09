# Note references open a sheet (tc-406m)

Date: 2026-11-09. Device: a disposable emulator, `bookfin-tc406m` (Android 16, API 36, google_apis arm64), deleted after the check. Server: the synthetic server, started with `dart run tool/showcase_fixture.dart 8196 --footnotes`, through `adb reverse` of one port. With `--footnotes`, First Frost has three endnotes in a last section, Notes, marked as Standard Ebooks marks them. Book: First Frost, EPUB downloaded. Tool: the T3 device-bound `agent-device` 0.21.31 for every launch, tap and screenshot.

| Screenshot | Step | Result |
| --- | --- | --- |
| `01-page-with-note-references.png` | Open First Frost. | Chapter one shows the note references 1 and 2 as superscripts. The label reads "One. The Grafted Trees · Page 1 of 2". |
| `02-note-sheet-cream.png` | Tap the note reference 2. | The sheet shows the heading Note, the text of note 2 with its list number, and Go to note. The page behind it does not move. Retaken for boo-2td2: the sheet is now glass, with Go to note in its title row. |
| `03-sheet-closed-page-unchanged.png` | Close the sheet with Back. | The same page shows, and the label still reads "Page 1 of 2", so the saved place did not move. |
| `04-note-sheet-night.png` | Choose Night, then tap the note reference 2 again. | The sheet and the note text use the night colors. Retaken for boo-2td2, as glass. |
| `05-go-to-note-night.png` | Tap Go to note. | The sheet closes, and the reader shows note 2 in the Notes section. The label reads "Notes · Page 1 of 1", and the scrub bar moves. |
| `06-back-link-still-jumps-night.png` | Tap the back link ↩ after note 2. | The back link is not a note reference, so it jumps back to chapter one, page 1 of 2. |

Android's accessibility tree, which the `agent-device` snapshot reads, held the note text "Russets are apples with rough, brownish skin. The old trees on the south wall were Egremont Russets, planted in the spring of 1961." and the button "Go to note". A real TalkBack check needs t2-u76g.

The back link draws as a color emoji in `05-go-to-note-night.png` and `06-back-link-still-jumps-night.png`, because the renderer drew U+21A9 with the system's emoji font. boo-wokk fixed this: the page draws such arrows with a bundled arrow font, and the sheet leaves the back link out. See `../glass-sheets/README.md`.
