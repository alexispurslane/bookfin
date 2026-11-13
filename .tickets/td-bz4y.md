---
id: td-bz4y
status: in_progress
deps: []
links: [te-c2tc]
created: 2026-11-13T21:58:52Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Stabilize archive times in isolated EPUB research fixtures

Discovered by the te-c2tc repository-wide archive audit. The settled seven-builder cleanup covers root Flutter fixtures and tool/showcase_media.dart. Standalone research still has clock-dependent replacements in tool/research/readers/dart_compat/test/compat_test.dart (EPUB cover bytes test), Python synthetic EPUB creation in tool/research/epub_engines/test_prepare.py and test_calibrate.py, and tool/research/sync/fixture.py. Their current callers inspect payloads or server metadata, not rebuilt publication identities; no failing reader restore is claimed. Review and fix stable creation times in their own fixture owners without regenerating checked-in assets or running live server actions.

## Acceptance Criteria

Inventory each research creator; preserve payloads/order and fixture interfaces; prove controlled byte stability and changed-content sensitivity for genuine EPUB builders; run the corresponding isolated research checks. Do not change the SVG-only resource-serving security probes merely because they use ZIP.

## Parent scope and launch — 2026-11-13

Continue the settled fixture-owner correction from te-c2tc in the four isolated
research owners named above. No production feature, generated corpus rewrite,
live-server action or device/browser action is authorized by this ticket.
Inspect every caller and preserve fixture content/order and source-change
sensitivity. Use controlled time changes, never sleeps or timing tolerances.
Run the corresponding focused and complete isolated package suites through Nix;
record pre-existing unavailable corpus/model/server checks as exclusions. Parent
owns integration and closure. Lead: codex/gpt-6-astra xhigh; exactly one fresh
read-only reviewer: codex/gpt-6-astra high. No second review stage.

## Launch accepted — 2026-11-13

Base: `215273e35f986cd6682b47b1efc8eff627ddee34`.
Client request ID: `bookfin-td-bz4y-astra-20261113-1`.
Task ID: `node:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-td-bz4y-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-td-bz4y-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A42e1fbbe-e54d-4e0d-8253-f080c4fbe734%3Adelegate-task%3Abookfin-td-bz4y-astra-20261113-1>

Running; branch and stage not yet reported. T3 owns the worktree. No result is
claimed from launch.

## Implementation and verification — 2026-11-13

Bound checkout: /Users/alexispurslane/.t3/worktrees/bookfin/t3-0cfba5ea,
branch t3/stabilize-epub-archive-times. Initial HEAD and review base:
215273e35f986cd6682b47b1efc8eff627ddee34; initial checkout clean. No checkout
creation, switch or reset. Ticket remains in progress for parent integration.

The four named owners set explicit entry modification times, preserving their
payloads, order, interfaces, compression and original test contracts. Decoded
source entries in the Dart replacement retain their metadata. No root Flutter,
production reader, checked-in asset, lockfile or security-probe change.

Evidence: docs/evidence/td-bz4y/README.md, inventory.json, commands.jsonl,
results.json, failures.json, preserved.json and HASHES.sha256. Controlled byte
comparisons fail before correction for all four owners, then pass, while changed
content still changes bytes. Both unfixed-clock controls pass in the valid runs.
Invalid initial clock-control attempts and an evidence-script syntax error are
recorded separately from meaningful red evidence.

Complete applicable isolated suites: epub_engines 102 passed; sync 27 passed,
13 local-HTTP-server tests explicitly skipped; dart_compat 5 passed, four existing
public-corpus skips. Focused suites also pass. Changed-file analysis and format
checks pass. Full dart_compat analysis retains an existing unnecessary_cast in
unchanged corpus_test.dart:45:18; new follow-up t0-bbyo records that separate work.

Native libmobi conversion callers are classified outside this four-owner scope;
only ignored conversion prerequisites were produced from checked-in MOBIs. No
new handwritten EPUB owner was found. No live server, device, browser, model or
public-corpus action; no coverage or general mutation run. One fresh read-only
review follows this implementation commit. Parent retains integration/closure.
