---
id: t1-fe3e
status: in_progress
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


## Notes

**2026-11-08T01:13:08Z**

Decision, Nov 7: the store retries the rewrite. After a failed rewrite into the new file, the cache keeps every account, including the change that failed, because memory holds their only copy outside the kept file. Each later operation first tries the rewrite again (_rewriteDue in LocalResumeStore). Tests in test/durability/record_store_test.dart: damaged pages found by replaceDamaged, and a full disk during the rewrite.
