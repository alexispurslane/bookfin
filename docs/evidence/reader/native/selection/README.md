# Text selection and copy on a native page (tc-iwqp)

Date: 2026-11-08. Device: a disposable emulator, `bookfin-tciwqp` (Android 16, API 36, google_apis arm64), deleted after the check. Server: the synthetic server (`tool/showcase_fixture.dart`) through `adb reverse` of one port. Book: Salt and Lantern, downloaded. Tool: the T3 device-bound `agent-device` 0.21.31 for every launch, long press, pan, tap and screenshot.

| Screenshot | Step | Result |
| --- | --- | --- |
| `01-long-press-word.png` | Long press "twelve". | The word is selected, with two handles and a menu of Copy and Select all. |
| `02-handle-dragged-into-next-paragraph.png` | Drag the end handle into the next paragraph. | The selection runs from "twelve" to "Every evenin", across the paragraph break. The handle stopped one letter short of the aimed point. |
| `03-after-copy.png` | Tap Copy. | The selection ends, as on Android. Android's clipboard preview shows "twelve, and nobody had asked her to." and "Every evenin" on two lines. |
| `04-pasted-into-search.png` | Open the reader's search and paste. | The field holds the 48 characters of the copied text. The field is one line, so Flutter drops the line break, and "to." and "Every" join (ticket tf-1rv4). |
| `05-swipe-with-selection-stays.png` | Long press "twelve", then swipe to the left. | The page does not turn, and "twelve" stays selected. |
| `06-tap-clears-selection.png` | Tap the page away from the selection. | The selection ends, and the reader controls stay shown, so the tap did not toggle them. |
| `07-swipe-without-selection-turns.png` | Swipe to the left. | The page turns to the chapter "Salt". |
| `08-selection-before-chapter-arrow.png` | Long press "spring". | The word is selected. |
| `09-chapter-turn-clears-selection.png` | Tap the previous chapter arrow. | The reader shows "The Harbor Light" with no selection, handles or menu. |

The emulator's shell cannot read the clipboard on Android 16, so the paste into search shows the copied text.

macOS was not checked by hand. This session has no tool to move a real mouse in a macOS window, and `tool/bookfin accept-macos` deletes the app's keychain sign-in. The widget tests in `test/reader/epub/selection_test.dart` drive a mouse drag, Cmd or Ctrl+A and Cmd or Ctrl+C under the macOS, Linux and Windows platforms.
