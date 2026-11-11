---
id: t9-dez7
status: in_progress
deps: []
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Measure the text outline of an EPUB or MOBI edition in a worker isolate, cached by revision

Step 3 of design A in docs/plans/cross-edition-places.md. measureTextOutline gives the contents entries of an ebook edition (title, depth, start in visible characters from the book's start) and the visible characters of each part, counted as BookMap counts them. It parses every section once in one Isolate.run. A text place converts to and from visible characters. Measure the time for a large EPUB.


## Notes

**2026-11-11T15:58:17Z**

measureTextOutline(Publication) in lib/reader/text_outline.dart lists the contents that the reader lists (listedContents, moved from the session to lib/reader/contents.dart) at their starts in visible characters, counted by countSection, which BookMap now shares (book_map.dart also exposes contentsTargets). TextOutline converts a reading place to characters (charactersOf) and back to a part and share (placeAt), and has a JSON form for the cache of t9-k6kd. measureDownloadedOutline (platform_io.dart) measures a downloaded EPUB or MOBI in one Isolate.run that reads the kept admitted book (MOBI through the new readMobi) and returns only the outline; a PDF gives null until t9-nl30. Time on this Mac, flutter test JIT, load 9 to 17 on 10 cores: se-bleak-house (1.58 M characters) 578 ms with admission, 131 ms from the kept admitted book, 108 ms for the measurement alone; se-moby-dick 263 ms and 78 ms; pg-2701-moby-dick 259 ms and 100 ms. Check: 2660 passed, 21 skipped.
