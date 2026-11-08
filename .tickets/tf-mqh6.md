---
id: tf-mqh6
status: open
deps: [tf-gnuk, tc-1yif]
links: []
created: 2026-11-08T16:27:49Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, macos, reader]
---
# Bundle the libmobi converter in the macOS app

lib/reader/mobi.dart opens libbookfin_mobi.so on Android and otherwise the BOOKFIN_MOBI_LIBRARY path or a bare libbookfin_mobi.dylib. The macOS app does not build or bundle native/mobi, so a MOBI or AZW3 book fails to import there. Fix: an Xcode build phase that runs native/mobi/CMakeLists.txt (as Gradle does on Android, and as the Linux and Windows runners can do in CMake), copies libbookfin_mobi.dylib and libmobi into Contents/Frameworks and signs them, and a macOS path in mobi.dart. MOBI shows through the EPUB viewport, so this follows the Apple EPUB ticket. Found in boo-gnx9.

## Acceptance Criteria

The macOS app imports and opens a MOBI book from the fixture.


## Notes

**2026-11-08T19:23:53Z**

Still needed. MOBI still converts with libmobi, but it no longer shows through a WebView: tc-1yif (epic boo-b2ey) makes the native reader the MOBI reader on macOS. This ticket now depends on tc-1yif. Its old blocker tf-gnuk is obsolete.
