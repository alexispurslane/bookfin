---
id: tc-p3j8
status: in_progress
deps: []
links: [tc-butt, boo-hyl4]
created: 2026-11-11T15:31:25Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make a move's distance agree with its two shown places

Found during boo-hyl4 on 2026-11-11 (docs/plans/history-choice.md, finding 3). A listening move label rounds the difference of the exact times, while each place text rounds its time down to whole seconds. A seek from 3,775,900 ms to 3,735,100 ms reads 'Moved back 41 s' with places 1:02:55 and 1:02:15, which are 40 s apart. Above a minute, duration() rounds to whole minutes: 10:00 to 11:31 reads 'Moved ahead 2 m'. Both history designs of boo-hyl4 keep this fix, so it ships first.

## Acceptance Criteria

The distance in a listening move's label equals the difference of the two place texts that the timeline shows for its before and after places. Under an hour, a distance of a minute or more names minutes and seconds, such as 1 m 31 s. A behavior test covers a seek whose exact difference rounds differently from its shown times.


## Notes

**2026-11-11T15:54:14Z**

A listening move's distance now subtracts audioSeconds (lib/foundation/time.dart), the whole seconds that audioTime shows, and names every unit from the largest nonzero one to the smallest nonzero one: 3,775,900 -> 3,735,100 ms reads 'Moved back 40 s'; 10:00 -> 11:31 reads 'Moved ahead 1 m 31 s'; an hour or more reads like '1 h 2 m 5 s'. Tests in test/playback/timeline_route_test.dart.
