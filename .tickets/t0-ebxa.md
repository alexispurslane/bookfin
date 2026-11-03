---
id: t0-ebxa
status: in_progress
deps: [boo-73yj]
links: [boo-mx5i, t3-jrhf, t3-ipk1]
created: 2026-11-02T12:38:42Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove PDFium callback ownership across Dart isolates

The November 2 host public-corpus run added a second PDF test file. Running both with the Dart default file concurrency aborts with exit 134: Cannot invoke native callback from a different isolate. The stack includes CFX_ExternalFontInfo::MapFont and FPDF_LoadPage. Individual suites pass. Research records the raw abort and serializes PDF test files; this does not establish safe concurrent production PDFium initialization.

## Design

docs/plans/bookfin.md; docs/research/reader-public-corpus.md; tool/research/readers/evidence/corpus/pdf-concurrent-abort.txt. Retain one coherent owner for native initialization, font callbacks and engine lifetime. No production engine redesign is selected by the research workaround.

## Acceptance Criteria

Reproduce the pinned callback-ownership failure in an isolated host process and establish the supported engine/worker ownership model. Prove safe document work through that model, including close/reopen and multiple callers, before parallel extraction or rendering is claimed. Preserve a nonzero crash report; do not catch native failures as ordinary parser rejection. Verify Android separately rather than generalizing a macOS observation.


## Notes

**2026-11-02T12:51:26Z**

Serial PDF test-file execution passes all eight PDF/Markdown checks together on the host. This is a research-runner remedy only, not evidence of safe concurrent production initialization or Android callback ownership.

**2026-11-02T13:15:24Z**

Start bounded ownership correction from integrated public corpus. Prove host callback lifecycle with real pinned engine, preserving Android verification as a separate required observation. No device work authorized by this launch.

**2026-11-02T13:41:14Z**

Bounded macOS ARM64 proof complete from 5815233235c0cf97999e1e7d00098494b7ccc557. New isolated reproducer deterministically retained SIGABRT exit -6 (callback-isolate error and FPDF_LoadPage), separate from ordinary PdfException rejection. One application isolate feeding the pinned dependency worker passed three simultaneously open document callers, real Helvetica font-callback events, close/reopen, once-only disposal callbacks, failed-caller cleanup, two actual worker-exit notifications, and restart with new worker identity plus working text/render/font callbacks. All 43 reader research checks passed (17 Python, 13 PDF/Markdown including five ownership checks, four original EPUB, nine joint-parser); scoped analysis and format checks passed. Original fixtures, corpus evidence, locks, serial setting and old PDF tests remain unchanged. See docs/research/pdf-worker-ownership.md and tool/research/readers/evidence/ownership/. This is research proof, not a production reader or cross-isolate routing adapter. Production must admit all native PDF calls in one application isolate and drain document/image disposal before worker shutdown. Android remains unverified under host stop rule; no device/browser/server/credentials/hardening/PR used. Ticket left in_progress for orchestrator integration and closure.

**2026-11-02T14:13:40Z**

Integrated reviewed 7498e52; independent static review passed host ownership proof. Corrected historical stop-rule wording: a separate Android attempt was reauthorized. Keep this ticket open for its separate Android verification; do not generalize host results.

**2026-11-03T14:16:49Z**

Exact normal Android attempt on 4ae8c6c is blocked before PDF native entry by t3-jrhf. Ordinary Jellyfin NIST original downloads intact but is routed to EPUB and rejected. Do not infer Android callback/font/disposal/reopen acceptance from the host proof or the empty normal-app error log. No production edit or closure. See docs/evidence/reader/android-normal-formats-20261103.md.

**2026-11-03T15:44:19Z**

Finite corrected normal 44d53af Android sequence succeeds: original PDF raster/fonts, NIST extracted text, original/reflow and close/reopen, short PDF, scan, Census, full process close, fresh true-offline process and NIST original/reflow. No observed native abort. This does not claim simultaneous documents, exact callback counts, explicit worker shutdown or stress/physical-device coverage. Evidence docs/evidence/reader/android-corrected-formats-20261103.md; crash buffer and audited screenshots retained. No closure.
