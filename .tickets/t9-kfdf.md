---
id: t9-kfdf
status: open
deps: [t9-sspn, t9-6u46, t9-xj41]
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules]
---
# The book page owns its actions, and each part follows only its own state

Rules: UI rule 1 (only controllers cause side effects). UI rule 3 (subscribe at the lowest level). Engine rule 1 (no whole-library grouping on the UI isolate).

Breaks:
- lib/catalog/book_page.dart, BookPage.build: listens to the whole catalog, so a busy change rebuilds the page and reruns the lookups below.
- lib/catalog/book_page.dart, BookPage.build: finds the series with shelf() over the whole library, and counts possibleMatches over the whole library, on each catalog notice, on the UI isolate.
- lib/catalog/book_page.dart, BookPage.build: a ListenableBuilder on services.activity rebuilds all content below the top bar on each playback tick and each download byte notice.
- lib/catalog/book_page.dart, _Actions: calls playback.open, opens the player, calls reader.open and pushes ReaderScreen.
- lib/catalog/book_page.dart, _EditionPanel: calls playback.open and reader.open, pushes ReaderScreen, opens the file-order sheet and calls catalog.orderFiles, and confirms and calls catalog.separateEdition.
- lib/catalog/book_page.dart, the status lines: read catalog.message and playback.message without subscribing.

Target design:
- BookPage is the controller. It owns listen, read, open player, push reader, separate source, correct file order, correct details, link and combine.
- _Actions reports onListen(edition), onRead(edition) and onDownload. _EditionPanel reports onListen, onRead, onOrderFiles, onSeparate(file) and onDownload.
- BookPage subscribes to the catalog's library listenable. It finds its book, its series and its match count through the catalog's indexes.
- The header subscribes to the book's download state. The progress row subscribes to LibraryServices.bookActivity(book). The edition panels use DownloadControls, which subscribe to their own edition. The status lines subscribe to the catalog's status and to Playback's message.
- Remove LibraryServices.activity when nothing uses it.

Owned files: lib/catalog/book_page.dart, lib/catalog/library_services.dart, and their tests.

## Acceptance Criteria

- A playing tick rebuilds only the progress row and the progress line (rebuild counters).
- A byte notice rebuilds only the download controls of that edition and the round download button.
- A catalog busy change rebuilds nothing on the page.
- Listen reports onListen(edition). The page opens the edition, then the player (Playback fake).
- Separate source reports onSeparate(file). The page confirms, then calls separateEdition.
- The page finds its series and matches through the catalog's indexes and groups no library.


## Notes

**2026-11-07T22:25:14Z**

boo-y6fb merged: Playback has positionNotifier (AudioPosition?, fires on every decoder report), selectionNotifier ((book, edition, playing, active)), sleepNotifier (Duration? left, once a second), recordsNotifier (history, bookmarks or resumes replaced), settingsNotifier ((speed, backward, forward)) and statusNotifier ((message, saveFailed)). Undo, the replacement offer and unsavedChanges have no narrow signal; those widgets stay on the broad notification, which stops firing on ticks after t9-cx1u.
