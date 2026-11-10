# Real shared History capture

Captured on November 10, 2026 for `boo-qn2i`, using Bookfin revision `bfcbe24b7c6ef6324c6769d02c40cf236ebd5ed0`.
`shared-history.webp` shows the production shared History sheet open over the production player.
It is rendered on a computer through Flutter's host test runner, not captured on Android and not evidence of device performance.

## Demonstration records, real surface

The image uses the controlled “River” book fixture from `test/playback/shared_timeline_test.dart`, with an audiobook and an EPUB.
It contains no private library, personal reading record, server address, or real account identifier.
The background cover is the production player's generated cover, not a replacement marketing illustration.

An ignored scratch harness, `.cache/qn2i_history_capture_test.dart`, binds the real `Playback` and `ReaderSession` owners to a synthetic test account and in-memory stores.
The audio engine and local-file lookup are test doubles; no server or real audio playback is needed to render this surface.
The listening jump is created through `Playback.open`, `Playback.jump(forward: true)`, and `Playback.flush`.
The reading owner loads ordinary serialized reading records through its `ReadingStore`, using the same schema as the existing shared-History tests.
The row data is not painted into a stand-in timeline.

| Visible record | Demonstration data source |
| --- | --- |
| Listening: Jumped ahead 30 s | Real Playback command on the fixture audiobook |
| Reading: Went to a search result | Controlled before/after reading positions, two minutes before capture |
| Reading bookmark: The far shore | Controlled named bookmark, twelve minutes before capture |
| Reading: Changed chapter | Controlled chapter move, twenty-five minutes before capture |

The harness mounts `PlayerView` under `ReaderScope`, taps the player's real History button, and expands the reading search move in the real `HistoryTimeline`.
The resulting sheet visibly includes listening and reading icons, Go back, Go to, and Delete controls.
The current time labels belong to these demonstration records, not a person's activity.

The capture uses the real bundled Outfit, Source Serif 4, and Material Icons fonts, the Cream theme, and the normal player and glass-sheet components.
The host viewport is 411 by 840 logical pixels, at two image pixels per logical pixel. The output is 822 by 1680 pixels.
The test harness disables Flutter's debug banner before rendering; it does not retouch the captured image.
The final PNG was encoded to WebP at quality 84, method 6, without cropping, compositing, or altering app contents.
`assets.json` records output dimensions, size, and the raw PNG and final WebP hashes.

The capture asserts that the listening jump, reading Go to control, and Delete control are present, and checks for Flutter exceptions.
It does not activate Go to during capture. Cross-medium routing is established by the inspected production code and existing behavior tests below, not by a fake navigation callback in this harness.

## Verified meaning of shared History

Shared History combines a book's listening and reading actions and bookmarks, newest first.
Each owner also saves its medium's resume position. The timeline itself does not add two live/current resume rows.
The homepage makes no claim that both current locations are shown together.

| Claim | Implementation | Existing behavior evidence |
| --- | --- | --- |
| Both owners keep durable histories | `lib/playback/playback.dart:374`, `lib/playback/playback.dart:1647`, `lib/reader/session.dart:941`, `lib/reader/session.dart:1215`, `lib/reader/session.dart:1487` | `test/playback/history_test.dart:345`, `test/reader/reading_timeline_test.dart:95` |
| One newest-first list for both media | `lib/playback/timeline.dart:32`, `lib/playback/timeline.dart:86` | `test/playback/shared_timeline_test.dart:201` |
| Book and headphone icons identify media | `lib/playback/timeline.dart:320` | `test/playback/shared_timeline_test.dart:219` |
| Open from player, reader, or book details | `lib/playback/screen.dart:213`, `lib/reader/screen.dart:131`, `lib/catalog/book_page.dart:270` | `test/playback/shared_timeline_test.dart:144`, `test/reader/dock_history_test.dart` |
| Go to opens the chosen entry's medium | `lib/playback/timeline.dart:53`, `lib/playback/timeline.dart:113` | `test/playback/shared_timeline_test.dart:247`, `test/playback/shared_timeline_test.dart:305` |
| Go back, restore, Undo, and bookmark controls | `lib/playback/timeline.dart:464`, `lib/reader/session.dart`, `lib/playback/playback.dart` | `test/reader/reading_timeline_test.dart:167`, `test/reader/reading_timeline_test.dart:231`, `test/reader/reading_timeline_test.dart:330` |

The references were inspected at the revision above. Both history tickets `t9-9ffz` and `t9-7fxw` are already closed; no absent history feature was implemented here.
The old HTML illustration and audiobook-only screenshot are no longer used in the homepage History section.

The final Nix command and passing capture-test result are recorded in the [PDF capture notes](../nihil-unbound/README.md#commands-and-result).
The existing shared-timeline, listening-history, and reading-timeline test files were also run through Nix, one file at a time: all 64 tests passed. The local log is `.cache/qn2i-history-claims.log`.
Early scratch harness attempts stalled while waiting for asynchronous work without pumping Flutter's test clock. Only those owned test processes were stopped.
The final harness pumps the clock while native work settles; both final capture tests pass and no capture command remains running.
See `../boo-qn2i-verification.json` for checks and their limits.
