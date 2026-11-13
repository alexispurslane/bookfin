---
id: t0-bbyo
status: open
deps: []
links: []
created: 2026-11-13T22:29:03Z
type: chore
priority: 4
assignee: Alexis Purslane
parent: boo-b2ey
---
# Remove the existing unnecessary cast in the isolated EPUB corpus test

Found while validating td-bz4y at base 215273e35f986cd6682b47b1efc8eff627ddee34. In tool/research/readers/dart_compat, dart analyze reports unnecessary_cast at test/corpus_test.dart:45:18 and exits 2. The file is unchanged by td-bz4y. Keep public-corpus behavior and its opt-in gate unchanged; remove the obsolete cast and rerun isolated package analysis through Nix.

## Acceptance Criteria

The isolated dart_compat package analysis passes without unnecessary_cast; corpus test behavior and opt-in gate remain unchanged.
