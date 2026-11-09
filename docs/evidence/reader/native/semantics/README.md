# Semantics of a native page on Android (tc-fz4n)

Date: 2026-11-08. Device: a disposable emulator, `bookfin-tcfz4n` (Android 16, API 36, google_apis arm64), deleted after the check. Server: the synthetic server (`tool/showcase_fixture.dart`) through `adb reverse` of one port. Book: Salt and Lantern, downloaded. Tool: the T3 device-bound `agent-device` 0.21.31. Its `snapshot` reads the Android accessibility tree, the same nodes that TalkBack reads.

| Step | Screenshot | Page nodes that the accessibility tree held, in order |
| --- | --- | --- |
| Open the book | `01-page1.png` | "The Harbor Light", then the three paragraphs of the page, each whole: "The lamp at the end of the harbor wall burned whale oil until the winter of the long ice, …", "Ada Quill kept it lit. She was twelve, and nobody had asked her to.", "Every evening she carried the can along the wall …" |
| Swipe to the next page | `02-turned.png` | "Salt", then "In the spring the salt traders came back from the south …" and "They wanted to meet the keeper. …" |
| System text size at its largest step (font scale 3.2), app relaunched, book opened | `03-large-text.png` | "Salt", then "In the spring the salt": only the two lines of the paragraph that the page shows |
| Swipe to the next page | `04-large-text-turned.png` | "traders came back from the south with their carts, and the town": the paragraph goes on with the lines of this page |

The snapshot does not show node flags or actions. The widget tests in `test/reader/epub/semantics_test.dart` prove the header flag, the link nodes and their tap, the image labels and the scroll actions.

TalkBack itself was not used. The agent-device snapshot helper suppresses other accessibility services, so TalkBack cannot bind while the T3 device tools drive the emulator (t2-u76g, same agent-device version). Real TalkBack speech, focus and its scroll gestures wait for t2-u76g.
