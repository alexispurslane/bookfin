---
id: tf-0nvi
status: in_progress
deps: [td-rvpm]
links: []
created: 2026-11-07T23:48:23Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [performance, engine-rules]
---
# Read personal-record rows without decoding them on the UI isolate

Found in boo-4bof. On Android, sqflite returns the rows of RecordDatabase.rows through a platform channel, and the channel codec decodes them on the UI isolate. An account read therefore still decodes all retained action payloads as strings on the UI isolate before the hop. That is about 7 MB for six hours of listening. The JSON decode, the journal replay and the snapshots already run in the hop.

Find out whether sqflite can run its queries from a background isolate on Android (BackgroundIsolateBinaryMessenger), or whether another SQLite binding reads rows in the worker. Measure the channel decode of a large account on the phone before you choose.

## Acceptance Criteria

A measurement on the phone of the channel decode for a large account. Then either the rows load in the worker isolate, or a comment in database.dart records why they cannot.


## Notes

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: one agent does tf-0nvi and boo-7ua0 together (group C), store and sync work.

**2026-11-08T01:01:58Z**

Group C, Nov 7. Measured on emulator-5556 (arm64-v8a, 4 vCPUs on an Apple M1 Max host), not on the phone, by the orchestrator's change of rules. Bench: tool/research/record_rows_bench, results in results-emulator-5556.txt. For 21,600 resume actions (10.5 MB of payloads, about 485 bytes each), the read of RecordDatabase.rows on the UI isolate stalls it for 20 to 26 ms (median of 3 runs: 25 ms), and StandardMethodCodec alone decodes the reply in 15 to 16 ms. For 43,200 actions the stall is 44 to 52 ms. The same read in a worker isolate through BackgroundIsolateBinaryMessenger stalls the UI isolate for 4 to 9 ms, which is the noise of the 1 ms timer; wall time is the same (about 340 ms). sqflite works from a background isolate: with singleInstance: true it hands back the UI isolate's native connection (static map in SqflitePlugin.java), which is unsafe, because the Dart transaction lock is per isolate. With singleInstance: false and readOnly: true it opens a second connection in the same Android SQLite library, which can read in its own transaction and close. Recommended build: the restore hop opens that connection, reads, decodes and replays in one Isolate.run, and reports SQLITE_CORRUPT to the UI isolate, which sets the file aside (ta-4rwp). Not built yet.
