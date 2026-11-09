---
id: t5-4lbx
status: open
deps: [t7-rcyp]
links: []
created: 2026-11-09T18:18:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep a book's page map on disk

Found in boo-ystu (docs/research/epub-layout-cache.md). A page map is the true page starts of each section of one book for one value of the layout settings. Build the store that keeps it, without changing the page source. Key: format version, book identity, page width, height and text size as exact 64-bit floats (not the theme: the night colors cut the same starts in all 4,573 corpus sections), and the text-engine fingerprint of the ticket before. File: .bookfin-layout beside the download's file, one file per key, named by a hash of the key, with the whole key in its header. DerivedBookFiles counts and removes the directory with the download. Format: magic number, version, key, then each section's complete flag, start count and starts as unsigned variable-length integers (item step, line or line step, part), then a CRC-32. Writes go to a temporary file and then a rename. The UI isolate encodes and decodes (0.2 ms for the largest corpus book on the host), with a comment that says why. At most four settings values per book, the most recently used; files of another fingerprint go at the first open after an update. A file whose header names another key is ignored. A broken file (bad CRC, short, or a decode error) is renamed to .bad, one per book, and the caller gets no map. Reading never waits for it.

## Acceptance Criteria

Tests show that a written page map reads back equal, that a kill between the temporary write and the rename leaves the old map, that a broken file is set aside and gives no map, that another key's file gives no map, that a fifth settings value evicts the least recently used one, and that removing the download removes the maps.

