---
id: boo-apx8
status: open
deps: [boo-0i64, boo-77sj]
links: []
created: 2026-11-08T17:39:24Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build the Linux desktop app as a flake package

User request (2026-11-08): packages.x86_64-linux.linux-app, a pure Nix build of the Linux desktop bundle (nixpkgs' flutter buildFlutterApplication or equivalent) with the Nix-pinned PDFium and libmobi. macOS needs Xcode, which a pure Nix build cannot use, so macOS stays tool/bookfin build-macos.

