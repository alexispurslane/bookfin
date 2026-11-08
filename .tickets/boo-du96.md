---
id: boo-du96
status: in_progress
deps: []
links: []
created: 2026-11-08T01:32:05Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
---
# Fall back to the main record connection when the worker cannot open its read

Found in tf-0nvi. A large account is now read in a worker through a second, read-only sqflite connection. If the worker cannot open that connection for a reason other than damage (SQLITE_CORRUPT or SQLITE_NOTADB), the read fails and the account cannot restore, although the main connection could read it. Fall back to the read on the UI isolate's connection in that case, and report nothing to the user. Test it with a reader whose open throws a non-damage error.

