---
id: boo-ivvx
status: open
deps: [boo-77sj]
links: []
created: 2026-11-08T17:41:47Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build the macOS app as a flake package

User request (2026-11-08): nix build .#macos-app on aarch64-darwin. Flutter's macOS build runs xcodebuild, which Nix cannot supply, so this package uses the system Xcode (/Applications/Xcode.app; this Mac's Nix has sandbox = false, and a sandboxed Mac needs sandbox = relaxed plus an Xcode exception). Declare that dependency: check the Xcode version and fail clearly if it is missing or different. Take Dart packages, CocoaPods pods and native libraries from the same locked fixed-output inputs as boo-77sj (pods as fixed downloads, not fetched during the build). Sign ad hoc. Not runnable in Tangled CI, which has no macOS runners.

