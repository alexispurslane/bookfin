---
id: boo-tapn
status: open
deps: []
links: []
created: 2026-11-07T23:50:31Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [test, flaky]
---
# Make the large-library bind timing test pass under heavy load

test/downloads/signals_test.dart 'a large library binds without hashing its sources on the UI isolate' (t9-4jqk) compares the bind's synchronous part with half of the inline hashing cost. It failed once in a full run at a02f679 with load 28.8 on 10 cores, then passed 5 of 5 alone and in the next full run. t9-4jqk reported about 1 failure in 30 runs at an earlier threshold. Prove the property without wall-clock timing, for example by counting hash calls on the UI isolate through an injected hasher or hop.

## Acceptance Criteria

The test fails if source ids are hashed on the UI isolate and never fails because of machine load (soak run of 50 under parallel load).


## Notes

**2026-11-12T12:27:53Z**

Failed again 2026-11-12 in the full run on main at 5152fb0c (load 40 on 10 cores); passed 3 of 3 alone.
