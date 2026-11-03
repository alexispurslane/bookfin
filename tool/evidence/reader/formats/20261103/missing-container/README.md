# Original format admission without Jellyfin Container

Base: 2ece46b. Ticket t3-jrhf.

The normal Android acceptance captured ordinary Jellyfin Book entries without
Container or MediaSources. Their downloaded PDF/MOBI originals were intact, but
the reader selected EPUB solely because the container field was empty.

The new tests pass a real buildBooks result from that DTO shape into the
production loader. Each fixture is copied unchanged to an extensionless
`complete` file, as in the production download layout. Four meaningful failures
show Unsupported EPUB ZIP directory for PDF, plain MOBI, PalmDOC-compressed
MOBI and KF8. EPUB and invalid-file/link rejection controls already passed.

For missing container metadata, the existing loader reads at most 1024 bytes
from its verified local file. A leading PDF signature selects PDFium; the Palm
Database BOOKMOBI type/creator fields select the existing MOBI importer. Other
inputs retain passive EPUB admission. Explicit container metadata keeps its
existing parser selection. File signatures are routing hints, not validation:
the original native parser or passive publication admission still validates
the complete document. No catalog revision/source key, downloaded bytes,
permission rule, cache identity or record owner changes.

All 17 focused importer/PDF/session tests pass, including native rendering,
conversion, cache repair, restart, EPUB and rejection controls. These tests
execute production host importers; they do not establish corrected Android
runtime acceptance or repeat a real Jellyfin network download. No device action
occurred in this correction lane.

Commands use the pinned Nix shell:

    flutter test test/reader/unknown_format_test.dart --reporter expanded
    flutter test test/reader/unknown_format_test.dart test/reader/mobi_document_test.dart test/reader/pdf_document_test.dart test/reader/pdf_session_test.dart --concurrency=1 --reporter expanded
    flutter test --concurrency=1 --reporter expanded
    flutter analyze

Final full verification: 431 tests pass, three opt-in skips; analysis reports
no issues. See full-tests.txt and analysis.txt. Independent review and a fresh
normal Android artifact remain required before runtime acceptance.
