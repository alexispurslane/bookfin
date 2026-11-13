---
id: boo-3y46
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep discovery going past a server object that this build cannot apply

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:504-512 and 546-549 throw a FormatException for a tombstone, or for an action value that this build cannot decode, before the cursor advances. The object stays on the append-only server, so every later sync on that device throws on the same page and the device receives no later record from any device. lib/sync/coordinator.dart:321-324 reports the failure as "plugin missing". test/sync/transport_test.dart:211 and closed ticket t9-of05 lock the throw in, so a change needs a user decision. Proposed model: keep the object, apply the rest in causal order, hide the unreadable value, report a count, and give the case its own failure kind. Skip tombstones, or remove DELETE from the plugin.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: keep it, skip it, go on. The phone stores a record that it cannot apply, advances the cursor, receives everything after it, and shows a quiet count of records that need a newer Bookfin. The case gets its own failure kind, not pluginMissing. This reverses the stop that t9-of05 and test/sync/transport_test.dart:211 lock in, so that test changes with this ticket. Add a test for the sync after such a record.
