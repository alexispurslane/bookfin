---
id: t7-rcyp
status: in_progress
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


## Decisions (user, 2026-11-09)

- Remove the full image decode from admission. Layout needs only the width and height, which the image header gives.
- Do not hash the book at open. Downloads already computes the SHA-256 of each file when its download completes (`record.digest` in lib/downloads/local_downloads.dart). The reader uses that digest as the original digest.
- Keep the admitted book on disk: the unzipped and admitted files and every admitted fact (identity, spine, spine steps, contents, styles, image sizes, warnings). An open reads that record and does not unzip, sanitize or hash again. A changed file or a new policy admits in full.

## Notes (2026-11-09)

- Downloads gives the reader a `VerifiedFile`: the saved file and the SHA-256 digest that Downloads computed when the download completed. `Downloads.readLocalFile` passes it to the reader's loaders. The publication's original digest is that digest.
- Admission reads only each image's header. It also finds the CFI spine steps (`Publication.spineSteps`), so the pager makes no worker call for them.
- `AdmittedBooks.open` (lib/reader/admitted_books.dart) keeps the admitted book in the download's `.bookfin-admitted` folder, keyed by the file's digest, the reading policy and `Publication.revision`. A later open reads it in one worker call. An unreadable record is set aside as `publication.unreadable`, and the book admits in full. `DerivedBookFiles` counts and removes the folder with the download.
- A MOBI keeps the admitted book of its conversion under the MOBI's digest and policy, so a later open neither converts, reads nor hashes it.
- A saved EPUB place no longer needs the processed identity to match (`ReaderDocument.restore`). The original digest, the policy and the engine still must match, and the pager opens the place only where its CFI and quote match the text. This keeps a place that an older admission saved in a book with an image whose header is sound but whose pixels do not decode. None of the 986 images of the 85 corpus EPUBs is such an image.
- Host numbers are in docs/research/epub-first-page-timing.md. The emulator run could not start for lack of disk space (t6-0yez).
