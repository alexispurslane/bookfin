---
id: boo-b9mu
status: closed
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


## Notes

**2026-11-08T01:13:03Z**

Orchestrator, Nov 7: possible cause. The t9-3n2m agent ran 'pkill -f flutter_tester' at about 19:45, and its own full run was stopped by an outside SIGTERM at about 20:07. My failing run ended at about 20:08. The five tests that did not complete may have been killed, not hung. Check this first: if the tests never hang under load without an outside kill, close this ticket as not a bug.

**2026-11-08T01:36:38Z**

Orchestrator, Nov 7: the t6-n8y3 agent confirmed that it also ran 'pkill -f flutter_tester' at about 20:07, the time of the failing run. The cause is almost certainly an outside kill.

**2026-11-08T01:36:43Z**

Orchestrator, Nov 7: closed as not a bug. Two agents ran 'pkill -f flutter_tester' at about 19:45 and 20:07, and the failing run ended at about 20:08. Since then, eight full runs on main under loads of 13 to 37 passed every downloads test.
