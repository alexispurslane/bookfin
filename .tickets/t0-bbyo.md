---
id: t0-bbyo
status: closed
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

## Parent correction and verification — 2026-11-13

Reproduced the warning with the complete isolated package analysis (exit 2).
Removed only the second cast after Dart has already established the phrase's
String type. The first cast, phrase matching, assertions and public-corpus gate
remain unchanged. Package analysis now reports no issues. The package suite
passes five tests; its four existing public-corpus tests remain explicitly gated.
Both touched Dart files format without changes.

Exact commands, retained before/after logs and source hashes:
docs/evidence/td-bz4y/integration/integration.json and commands.json. Parent
performed this small correction directly; no additional delegate or review stage.

Integrated in c7ff192c and closed by the parent after the passing checks above.
