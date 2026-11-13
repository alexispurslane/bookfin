---
id: boo-hmrp
status: in_progress
deps: [boo-f4xm]
links: [boo-0931, boo-s11s]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Upload pending records when playback pauses or the app hides

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/main.dart:333-341 calls `sync.suspend()` when the app hides, and `playback.flush()` writes only to local SQLite. No code calls `synchronize()` while the app is hidden (lib/sync/coordinator.dart:171-175). An hour listened with the phone locked stays on the phone until Bookfin opens again. A second device then plays from the old place, and the two devices produce a "Choose a saved place" conflict. Drive the upload from events: pending actions plus a pause, a stop, a book change or the app hiding, with a debounce. During background playback, use the 10-second cadence that lib/playback/reporting.dart:76 already has. Keep the boo-nxp8 decision of no polling while idle.



## Astra implementation launch

Review base: 3e345a1737fd0312e3fb6b5575eddf7de9ea2df1. Separate T3 worktree; implementation and direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. One fresh read-only reviewer is authorized with the same provider/model and reasoningEffort high. No other stage agents. Required checks include affected suites/analysis and the full Flutter suite through nix develop with concurrency at most two. Parent owns integration and closure.

Client request ID: bookfin-boo-hmrp-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.
