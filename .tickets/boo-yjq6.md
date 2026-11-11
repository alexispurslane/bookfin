---
id: boo-yjq6
status: in_progress
deps: []
links: []
created: 2026-11-11T20:09:32Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-tam0
---
# Open books faster: quick wins 1 to 10 of faster-book-open.md

Build the ten quick wins in docs/plans/faster-book-open.md: native inflate with a byte limit, slicing-by-8 CRC-32, own PNG and JPEG header reader, identity from policy+revision+digest (decided), const hyphenation tables, prepare at once with the last page settings, return before the record write ends, lazy image reads from the record, PDF progressive loading, no readAsBytes into the UI isolate.


## Notes

**2026-11-11T20:21:39Z**

Quick win 1 (native inflate with a byte limit): host AOT bench, median of 7, inflate of every deflated entry: prose 10.0 -> 2.9 ms, long 17.8 -> 4.9 ms, illustrated 22.7 -> 12.5 ms, divine 13.5 -> 4.0 ms (tool/reader/admission_bytes_bench.dart).

**2026-11-11T20:26:06Z**

Quick win 2 (slicing-by-8 CRC-32): host AOT bench, median of 7, CRC-32 of every expanded entry: prose 5.5 -> 1.3 ms, long 7.9 -> 1.9 ms, illustrated 73.6 -> 17.9 ms, divine 124.9 -> 30.1 ms. Equal to package:archive's getCrc32 on all 8,204 entries (269 MB) of the 90 corpus books.

**2026-11-11T20:34:05Z**

Quick win 3 (own PNG and JPEG header reader, image_size.dart): host AOT bench, median of 7, headers of every image: prose 4.4 -> 0.0 ms (5 images), long 5.7 -> 0.0 ms (7), illustrated 4.9 -> 0.1 ms (89), divine 110.2 -> 0.006 ms (138). Same accept or refuse and same size as package:image on all 986 corpus images; 22 malformed and edge-case tests check both readers.

**2026-11-11T20:44:09Z**

Quick win 4 (identity from the policy, Publication.revision and the file digest; revision 3): host AOT bench, median of 7, the SHA-256 that the identity cost: prose 13.7 -> 0.002 ms, long 18.0 -> 0.002 ms, illustrated 170.3 -> 0.002 ms, divine 286.1 -> 0.002 ms. Tests prove that a place saved under the old identity opens at its place, and that the first open after the change lays out the page map once again and the next open reads it. Fixture tests that matched places on the old identity now match on admittedFilesDigest (test helper, the old formula).

**2026-11-11T20:54:15Z**

Quick win 5 (const hyphenation tables): host AOT bench (tool/reader/hyphenation_bench.dart), median of 7, first hyphenation of an American and a British word in a new worker: 3.4 -> 0.012 ms. 400,000 words: 714 -> 668 ms and 868 -> 855 ms in two runs at host load 29, so no slower lookups. tool/reader/hyphenation_tables.dart generates lib/reader/epub/hyphenation_en_tables.dart (502 KB of source); hyphenate_test checks it against hyphenation_en.dart.

**2026-11-11T21:06:00Z**

Quick win 6 (start the open with this phone's last page settings): LastPageSettings keeps the settings of each shown EPUB page (SharedPreferencesAsync); EpubPager(expected:) prepares the saved place's section, or section 0, at once and uses that work only when the first present is equal. Host bench (admission_benchmark_test), pager construction to shown page with the first present 12 ms later, median of 5: prose 30.0 -> 21.6 ms, long 35.5 -> 23.6, illustrated 28.1 -> 20.0, divine 27.8 -> 19.7, MOBI 26.8 -> 19.4. Recorded t4-4d21 for the three same preference stores.

**2026-11-11T21:17:30Z**

Quick win 7 (the load returns before the record write ends): AdmittedBooks.load runs read/admit and the caller's use in one worker, gives the record as TransferableTypedData, and a worker of its own writes it atomically after; a later load of the same download waits for that write (AdmittedBooks.written). EPUB, MOBI and the outline measure all load this way. Host bench, median of 5: the write that left the path took prose 2.6, long 3.8, illustrated 8.7, divine 26.7, MOBI 2.9 ms; fresh load 82.8 -> 78.8, 119.6 -> 117.5, 100.9 -> 86.7, 261.6 -> 239.2, 330.8 -> 320.2 ms.

**2026-11-11T21:34:09Z**

Quick win 8 (images and fonts read from the record when a page draws them; Publication.revision 4): the record lists the text files first, so a reopen reads the header and the text block, and Publication.bytesOf reads an image or a font from its byte range while the record still begins with its key line. Host bench (admission_benchmark_test), cached open, median of 7, before -> after: prose 1.9 -> 1.9 ms, long 3.1 -> 2.3, illustrated 11.3 -> 2.9, divine 29.1 -> 7.0, MOBI 2.5 -> 1.6. Found and fixed a race from quick win 7: the record write ran outside the download's read, so a removal during it could fail or leave the record behind. The session now gets the book at once but keeps the download lent until the record is written (ReaderSession.derivedWrites), and the outline measure waits for it. Page map writes still run outside a read, as before.

**2026-11-11T21:54:11Z**

Quick win 10 (no PDF bytes in the UI isolate): PdfRuntime.open takes the file's path and opens it with PdfDocument.openFile, so PDFium reads the file itself. Host bench (test/reader/pdf_open_benchmark_test.dart, new), median of 7, open / open with the render of page 100 at 1080 pixels: Raven (24 pages) 33.9 / 43.8 -> 14.3 / 24.3 ms, Origin of Species (568 pages) 495.4 / 614.3 -> 206.0 / 322.8 ms. Host load fell from 16 to 9 between the runs. Done before quick win 9, whose tests open files by path.

**2026-11-11T22:25:09Z**

Quick win 9 (progressive PDF open): openFile(useProgressiveLoading: true) measures only page 1, and the book measures each other page at its first use (_NativePdfBook._page, pdfrx reloadPages), before its text or render. Nothing measures all pages in the background: the book map and the scrub bar count pages and read no sizes. Host bench, median of 7, both at load 5, open / open with the render of page 100 at 1080 pixels: Raven 13.7 / 23.5 -> 1.6 / 14.8 ms, Origin of Species (568 pages) 202.1 / 318.6 -> 1.7 / 117.3 ms. Three tests prove that a page that the open did not measure draws at its own size and gives its own text.
