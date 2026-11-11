---
id: te-24cn
status: open
deps: []
links: []
created: 2026-11-11T23:32:39Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make the extensionless-download format test delete its folder after background writes finish

Found on 2026-11-11 in a full flutter test run under a load of 12 on 10 cores. test/reader/unknown_format_test.dart, 'ordinary Book without Container opens river.epub from an extensionless download', failed in its teardown: FileSystemException: Deletion failed, path = '/tmp/.../bookfin-format-...' (OS Error: Directory not empty, errno = 66). The test passed in 3 runs of the file alone. A likely cause: a write that the reader starts without awaiting it (for example a kept admitted book beside the download) lands in the folder while directory.delete(recursive: true) runs. Find the write, and make the test wait for it, or make its owner expose a way to wait for it.

