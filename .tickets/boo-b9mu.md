---
id: boo-b9mu
status: open
deps: []
links: []
created: 2026-11-08T01:11:02Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
---
# Find why five downloads tests did not complete in one full run under heavy load

After the group A merge (t9-cx1u moved byte progress to the per-edition watches), one full run of flutter test on main at load 20 on 10 cores reported 'did not complete' for five tests: transfer_test 'a missing complete file contributes no bytes to a queued retry' and 'player lookup waits for saved files before declaring them unavailable', and retained_test 'retained removal never follows or deletes a linked media file', 'verified lookup refuses a source directory replaced with a symlink' and 'a corrupt retained copy is not playable after reselection'. test/downloads alone passed (164 tests), and two more full runs at the same load passed (1141 tests). Find whether these tests wait on a real-time condition (for example waitForBytes or a watch notice) that can be missed or that times out under load, and make them deterministic.

