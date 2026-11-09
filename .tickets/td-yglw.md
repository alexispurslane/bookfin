---
id: td-yglw
status: open
deps: []
links: []
created: 2026-11-09T06:37:08Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Drop nodejs_22 from the default dev shell

tc-rap6 deleted packages/flutter_epub_viewer, whose epub.js engine build, engine tests and Chromium comparison were the only users of Node.js in the default dev shell. flake.nix line 102 still lists pkgs.nodejs_22. tc-rap6 did not edit flake.nix, because its brief kept flake.nix out of scope. Other uses: tool/research/readers has its own flake with its own Node.js. The .mjs scripts under tool/evidence/reader/ are historical evidence that nothing runs.

## Acceptance Criteria

flake.nix no longer lists nodejs_22 in devShells default. nix develop still opens, and tool/bookfin test and build-android still pass. The flake lock does not change.

