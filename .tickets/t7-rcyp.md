---
id: t7-rcyp
status: open
deps: []
links: []
created: 2026-11-09T16:08:24Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Open a downloaded book without decoding every image and hashing the book again

Found in boo-rw7u (docs/research/epub-first-page-timing.md). On an arm64 Android 36 emulator with a profile build, admission is the largest part of the time from opening a book to its first drawn page: 190 ms of 274 ms for Gutenberg's Frankenstein, 541 ms of 688 ms for Standard Ebooks' Hamlet, 591 ms of 1,008 ms for Standard Ebooks' Poetry of John Keats, 949 ms of 1,022 ms for Gutenberg's Jane Eyre, and 442 ms of 517 ms for a cached MOBI (median of 25 warm opens each). Publication.admit runs at every open of the book. It unzips the book, hashes the archive and each resource with SHA-256, parses and sanitizes each XML document, and decodes every PNG and JPEG in full with package:image to make sure that it is valid (_raster in publication.dart). On the host, the full image decodes alone are 43 to 63 percent of admission: 60 of 138 ms for Frankenstein (1 image, 1.9 megapixels), 169 of 285 ms for Hamlet (5 images, 5.4 megapixels), 441 of 703 ms for Jane Eyre (29 images, 15.2 megapixels). A cached MOBI admits its converted EPUB again at each open. After admission, the pager makes one more worker call that parses the package document again for the CFI spine steps (_spineSteps in pager.dart), before it prepares the first section. Find a design that does the checks once per downloaded file, for example a record of the admitted facts that the download keeps, keyed by the original digest and the policy, and keep the data-safety rules of AGENTS.md.

## Acceptance Criteria

The open benchmark (tool/reader/open_benchmark.dart) on the emulator and on the Pixel 8 shows the admission time before and after for the five books of boo-rw7u, and a book that changed or a new policy still admits in full.

