---
id: boo-0ptc
status: closed
deps: []
links: []
created: 2026-11-10T13:01:11Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide whether PDF search keeps its note about skipped pages

Found in te-h8ip. PDF search ends with 'Search skipped N source pages without reliable text…'. The note counts pages whose content cannot reflow (covers, contents, diagrams) together with pages whose recognition failed. The user asked earlier to remove disclaimers in the PDF reader, but this note tells the reader that results can be incomplete. Ask the user; if it stays, count only pages that may hold searchable text.


## Notes

**2026-11-10T13:26:09Z**

User decision (2026-11-10): count only pages that Bookfin failed to read (PdfTextStatus.failed, or an exception). Covers, contents, diagrams and pages without text are skipped quietly.
