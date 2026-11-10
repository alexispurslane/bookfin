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

## Recovery on November 10, 2026

Commit `b4ec646ad8c1d560f8341f46e98e6eb2c4ed9b50` was cherry-picked onto
`9bf71644c0639f5fc201b756fb938eb1137b75be` without conflicts. The screenshots
above are prior emulator evidence, copied unchanged. No emulator build or phone
interaction was repeated during recovery. The newer word renderer and the
decision to keep scanned pictures' paper tone are unchanged.

The recovered implementation and its tests were not written again. Recovery
does not establish that those original tests failed before implementation.
One acceptance gap was reproduced before its fix: a backward move from source
page 6 to page 5 surveyed page 6 next, instead of page 4. The new session test
failed with actual order `[1, 5, 6]`, expected `[1, 5, 4]`. `BookSurvey.follow`
now keeps the direction of the last move between source pages. Reporting another
place on the same source page keeps that direction. All eight survey session
tests then passed, including changing direction back to forward.

The focused run of `pdf_crop_test.dart`, `book_survey_test.dart`,
`survey_session_test.dart`, `pdf_viewport_test.dart`, `book_crop_test.dart` and
`word_pages_test.dart` passed all 79 tests through `nix develop`. The added
300 ms boundary test passed on its first run. It characterizes recovered
behavior; it is not claimed as a pre-implementation failure.

| Acceptance requirement | Verification |
| --- | --- |
| Content only, matching body size and place, whole wide table | Pixel and screen-coordinate assertions in `pdf_crop_test.dart`; original emulator screenshots above |
| Crop fixed while shown | Late-crop and subsequent-turn tests in `pdf_crop_test.dart` |
| At most 300 ms waiting for an initial crop | A controlled test clock proves no render at 299 ms and a render at 300 ms while the survey read is still pending |
| Crop arriving during the initial wait | The 100 ms arrival test proves the first rendered image is cropped |
| Next page prepared in the reading direction | Survey crop-readiness test and session tests for forward, backward, same-page reports and direction reversal |
| Cropped deck cards with no waiting | Known and unknown crop preview test in `pdf_crop_test.dart` |
| Pinch zoom and pan | Two-pointer gestures reach 6 times zoom; dragging pans without turning in `pdf_crop_test.dart` |
| No crop processing on the UI isolate | Analysis uses the book's worker call; image decoding reads the crop through its row stride, without a Dart pixel loop |

The word-view integration in tb-22fu must preserve `_draw`'s per-page crop
capture, `_turned`'s immediate crop choice on a turn, and `preview`'s nonwaiting
crop choice. Both Original images and deck cards use `_drawPage` and `_crops`.
The Trim margins switch in tb-nkz5 should turn cropping off through `_crops` and
explicitly redraw the shown page when the switch changes.

## Recovery checks

All commands below ran through `nix develop` on November 10, 2026.

| Command | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool integration_test` | Passed: 390 files, zero changes |
| `flutter analyze lib test integration_test` | Passed: no issues |
| `flutter test --reporter expanded` | Passed: 2,514 tests, 21 skipped, 2 minutes 53 seconds |
| Focused six-file reader test run above | Passed: 79 tests |

The commands reported missing `iphoneos` and `iphonesimulator` SDKs while
probing the host. These warnings did not fail the checks. The known intermittent
survey reopen test in boo-7plj passed in this full run. No native files changed,
so the native OCR worker script was not required. Coverage, mutation testing,
merged word-view checks and physical-phone acceptance remain with the parent.
