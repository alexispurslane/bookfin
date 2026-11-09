# Every reader sheet is glass (boo-2td2, boo-wokk)

Date: 2026-11-09. Device: a disposable emulator, `bookfin-boo2td2` (Android 16, API 36, google_apis arm64), deleted after the check. Server: the synthetic server, started with `dart run tool/showcase_fixture.dart 8296 --footnotes`, through `adb reverse` of one port. Book: First Frost, EPUB downloaded. Build: a debug APK of this branch. Tool: the T3 device-bound `agent-device` 0.21.31 for every launch, tap and screenshot.

| Screenshot | Step | Result |
| --- | --- | --- |
| `01-note-sheet-cream.png` | In Cream, tap the note reference 2 in chapter one. | A glass sheet shows the note. Its title row holds the heading Note on the left and the quiet action Go to note, with a forward arrow, on the right. The back link of the note is not in the sheet. The page behind it does not move. Retaken for boo-8ucr: the note starts at the heading's left edge with its number before the first word, and the space above and below it is even (see `../footnotes/refined/README.md`). |
| `02-note-sheet-night.png` | Choose Night, then tap the note reference 2 again. | The same glass sheet in the night colors. The note text uses the reader's night ink and stays readable on the glass. Retaken for boo-8ucr. |
| `03-contents-sheet-cream.png` | Tap Contents. | The contents and bookmarks tabs on a glass sheet. |
| `04-search-sheet-cream.png` | Tap Search book and search for "orchard". | A glass sheet with the heading Search and the action Close in its title row, over the field and three hits. |
| `05-settings-sheet-cream.png` | Tap Reading settings. | A glass sheet with the heading Reading settings in its title row, over the text size and theme controls. |
| `06-go-to-note-night.png` | Tap Go to note in the night note sheet. | The sheet closes, and the reader shows the Notes section. The label reads "Notes · Page 1 of 1". |
| `07-back-link-text-glyph-night.png` | Look at the notes on the Notes page. | Each back link draws the leftwards arrow with hook (U+21A9) as an underlined text glyph in the page's ink, not as a color emoji. |

Android's accessibility tree, which the `agent-device` snapshot reads, held the heading "Note", the button "Go to note", and the note text "Russets are apples with rough, brownish skin. The old trees on the south wall were Egremont Russets, planted in the spring of 1961." without the back link. A real TalkBack check needs t2-u76g.
