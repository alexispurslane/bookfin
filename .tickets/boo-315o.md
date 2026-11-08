---
id: boo-315o
status: in_progress
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

