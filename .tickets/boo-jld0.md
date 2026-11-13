---
id: boo-jld0
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Refresh the catalog on resume only when it is stale, and skip the write when nothing changed

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/main.dart:331 starts a full catalog refresh at every return from hidden. lib/catalog/controller.dart:647-683 downloads every page of every library, builds the catalog and writes it, also when the content digest did not change. The code records `completedAt` and never reads it. test/app/resume_refresh_test.dart locks in one refresh for each return. Let the catalog own the freshness decision: refresh on resume after an unreachable result, or when the last success is older than a set interval, and skip the build and the write when the digest is unchanged. The interval is a tradeoff that the user sees, so the user decides it.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: a return to the foreground refreshes the catalog only when the last successful refresh is older than 1 hour. Launch, a refresh by hand, and a return after an unreachable result refresh as before. Skip the build and the write when the content digest is unchanged. test/app/resume_refresh_test.dart changes with this ticket.
