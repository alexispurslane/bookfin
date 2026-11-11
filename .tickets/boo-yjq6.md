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
