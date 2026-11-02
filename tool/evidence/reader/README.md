# Coordinated EPUB implementation evidence

Date: November 2, 2026. Base: `2daf2ef`. Tickets: `t3-9r9u`, then `boo-9wgg`. Both remain in progress for parent review, integration, and acceptance.

The review-correction pass starts from merged implementation `d9d238b0c140044143bf5b3e96b9a1371490a375`, which includes `3d0da653c022a8baa1080f0147c91ed2e330b498`. Both commits remain ancestors of this handoff. Corrections are new commits, not replacements of that implementation.

## Review corrections

Review correction R1: `corrections/r1-red.txt` records three meaningful failures across the actual source XML to iframe HTML-parser boundary. `corrections/r1-green.txt` records the same three passing after XML tree import replaces HTML reparsing. The cases cover implicit table bodies, paragraph normalization, and table foster parenting. Tests exercise saving, quote validation, search, contents fragments, and source IDs. Assets are rebuilt from the source fork. Android acceptance remains outstanding.

Review correction R2: `corrections/r2-red.txt` records lost bookmark snapshots, a missing bind/dispose retry, and an edit that reverted after reopening. `corrections/r2-green.txt` records five passing persistence scenarios. They use the real shared preference record merger with failure injected only at the reading-store boundary. They cover flush, account isolation, delayed old-account failure, audio/reading writes, disposal, and bookmark edit/delete after storage recovery. No process-death durability is claimed while storage remains unavailable.

Review correction R3: `corrections/r3-{red,green}.txt` records the production controls regression and correction. The test changes reported visible chapter/page counts, restores a bookmark, and supplies a new visible page count rather than reusing bookmark metadata. Unknown progress has no rail fill. `corrections/r3-engine-{red,green}.txt` checks actual source CFI ordering against two chapter anchors in one document and validates reported page counts. Host DOM tests do not measure Android page geometry.

Review correction R4: `corrections/r4-red.txt` records the actual outgoing 22px then 44px commands at 200% system text scaling. `corrections/r4-attach-red.txt` records an appearance command sent before renderer opening completed. `corrections/r4-green.txt` records both corrected scenarios. The native platform boundary is replaced only to record outgoing commands and return reader-ready events. Tests cover final size, theme, system scaling, reopen, saved-source anchor, and delayed attachment. The actual-engine appearance test in the final engine report checks CSS size and preserved visible-start CFI at the display boundary. There is no Android layout or device proof.

Final R2 checks split bookmark editing and deletion into separate behavior tests. `corrections/r2-delete-red.txt` restores only the original failed-write queue long enough to reproduce a deleted bookmark reappearing. The corrected queue is restored immediately afterward. `corrections/r2-record-guards-red.txt` records malformed stored lists and bookmark data throwing type errors when only recoverable exceptions are caught. Explicit input guards now preserve those damaged records without swallowing programming errors. `corrections/r2-persistence-final.txt` supersedes the earlier five-case checkpoint with nine passing cases. Each test uses one immutable admitted edition so ZIP creation times cannot change its source identity during account switching.

The final corpus test now opens the actual iframe for all nine processed editions. It resolves a source CFI in that iframe, generates a viewport CFI, and validates the quote against source XML after reopening. The three targeted R1 tests additionally assert that the source document is XML while the iframe document is HTML. They do not resolve both sides against XML.

| Final correction check | Result | Evidence |
| --- | --- | --- |
| Full Flutter app suite | 346 passed, 0 failed, 0 skipped | `corrections/host-final.txt` |
| Focused Flutter reader suite | 40 passed, 0 failed, 0 skipped. Included in 346, not additional tests. | `corrections/reader-final.txt` |
| Real publication admission | 9 passed, 0 failed, 0 skipped | `corrections/corpus-admission.txt` |
| Bundled engine regressions | 14 passed, 0 failed, 0 skipped | First TAP report in `corrections/engine-final.txt` |
| Engine and actual iframe on processed corpus | 9 passed, 0 failed, 0 skipped | Second TAP report in `corrections/engine-final.txt` |
| Clean asset rebuild | Locked npm install, build, and unchanged hash verification passed | `corrections/engine-final.txt` |
| Flutter analysis | No issues | `corrections/analysis.txt` |
| Dart format | 73 files, 0 changes | `corrections/format.txt` |
| SDK link, SDK platforms, and native hooks | Passed, including expected negative checks | Start of `corrections/host-final.txt` |
| Android ARM64 debug build | Passed in 287.4 seconds | `corrections/android-build.txt` |
| JavaScript web build | Passed in 23.2 seconds | `corrections/web-build.txt` |
| Packaged runtime assets | All four runtime hashes match source, APK, and web output | `corrections/artifact-hashes.txt` |
| Packaged Android manifest | Permission names, component exports/access guards, SDK levels, and application security flags match the reviewed baseline | `corrections/android-manifest.xml`, `corrections/artifact-hashes.txt` |
| Owned build processes | Gradle daemon stopped; no Java processes remain for this worktree | `corrections/cleanup.txt` |

Reproduction uses the existing pinned nine-edition corpus. This worktree copies the input and converted EPUB cache from the read-only implementation checkout, verifies each `epub_sha256`, and runs fresh production admission. It does not reuse previously processed documents or infer corpus success from the prior checkout.

Commands run through `nix develop`. Flutter suites use `--concurrency=2`. Engine verification uses `npm ci --ignore-scripts --no-audit --no-fund`, `npm run build`, `npm run verify`, `npm test`, and `node --test test/corpus.cjs`. Builds run one at a time. Resource snapshots are in `corrections/build-resources.txt`.

The Android command is `nix develop --command bash tool/bookfin build-android`. The web command is `nix develop --command flutter build web --no-wasm-dry-run`. Android dependency compilation reports deprecated/unchecked Java APIs and obsolete Java 8 source/target warnings. Web compilation retains the baseline missing Cupertino icon-font warning. Both builds succeed. No unrelated dependency or font change was made to silence these warnings.

The packaged Android manifest is decoded with `apkanalyzer manifest print`. The baseline evidence is a merged manifest, so formatting, resource identifiers, and compiler attributes differ. The security comparison normalizes `signature` protection to its encoded `0x2` value. It does not claim that the two XML files are byte-identical. The root Android sources are unchanged from `d9d238b`.

No Android acceptance, device, browser, installation, production credentials, production server, coverage campaign, mutation campaign, PR, or ticket closure is claimed. The host stop-rule reauthorization question remains with the parent. The unchanged Unicode and stylesheet-search limits remain documented in `docs/reader-implementation.md` and the search sheet.

## Baseline implementation results

All build, test, analysis, and format commands ran through the pinned Nix shell. Only one heavy command ran at a time. Resource checks preceded builds; `build-resources.txt` records the final checks. There were no device or browser actions, installation, runtime acceptance, production requests, public servers, coverage jobs, or mutation jobs.

| Check | Exact result | Evidence |
| --- | --- | --- |
| Passive publication and resource tests | 14 passed, 0 failed, 0 skipped | `admission-tests.txt` |
| Complete reader Flutter suite | 28 passed, 0 failed, 0 skipped. Included within the full app count, not additional tests. | `host-final.txt` |
| Production admission of pinned corpus | 9 passed, 0 failed, 0 skipped | `corpus-admission.txt` |
| Actual bundled engine regressions | 9 passed, 0 failed, 0 skipped | First TAP report in `engine-final.txt` |
| Actual bundled engine on processed corpus | 9 passed, 0 failed, 0 skipped | Second TAP report in `engine-final.txt` |
| Full app Flutter suite | 334 passed, 0 failed, 0 skipped | `app-tests.txt` |
| SDK and native-hook checks | Three shell scripts passed: additive SDK discovery, Android SDK 35/36 access compilation, and Darwin native compilation/signing. Negative signing probes deliberately print errors before their PASS result. | Start of `app-tests.txt` |
| Flutter analysis | No issues | `analysis.txt` |
| Dart format check | 71 files, 0 changed | `format.txt` |
| Rebuilt asset hashes | All four checked-in runtime assets matched before and after rebuilding | `reproducible-assets.txt`, `packages/flutter_epub_viewer/ASSETS.sha256` |
| Android ARM64 debug build | Passed; no installation | `android-build.txt`; `build/app/outputs/flutter-apk/app-debug.apk` |
| JavaScript web build | Passed; reader explicitly unsupported on web | `web-build.txt`; `build/web/` |
| Merged Android manifest inspection | No added media/storage permissions, exported services, or cleartext/network-policy relaxation. Existing audio service and media-button receiver remain. Plugin browser activities and receiver are not exported. AndroidX's profile-install receiver requires the DUMP permission. | `android-manifest.xml` |

The web compiler prints a missing optional Cupertino icon-font warning. The JavaScript build succeeds; Bookfin controls use Material icons. The initial Android compilation prints third-party Java 8/deprecated API warnings. These are not analyzer or test failures.

Original vendored engine sources and license texts retain their upstream whitespace, including CRLF license lines. Raw test logs also retain the test runner's whitespace. A generic `git diff --check` reports those files. Project Dart formatting is clean; source-only whitespace inspection excludes the vendored source, generated assets, licenses, and raw evidence logs.

## Meaningful red tests

These are historical failures recorded before each correction. They are intentionally failing evidence, not the final suite result. Some combined historical logs include more than one failure. The final results table is the authority for passing counts.

| Evidence | Behavior that failed before correction |
| --- | --- |
| `publication-red.txt` | Publication scripts and active SVG remained available; remote CSS remained; archive traversal was admitted. |
| `processed-limit-red.txt` | Repeated short SVG-wrapper references expanded into a processed chapter larger than the admitted resource limit. |
| `boundary-red.txt` | A remote request returned no intercepted response, which delegated it to the WebView instead of explicitly denying it. |
| `epub2-contents-red.txt` | The processed OPF lost its admitted EPUB2 NCX contents item. |
| `local-style-policy-red.txt` | The runtime content-security policy did not admit local publication stylesheets. |
| `local-base-policy-red.txt` | The inherited runtime policy blocked the trusted engine's local publication base address. |
| `imports-red.txt` | A valid local CSS import was omitted. |
| `engine-red.txt` | Inline, repeated, short-document, hidden-text, and Unicode-offset search behavior was wrong. |
| `navigation-red.txt` | Encoded destinations and validated visible-start locators did not resolve correctly. |
| `corpus-navigation-red.txt` | A real nested semantic-note fragment produced an unresolvable CFI. |
| `font-selection-red.txt` | Reader typography overrode the edition's explicit font. This test exercises actual engine CSS APIs and computed style, not font rasterization. |
| `unicode-length-red.txt` | Unicode lowercase expansion silently discarded a query below the public query-length limit. |
| `records-red.txt` | An audio record write overwrote reading records. |
| `reading-before-audio-red.txt` | A reading-only account record prevented the first audio session from restoring or saving positions. |
| `session-red.txt` | Positions did not restore; old account work remained visible; incompatible processed content did not reject a saved location. |
| `restore-close-red.txt` | Closing during account-record restore allowed the pending book to open afterward. |
| `source-removal-red.txt` | A removed edition cleared the viewport without an error, leaving an indefinite loading state. |
| `isolation-red.txt` | An old account's delayed open survived record restoration; the large-text search error was not visible. |
| `local-boundary-red.txt` | Real verified LocalDownloads files did not complete admission and reopen. |
| `controls-red.txt` | Production control tests exposed invalid platform initialization instead of an explicit unsupported-platform boundary. |

`final-boundaries.txt` is an earlier passing combined checkpoint: 26 reader tests, nine corpus admissions, eight engine regressions, and nine engine corpus tests. It predates the final reading-before-audio and Unicode query-length regressions; use the final table for current totals. `reading-before-audio-green.txt` is the focused two-test record-store confirmation.

## What remains unverified

Host DOM tests exercise real processed documents, actual fragment resolution, exact search ranges, and fresh-engine locator reopen. They do not supply browser geometry and cannot establish rendering or sandbox enforcement. Flutter widget tests exercise production controls on the explicit unsupported-platform path. Appearance tests replace the native WebView boundary to observe renderer commands; they do not establish Android rendering or native enforcement.

Android acceptance remains required for XHTML/CSS layout, rendered PNG/JPEG, applied embedded and fallback fonts, visible-start pagination, large-text/focus behavior, TalkBack, offline operation, force-stop/process-death resume, and native network/navigation/permission denial. The original source revision and both content identities are checked by host record tests, but those checks do not replace actual Android visible-start acceptance.

The implementation limits and reproduction commands are in `docs/reader-implementation.md`. Parent review must also consider the documented removal of the unused `marks-pane` path and replacement of the license-text-missing `path-webpack` shim. The selected navigator remains the bounded Flutter wrapper plus clean pinned epub.js, not Readium or another silently selected package.

## Follow-up review corrections

Malformed combined records and reading sections now raise FormatException at the storage decoder. Regression cases preserve the damaged bytes, disable saving for that account, then save a bookmark for another account. Obsolete location failures now obey the same newest-event rule as successful locations. The engine regression delivers a newer valid location before rejecting the older request and also checks that a current failure still reaches Flutter. Red evidence is in outer-storage-red.txt and obsolete-location-red.txt; all 15 engine checks pass in correction-engine-green.txt. These host checks do not establish Android acceptance.
