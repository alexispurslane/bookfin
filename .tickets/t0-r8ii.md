---
id: t0-r8ii
status: open
deps: []
links: []
created: 2026-11-10T02:12:54Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Decode a large page map without a long pause on the UI isolate

Found in t5-s1vy. Format 4 of the page map keeps table cell widths, 16 bytes a cell. The largest map of the corpus grew from 176 KB to 536 KB (Standard Ebooks' Dialogues of Plato at 360 x 640 @ 26, 21,820 cells). On the host's debug build, a warm read of a 514 KB map takes 4.4 to 5.8 ms and a write about 7 ms on the UI isolate, file access and CRC-32 included, against 2 ms and 4 ms at 175 KB. Measure it on a device. If it is longer than a frame, move the decode and encode to a worker (the widths are typed data, so their copy is cheap), or decode a section's measures only when the section is prepared.

