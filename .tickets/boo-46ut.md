---
id: boo-46ut
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
# Persist the speech anchor map and never block a Go to on its growth

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, size estimated. lib/crossings/speech_places.dart:51, 74-79, 107 and 151-192. The anchor maps live in memory only, so after each launch every heard window is searched again, and a window with no match runs a whole-book search. A Go to on a place that no kept window covers awaits that growth, and all work shares one first-in first-out worker (lib/speech/worker.dart:212-227). With 400 kept windows the first Go to of a launch can wait for seconds. Keep the anchor map as derived data beside the heard windows, grow it by one window as each arrives, and let a request read the anchors that exist now. Related: t2-b0sx, t2-5yh3.

