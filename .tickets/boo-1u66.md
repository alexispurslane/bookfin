---
id: boo-1u66
status: open
deps: []
links: []
created: 2026-11-09T19:31:05Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep a book's main text size so the first page never waits to measure it

Found in the boo-0ari merge. With the text size override on, the first page of a book waits for measureMainTextSize, which styles the three longest sections in a worker: 8 ms median and up to 522 ms (Roget's Thesaurus) on the host, and probably 1.5 to 2.5 times that on a phone. That is on the path to the first page, which t7-rcyp just made fast. Keep the measured main text size with the kept admitted book (lib/reader/admitted_books.dart) or with the page map (t5-4lbx), keyed by everything that it depends on (media queries make it depend on the page width and height), so that only the first open of a book at a page size measures it. Decide whether media queries must count at all for this measurement.

