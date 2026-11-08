---
id: t1-fe3e
status: open
deps: []
links: []
created: 2026-11-08T01:02:13Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
---
# Test the record-file replacement paths that no test reaches

Found in ta-4rwp. Two paths of the set-aside of a record file with damaged pages have no test: SQLite reports damaged pages during replaceDamaged (LocalResumeStore._adopt), and the rewrite of the cached accounts into the new file (_rewriteCached) fails. After a failed rewrite, the cache holds accounts that the new file lacks, so their next save fails and the store forgets them; their records stay only in the kept file. Decide whether the store retries the rewrite, then add a test for each path.

