---
id: boo-tshd
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Use one place map for chapter anchors and heard anchors

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/speech/place.dart:215-277 and lib/crossings/alignment.dart:193-331 define two `Anchor` types and two piecewise-linear interpolations between recording time and visible ebook characters, with different validity rules. The order "speech anchors, then chapter anchors, then whole-book share" is written in four places (lib/crossings/speech_places.dart:82-113 and 181, lib/crossings/crossings.dart:212-257). Build one place map with points of two kinds, one interpolation, one validity rule for each span, and one query in each direction that returns the value and its source.

