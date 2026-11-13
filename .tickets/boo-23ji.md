---
id: boo-23ji
status: open
deps: []
links: [boo-x1zf]
created: 2026-11-12T23:41:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Release PDFium and keep the close chain alive when a PDF close fails

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible (it needs an Error that is not an Exception). lib/reader/pdf.dart:1108-1118, lib/reader/session.dart:663-669, lib/reader/book_survey.dart:279-338. `_dispose` awaits `survey.close()` before its `try`, so an Error from the survey skips `_document.dispose()` and leaks the PDFium handle. The `_closing` chain of the session handles only Exception, so it stays failed: every later open reports "could not be opened" and every later document leaks. The survey does not add the failing page to `_failed`, so each page turn runs the failing analysis again. Put the release in a `finally`, keep the chain going after any failed close, and mark the page failed before the Error propagates.

