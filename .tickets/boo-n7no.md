---
id: boo-n7no
status: open
deps: []
links: [boo-f4xm, boo-rw9z, boo-2bl9, boo-w6m2]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give Playback and ReaderSession one record writer

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/playback.dart:1674-1770 and lib/reader/session.dart:1690-1787 each implement the same protocol: pending change sets, `followedBy` and `applyTo`, failed accounts, a record revision, the refresh guard, and the rule about `acceptSnapshot`. The copies already differ: the reader retries the pending changes of every account on every save, and Playback retries an account only when it is bound again. Make one writer, generic over the place type and the record codec, or let the store own the pending overlay and its retry. This also removes about 400 lines of record state from Playback.

