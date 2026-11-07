---
id: tf-0nvi
status: open
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

