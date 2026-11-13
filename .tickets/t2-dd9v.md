---
id: t2-dd9v
status: open
deps: []
links: []
created: 2026-11-13T02:25:13Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Retry a speech landing after one stopped or failed window

lib/speech/heard_windows.dart:297-303 turns WorkerStopped into a null window. lib/crossings/crossings.dart:286-300 then keeps that null in _heardDone as speech refused until downloads change. Go to on that history entry uses matched chapters for the rest of the run after a transient failure. The comment near crossings.dart:288 says stopped workers should not be kept. Preserve enough information to retry a transient failure, while keeping a lasting refusal cached.
