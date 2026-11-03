# Format review corrections

Base: dbc54ed92d976d1072cd0e55c60a7546915b76ac, which contains reader milestone
94457bf and the approved sync fixes. Independent packaging/OCR commits are not
in this checkout. No packaging, model, engine asset or dependency changed here.

## Ownership and behavior

F1: Reader loading uses Downloads.readLocalFile. LocalDownloads admits the
verified-file callback through its existing command queue, so native import
finishes before removal or account restoration can reclaim the source directory.
The original is verified inside that operation. A read queued after removal
cannot start a converter. No extra queue, durable cache index or reader-owned
removal callback was added. The same command queue means other download commands
wait for an admitted reader import; this is bounded ownership, not cancellation
of native work already running.

DerivedBookFiles defines the existing MOBI subtree once. The importer uses its
directory; the download owner uses its byte query and deletion operation.
Current unavailable-file controls include derived bytes. Retained inventory
includes regular derived files even if the original has disappeared. Current
and retained removal delete the subtree within the existing account/source
containment checks. Symbolic links contribute no bytes and are never traversed.
A disappearing subtree reports zero derived bytes during removal.

F2: The viewport admits one draw for a page generation. A later page generation
can proceed; completion from an earlier generation cannot clear the newer draw
guard or publish an old image. Existing stale-result disposal remains in place.

F3: Backward movement across a reflow source-page boundary loads the preceding
source page at its text end. The existing text layout clamps this to its last
viewport and publishes that viewport's first character. Forward movement and
explicit Contents/search addresses keep their normal beginning or saved anchor.

## Regressions and evidence

red.txt contains four meaningful baseline failures: current cache removal,
cache-only retained byte accounting, repeated draw admission, and previous-page
reflow placement. The last failure was offset zero instead of the preceding
page's final viewport at 6,172 logical pixels.

The PDF tests use the real Flutter viewport, text layout, scrolling, raster
decoding and ui.Image disposal. The PdfBook boundary supplies long text and a
held raster; they are not new native PDF-parser acceptance tests. Existing
real native PDF tests remain in the full suite.

The removal/import regression seeds real MOBI bytes in a correctly scoped,
hashed and verified download record. It holds the actual native loader's entry,
requests normal removal, then releases conversion. With command serialization
temporarily removed, removal completes before import: removal-race-red.txt.
The production test requires import success, complete cleanup, and refusal to
start another read after removal. A 100-ms observation interval detects early
removal; final native import and filesystem assertions do not depend on a
simulated converter. An earlier zero-duration observation did not expose the
race and is not claimed as red evidence.

A separate retained-file test places a link to an external directory in the
derived subtree. Its bytes are excluded, and its target remains unchanged after
removal. Existing account isolation and directory-link regressions also run.

Commands use the pinned Nix shell:

    nix develop --command bash -c 'flutter test test/reader/pdf_navigation_test.dart test/downloads/retained_test.dart --reporter expanded'
    nix develop --command bash -c 'flutter test test/downloads/retained_test.dart --plain-name "removal waits for a running native MOBI import" --reporter expanded'
    nix develop --command bash -c 'flutter test --concurrency=1 --reporter expanded'
    nix develop --command bash -c 'flutter analyze'

The first complete suite passed 405 tests with one optional real-plugin skip.
The first analyzer run found two missing-brace style messages; initial-analysis.txt
retains them. They were fixed, and the final suite and analyzer were rerun.

No Android build/install/runtime, actual-plugin rerun, native replacement
installation, legal-compliance acceptance, OCR acceptance, coverage or mutation
campaign is claimed. The targeted serialization-disabled red check above tests
this fix; it is not a broad mutation campaign. Existing iOS SDK warnings are
native-hook output on this host without an iOS SDK.

Final verification: 405 Flutter tests passed, with one optional actual-plugin
skip. Flutter analysis reported no issues. See full-tests.txt and analysis.txt.
