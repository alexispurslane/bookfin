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
