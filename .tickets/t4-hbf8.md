---
id: t4-hbf8
status: open
deps: []
links: []
created: 2026-11-11T15:54:58Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the root flutter analyze free of errors from the research benches

Found during boo-hyl4 on 2026-11-11. On main at 0a217456, the root 'flutter analyze' (the command in the ticket briefs) reports 72 issues in tool/research/record_hop_bench, tool/research/record_rows_bench and tool/research/tts_bench, for example undefined names (restoreText, RecordJournal, Plan) in record_hop_bench/bench.dart. analysis_options.yaml excludes only tool/research/readers/**. td-tswb covers tool/acceptance and t5-0p5a covers tool/reader. Either exclude the standalone research packages, as for tool/research/readers, or fix them, so that 'dart format --set-exit-if-changed lib test && flutter analyze && flutter test' can pass.

## Acceptance Criteria

The root flutter analyze reports no issue under tool/research.

