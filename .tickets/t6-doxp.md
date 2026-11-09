---
id: t6-doxp
status: open
deps: [boo-981b]
links: []
created: 2026-11-09T17:35:49Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Take a PDF's original digest from Downloads instead of hashing it at open

t7-rcyp gives the reader the SHA-256 digest that Downloads computed when a download completed (VerifiedFile). EPUB and MOBI opens use it. PdfRuntime.open in lib/reader/pdf.dart still hashes the whole PDF in a worker at each open (compute(_digest, bytes)). Pass VerifiedFile.digest to it, so that one owner keeps the fact.

## Acceptance Criteria

A PDF open does not hash the file, and a saved PDF place still opens.

