# t7-3j9c: production and gallery browser builds

Original base and initial HEAD: `62f4fb238861fd601acb2668a9a4d646c8a28c77`.
Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-55dca846`.
Branch: `t3/55dca846`. Initial checkout was clean; the original-base diff was
empty. The ticket was already in progress and had no dependencies.

## Failure and correction

The original production build could not compile `dart:ffi` for the browser.
The import ran through account binding, crossings, text outlines, book maps,
PDF documents, and `pdf_outline.dart`. Its transitive `ffi` and `pdfium_dart`
imports also failed. Both production and gallery entry points failed in the
new executable build regression, before any production code changed.

The first attempt lacked `.dart_tool/package_config.json` in the fresh
worktree. Dependency setup succeeded, then the exact original command failed
for the native imports. The setup failure is not red evidence. The later red
builds compile the actual application, with no invented fixture or missing
test reference: browser import portability is the defect being reproduced.

`pdf_outline.dart` keeps its pure calculation and selects file measurement
through the same conditional-export convention as `reader/platform.dart` and
`reader/ocr_storage.dart`. `pdf_outline_io.dart` contains the existing native
implementation. Its worker scheduling, private handle, eight-millisecond
slices, and `finally` cleanup are unchanged. `pdf_outline_stub.dart` reports
an unsupported operation. It supplies no browser PDF reader or outline.
The existing reader platform stub remains unchanged.

No caller needs platform knowledge or a new argument. The native measurement
body and pure calculation body are byte-for-byte relocations; the separate
relocation audit records that static inspection. This is not a source-text
regression test. Seven existing calculation tests moved out of the native
fixture suite unchanged, and one test checks that the browser implementation
rejects file measurement rather than supplying an empty outline.

`test/web_build_test.sh` compiles both real entry points and checks that each
produces a nonempty JavaScript application. Run it from the project root with
`nix develop --command bash test/web_build_test.sh`. It launches no browser.
The corrected builds expose no further blocking native import. Their existing
warnings about secure-storage WebAssembly compatibility and a missing
Cupertino font remain; this ticket verifies the default JavaScript builds.

## Evidence

`commands.json` records the exact command arguments, working directory, exit
code, duration, results and archived output for each verification command.
Every log is complete stdout and stderr, compressed without altering its
bytes. The manifest records raw-byte SHA-256 hashes and original paths under
`/tmp/bookfin-t7-3j9c`. `historical-boo-jlhy-web.log.gz` preserves the supplied
historical failure separately from this ticket's reproductions.

All builds, tests, analysis and format checks use the project's pinned Nix
shell. Flutter tests use two workers at most, with one heavy command at a time.
No existing test was disabled, no timing threshold changed, and no other
owner's process was stopped. Detailed results and skip names are in the
manifest and logs.

The focused native run passed 109 tests. The affected reader, crossing, app,
gallery and playback crossing suites passed 1,817 tests with 21 skips. The full
Flutter suite passed 3,693 tests with 27 skips: one more pass than the supplied
parent baseline, from the new unsupported-operation test. Affected analysis
found no issues. Format verification changed no files, and the build script
passed Bash syntax verification. Original-base whitespace checks cover the
entire staged change and are repeated at the final HEAD.

The seven relocated calculation tests are regression preservation, not newly
failing behavioral tests. The runtime rejection test protects the new browser
stub. The original application builds are the meaningful red check for this
import-portability repair. No test source was grepped to establish correctness.

## Limits and ownership

Browser builds do not establish browser interaction or device acceptance.
No browser or device tools, credentials, coverage or general mutation campaign
were used. There is no push, PR, merge, deployment, ticket closure or worktree
removal. The parent owns integration, acceptance, hardening and closure.

The integrated tf-il7u correction is preserved. The separate t5-rplx failure
remains unexplained; a passing run here would not establish its cause.
No product fork arose. The implementation follows the accepted PDF outline
and engine rules in `docs/plans/cross-edition-places.md` and the ticket scope.
