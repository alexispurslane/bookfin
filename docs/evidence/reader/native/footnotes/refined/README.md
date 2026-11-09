# The note sheet's spacing and alignment (boo-8ucr)

Date: 2026-11-09. Device: a disposable emulator, `bookfin-8ucr` (Android 16, API 36, google_apis arm64, 1080 x 2400 at 420 dpi), deleted after the check. Server: the synthetic server, started with `dart run tool/showcase_fixture.dart 8317 --footnotes`, through `adb reverse` of one port. Book: First Frost, EPUB downloaded. Tool: the T3 device-bound `agent-device` for every launch, tap and screenshot.

The before screenshots come from a debug build of `6cb73f8` (main before this ticket). The after screenshots come from this branch, through hot reload.

## Note shapes

With `--footnotes`, the first chapter of First Frost has five notes. Four are endnotes in a numbered list in the Notes section. One is a footnote without a number.

| Reference | Shape |
| --- | --- |
| 1 | A note of one sentence. |
| 2 | A note of a few lines. |
| 3 | A note of three paragraphs. |
| 4 | A note long enough to scroll. |
| * | A footnote without a number, an `aside` at the end of the chapter. |

## Causes

- The note's excerpt kept the boxes around the note, as on the page. Above the first line, it kept the body's 20 px top padding and the list's top margin. Below the last line, layout drops trailing margins. So the space above was tall and the space below was short.
- The excerpt also kept the page's side padding, the list's 40 px padding and the paragraph's 1.2em first-line indent. So the number "2." hung in the list's padding, a wide gap followed, and then an indent before the first word.
- The sheet then added its own space below the note, and no side inset that matched the title row.

## Screenshots

| Screenshot | Step | Result |
| --- | --- | --- |
| `01-before-one-line-cream.png` | Tap the reference 1. | Before: the number hangs right of the heading's edge, then a gap and an indent. Tall space above, short space below. |
| `02-after-one-line-cream.png` | Tap the reference 1. | After: "1." starts the first line, at the heading's left edge. The text wraps under it. |
| `03-before-numbered-cream.png` | Tap the reference 2. | Before. |
| `04-after-numbered-cream.png` | Tap the reference 2. | After. |
| `05-before-paragraphs-cream.png` | Tap the reference 3. | Before: the first paragraph is indented under a hanging number. |
| `06-after-paragraphs-cream.png` | Tap the reference 3. | After: the first paragraph starts flush with the number. The later paragraphs keep the book's indent and the space between paragraphs. |
| `07-before-long-cream.png` | Tap the reference 4. | Before: a line sits on the sheet's bottom edge. |
| `08-after-long-cream.png` | Tap the reference 4. | After: the text fades out in the space above the sheet's bottom edge, which shows that more follows. |
| `09-after-long-scrolled-to-end-cream.png` | Scroll the note to its end. | The last line sits in clear space above the edge. The line that scrolled under the title row fades out. |
| `10-before-no-number-cream.png` | Tap the reference *. | Before: the first line is indented. |
| `11-after-no-number-cream.png` | Tap the reference *. | After: the text starts at the heading's left edge. |
| `12-after-numbered-night.png` | Choose Night, tap the reference 2. | The same spacing in the night colors. |
| `13-after-paragraphs-night.png` | In Night, tap the reference 3. | The same. |
| `14-after-no-number-night.png` | In Night, tap the reference *. | The same. |
| `15-after-largest-text-night.png` | Set the system text size to its largest, tap the reference 1. | The heading Note stays whole, and Go to note moves under it, at the end. The note starts at the heading's left edge. |

`13` and `14` were taken before two later changes: the fades of a scrolling note and the title row's layout at large text sizes. Neither change shows in a note that does not scroll, at the default text size.

Before the title row change, the heading broke into "No" and "te" at the largest text size. Go to note took the rest of the row. Every glass sheet with a title action had this problem. That intermediate screenshot is not kept.

## Measured spacing

The gaps below are measured in the screenshots of note 2 in Cream, in dp (2.625 px per dp). The space above runs from the baseline of the heading Note, which has no descenders, to the top of the first line's letters. The space below runs from the bottom of the last line's letters to the sheet's bottom edge.

| Build | Space above | Space below |
| --- | --- | --- |
| Before | 50.7 | 18.7 |
| After | 32.8 | 30.5 |

## Page layout

The page's own layout did not change. `BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/fidelity_test.dart` wrote a `fidelity-native.json` that is byte for byte the same as on `6cb73f8`. The corpus check for `se-frankenstein` and `se-alices-adventures-in-wonderland` gave the same results as on `6cb73f8`, apart from the timings.
