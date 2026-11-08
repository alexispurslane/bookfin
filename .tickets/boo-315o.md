---
id: boo-315o
status: closed
deps: []
links: []
created: 2026-11-08T12:48:01Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make the reader progress bar a whole-book scrub bar with chapter and bookmark marks

User request (2026-11-08): show bookmarks and chapters in the ebook reader's progress bar. Today it is a LinearProgressIndicator (lib/reader/screen.dart:354-358) that cannot be dragged. For EPUB and MOBI it measures only the current spine section (epub.js displayed.page/total), and book.locations is never generated. For PDF it measures the whole document. Build: one draggable bar for all reader formats that measures the whole book, marks chapter starts and reading bookmarks, previews the target place label while dragging, and moves on release. Reuse the audio player's PositionSlider and its _PositionMarks painter (lib/playback/screen.dart:1009, 1137-1182) by generalizing them to book fractions, so that one component serves both (AGENTS.md UI rule 2). For EPUB, pick a whole-book position that is cheap at open time, for example section sizes as weights, and cache anything expensive per book. This is the base for the page-card scrubbing view.


## Notes

**2026-11-08T13:42:46Z**

EPUB whole-book position: spine sections weighted by their byte size, plus the text progress through the section (visible characters, white space left out), measured by reader.js and saved with each place. epub.js locations were measured on War and Peace (367 sections) in desktop headless Chromium: 38.4 s with its default 100 ms pause per section, 4.9 s of real work with no pause, and a 1.3 MB cache per book. Section sizes cost a sum over the spine at open. Places saved before this change have no progress and sit at the start of their section.

**2026-11-08T14:19:05Z**

2026-11-08: the user chose that a PDF place sits at the end of its shown page, so the last page fills the bar (lib/reader/book_map.dart).
