# Integrated sync and reader candidate

Runtime source: 40ee5d4 (reviewed sync/format merge 681c168 plus packaging
6a7fb49 and source-export evidence 40ee5d4). No production-source merge conflicts.
Ticket-note conflicts retained both histories.

Pinned Nix shell verification:

    flutter test --concurrency=1 --reporter expanded
    flutter analyze

407 Flutter tests pass, one optional actual-plugin test skipped. Analysis is
clean. This verifies the combined source, including native notices tests.
No new Android runtime, two-device sync, library replacement or legal acceptance
is inferred. Research OCR probes remain separate from this production source.
