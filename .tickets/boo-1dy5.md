---
id: boo-1dy5
status: open
deps: [boo-0i64]
links: []
created: 2026-11-08T17:39:24Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Give each build host one default dev shell for Android and its desktop app

User question (2026-11-08): 'the platform specific dev shell is automatically picked by nix develop right?' Today nix develop picks devShells.<system>.default, which is the Android shell on both hosts; the desktop shells are separate (.#macos on aarch64-darwin, and .#linux from boo-0i64). Make the default shell of each host build both Android and that host's desktop app, if the toolchains can live together (the macOS shell uses the system Xcode and unsets SDKROOT and DEVELOPER_DIR, while the Android shell wraps xcrun and sigtool). If they cannot, keep separate shells and explain why in docs/setup.md.

