---
id: ta-ukpf
status: open
deps: []
links: []
created: 2026-11-09T19:53:33Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Share one atomic write for derived book files, and remove the partial files of killed writes

Found in t5-4lbx. AdmittedBooks._keep (lib/reader/admitted_books.dart) and PageMaps.write (lib/reader/epub/page_maps.dart) both make the derived directory when it is absent, refuse a non-directory in its place, write a partial file with the process id and a time, rename it over the kept file, and delete the partial file on failure. This is the second real use, so factor it into one function beside DerivedBookFiles. t5-4lbx did not change admitted_books.dart because t9-esjw and boo-1u66 change it in parallel. Both stores also leave the partial file of a process that was killed between its write and its rename until the download is removed. The shared write can remove partial files of other process ids that are older than a minute.

## Acceptance Criteria

AdmittedBooks and PageMaps use one write function, and their tests pass unchanged. A test shows that a partial file that a killed process left goes away at a later write, and that a write in progress in this process keeps its partial file.

