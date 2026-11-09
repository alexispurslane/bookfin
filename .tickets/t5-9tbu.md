---
id: t5-9tbu
status: open
deps: []
links: []
created: 2026-11-09T18:18:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Report the app's install and the system's build to Dart for cache keys

Found in boo-ystu (docs/research/epub-layout-cache.md). A disk cache of layout results must be dropped when the app's code, its bundled fonts or Flutter's text engine change, and when the system's fallback fonts change. The app's version (0.1.0+1 in pubspec.yaml) is the same in every build, so it cannot stand for the code. Add a method to the existing bookfin/device channel that returns the app package's install time (Android PackageInfo.lastUpdateTime) and the system's build (Android Build.FINGERPRINT), and the same facts on macOS (the modification time of the app bundle's executable, and the system version). Give Dart one function that returns them as one text-engine fingerprint, together with the platform's locale list. A debug build returns no fingerprint, because hot reload changes code with no install, so a debug build reads no layout cache.

## Acceptance Criteria

On the Android emulator, the fingerprint changes after an APK install and stays the same across launches of one install. On macOS it changes after a rebuild. A debug build gives no fingerprint. A runner without the channel gives no fingerprint, and nothing fails.

