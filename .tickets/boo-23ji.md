---
id: boo-23ji
status: in_progress
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

## Settled integration scope — 2026-11-13

Keep the existing document, survey and session owners. Make cleanup release all owned resources even when awaited work or survey shutdown fails. Preserve the original failure for the appropriate caller; do not treat a failed contract as successful work or retry a failed survey page indefinitely. A failed previous close must not poison the session's later open/close chain. Include pending PDF work, text-supply shutdown, PDFium disposal, and owner release in the lifetime audit; no new lifecycle framework or navigation redesign.

Prove meaningful failures with controlled completion/failure tests, including a non-Exception Error, once-only disposal, later successful open/close, and survey failure retention. Inspect existing contract semantics explicitly. Required checks: focused regressions, reader/crossings/speech affected suites, full Flutter suite, changed-file analysis/format and diff checks. Nix, concurrency two, one heavy command at a time. No devices, coverage, mutation testing, push or PR. One fresh read-only Astra high reviewer; direct Astra xhigh fixes with red-green evidence. Parent integrates and closes.

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible (it needs an Error that is not an Exception). lib/reader/pdf.dart:1108-1118, lib/reader/session.dart:663-669, lib/reader/book_survey.dart:279-338. `_dispose` awaits `survey.close()` before its `try`, so an Error from the survey skips `_document.dispose()` and leaks the PDFium handle. The `_closing` chain of the session handles only Exception, so it stays failed: every later open reports "could not be opened" and every later document leaks. The survey does not add the failing page to `_failed`, so each page turn runs the failing analysis again. Put the release in a `finally`, keep the chain going after any failed close, and mark the page failed before the Error propagates.
