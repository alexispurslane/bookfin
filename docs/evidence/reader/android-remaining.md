# Android EPUB: remaining native checks

Date: November 2, 2026. Tickets: `boo-ohud`, `boo-9wgg`, `t3-9r9u`, and `t8-j809`.

The shared global appearance checks pass on normal Android source `17c9e6b`.
The bounded image, applied-font, selection, large-text, offline, resource-denial, and navigation checks below also pass.
This is not full reader acceptance. Actual TalkBack remains blocked by the device automation host, tracked in `t2-u76g`.
Native permission callbacks and interception of arbitrary remote HTTPS requests are not independently proven.
No production behavior changed in this acceptance lane. The parent owns integration and ticket closure.

## Builds and device

An APK is the installed Android package. SHA-256 identifies its exact bytes.
All device actions used the worker's device-bound `agent-device` command on `local` / `emulator-5554`, Android API 36.
The package was `dev.bookfin.bookfin`. No physical device was tested.

| Observation set | Source | APK SHA-256 | Boundary |
| --- | --- | --- | --- |
| Initial screenshots 01–12 and unprefixed security probes | Checkout `8283109`; application runtime unchanged from `c279fd6d9fe6a792d04c8b6a15c519c4077aebde` | `e620a4eb5f61ead9a7e0e227f1c05189a74f0f9eaa624023ac36a4e4b90c6bd7` | Installed package pulled before reuse; source/runtime asset comparison passed |
| Screenshots 13–51, theme records, and `current-*` probes | `17c9e6bf175a5586566441183b8e8ed19534c1b6` | `8e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b` | Normal Nix debug APK, default `lib/main.dart`; installed readback equals build and final readback |

The second package contains 100,151,103 bytes. The source tree is `739c952eae10708e00fa4e6aae70efba1b4e0a47`.
Packaged `index.html`, `epub.js`, and `reader.js` match source bytes on both packages.
`provenance.json` records the individual hashes. The normal build took 212.3 seconds and reported existing Java target/deprecation warnings.
The parent-authorized merge of `17c9e6b` preceded this build. No custom Android entry point or renderer was used.

## Synthetic publication and request sink

Admission means converting an EPUB into the passive resources the reader permits.
Enforcement means refusing a request that the running WebView actually attempts.
The tests below keep these claims separate.

The fixture generator is `tool/acceptance/reader_remaining_fixture.py`.
It extends the existing semantic EPUB fixture with three chapters: Asset checks, Admission checks, and Reflow checks.
It uses the existing local PNG and licensed Source Serif WOFF2 font, a generated 2×3 JPEG, and twenty numbered paragraphs.
The exact single-image SVG wrapper and the active `onload` variant use the same JPEG.
The retained EPUB includes the existing font license. No corpus download or new dependency was needed.

| Retained input | Bytes | SHA-256 | Use |
| --- | --- | --- | --- |
| `initial-synthetic.epub` | 136,187 | `23c5416e3db33bdfe48b363a52f8ae9ab9de93bccc45ecb1156486284402251f` | Initial diagnosis only; remote CSS import shared the valid font/image stylesheet |
| `synthetic.epub` | 136,430 | `bcf88777f524e966d9f2445f5a253b83659644a704def64510674876082c7207` | Corrected fixture; remote import isolated in `Styles/denial.css`; all current-build checks |

The final processed publication identity is `66b8218f87a845923c2724e259a99fa22f6423f7960a0c4b31791660f4da72a0`.
The initial fixture caused rejection of the complete mixed stylesheet, not failed font decoding.
A new fixture regression failed for that reason, then passed after the fixture correction.
The source-change guard rejected the stale downloaded revision during replacement. The final download followed a catalog refresh.
Screenshots 05–08 retain the expected changed-publication warning; they do not prove same-publication resume.

Both owned ports were free before startup. Disposable Jellyfin 12.4.0 used host loopback port 7364.
The observer and request sink used host loopback port 7365, reached through the worker's Android reverse route.
The sink returned a visible HTTP 200 page and recorded only bounded request metadata.
All adversarial destinations were under `http://127.0.0.1:7365/probe/`.
No internet target, production account, or private publication was used.

## Security results

The `observe-native.mjs` diagnostic attached to the normal debug APK's exposed WebView through the Chrome DevTools Protocol (CDP).
CDP provides browser request events and font measurements.
Read-only observations did not change page state. The explicitly marked probes invoked requests from the trusted top runtime through CDP.
Those probes are diagnostic instrumentation, not normal-app interactions or admitted publication scripts.
Neither the publication sandbox nor production security settings changed.

| Case on `17c9e6b` | Attempt and observed result | Evidence | Claim and limit |
| --- | --- | --- | --- |
| Production admission | Unsafe script, frame, form, remote image, remote link, and active link do not survive as active content. Readable markers remain. Local link opens Reflow checks. | `current-admission.json`, screenshots 33–34 | Admission passes. Removed content never reaches native interception. |
| Native resource positive control | Actual GET of the admitted publication PNG returns 200 and 91 bytes. | `current-request-probes.json` | The same monitored WebView path can serve an allowed resource. |
| Native resource denials | Actual GET of missing publication resource, query-bearing admitted URL, and POST of admitted PNG each return 403 with zero bytes. CDP retains matching request/response events. | `current-request-probes.json` | Native resource boundary exercised for these requests, not merely a host resource-map unit test. |
| Remote fetch | Actual runtime fetch rejects with a Content Security Policy (CSP) error. CSP restricts destinations before native loading. | `current-request-probes.json` | CSP denial passes; this is not proof of native remote interception. |
| Top-level navigation | `location.assign` schedules and requests navigation to the owned sink. Document loading fails with `net::ERR_ABORTED`, `canceled: true`. Runtime URL remains unchanged and the reader stays visible. | `current-navigation-probe.json`, screenshot 32 | Actual forbidden navigation is canceled. No external activity opens. |
| Native HTTP loading path | CDP `Network.loadNetworkResource` targets the owned sink. It returns `net::ERR_CLEARTEXT_NOT_PERMITTED` / -29. | `current-network-resource-probe.json` | Native cleartext loading is refused. This does not isolate the app's arbitrary-HTTPS interceptor. |
| Camera and microphone | Actual `getUserMedia({audio:true,video:true})` returns `NotAllowedError: Permission denied`; new camera/microphone Permissions-Policy violations are recorded. | `current-permission-probes.json` | WebView policy denial passes. The native permission callback is not reached or independently proven. |
| Geolocation | Actual geolocation attempt returns error 1 and explicitly reports that Permissions-Policy disabled access. | `current-permission-probes.json` | WebView policy denial passes. The native geolocation callback is not independently proven. |

Meaningful controls reached the exact monitored endpoints through Android Chrome before the current-build diagnostic attempts.
Screenshots 27–29 show the sink's readable response for navigation, fetch, and native-resource endpoints.
The sink records confirm HTTP 200 at each exact path.
The counts below do not change between `http-events-before-current-probes.jsonl` and the final `http-events.jsonl`.
Thus a dead route or unobserved endpoint does not explain the absence of diagnostic sink hits.

| Sink path | Before current probes | After current probes |
| --- | ---: | ---: |
| `/probe/native-control-before` | 2 | 2 |
| `/probe/diagnostic-navigation` | 1 | 1 |
| `/probe/diagnostic-fetch` | 1 | 1 |
| `/probe/native-resource` | 1 | 1 |

CDP `Log.enable` replays historic console messages on attachment.
Use each capture's start time, matching Network/Page events, and new policy timestamps; do not count every replay as a new attempt.
The four owned Chrome tabs were closed individually. Screenshot 30 shows an empty tab list.
Chrome first-run completed without an account; its notification offer was declined. Unrelated browser data was not cleared.

## Images and actual font application

The current Asset checks screenshot is 31. Screenshot 43 repeats the assets after an offline process restart.
`current-assets.json` and `current-offline-assets.json` retain decoded image dimensions and rendered-font measurements.

| Asset | Native result | Limit |
| --- | --- | --- |
| PNG | Decodes at natural 24×24; drawn at 48×48 CSS pixels | One representative local PNG |
| Direct JPEG | Decodes at natural 2×3; drawn at 48×72 CSS pixels | One representative local JPEG |
| Exact passive SVG JPEG wrapper | Resolves to the same admitted JPEG; drawn at 48×72 | Only the exact supported wrapper shape |
| Active SVG wrapper | Shows `[Unsupported image: Active SVG blocked marker]`; no active SVG is served | Expected unsupported behavior, not a native attempted-request proof |
| Publisher WOFF2 | `BookSerif` FontFace is loaded. `CSS.getPlatformFontsForNode` reports `Source Serif 4 (Fontations)`, PostScript `SourceSerif4Roman-Regular`, `isCustomFont: true`, with 37 rendered glyphs for the sample paragraph | Actual applied custom glyphs, not just a computed family name; no universal font-format claim |

The initial mixed-stylesheet fixture instead used the reader's `BookfinSerif` fallback.
Its positive custom-glyph counts prove that fallback application only.
The corrected fixture associates and applies the publisher font. These are separate observations.

## Selection, large text, and offline reading

| Case on current build | Observed result | Evidence and limit |
| --- | --- | --- |
| Native text selection | Screenshot-grounded long press at device pixel (300,650) selects the word “sentence”. Android draws both selection handles and its Copy/Share/Select all/Web search/Read aloud menu. | Screenshot 41. Earlier selector-centered attempt in screenshot 34 did not select text and is not a pass. |
| OS large text | Bound `accessibility-large` sets Android `font_scale` to 1.75. With saved reader size 22, retained body measurement is 54.25 CSS pixels. Reflow has 37 pages; Next moves from page 1 to page 2. | Screenshots 35–36 and `current-offline-large.json`. Reports the retained measurement, not an assumed scaling formula or an interim observation. |
| Offline reading | Both fixture servers stopped, own reverse route absent, airplane mode on, Wi-Fi and mobile data off. Large-text paging still works. | Screenshots 35–36 and retained network-state readback. |
| Offline process restart | A new app process shows the saved library and “Cannot reach Jellyfin. Saved books are still available.” Read opens settled, readable Reflow checks. | Screenshots 37 and 40, `offline-restart-document.json`. Screenshot 39 is transient loading, not pass evidence. |
| Offline local navigation and assets | The real Return to asset checks link opens the asset chapter after restart. Images decode and the publisher font supplies actual glyphs. | Screenshot 43, `current-offline-assets.json`. |

The final offline observations used saved reader size 20 after reducing the reader control once.
The bound tool's `medium` preset was later found to mean Android scale 0.94, not the original 1.0.
The offline asset capture measures 17.672 CSS pixels under that preset. It does not prove a 20-pixel rendered body.
Cleanup restored exactly 1.0 through Android's Display size and text screen and read it back.
The screen automatically added a Font size quick-settings tile; cleanup removed that new tile without resetting other tiles.

An intended neutral tap after screenshot 41 accidentally selected the system's Read aloud action.
Screenshot 42 records that local overlay; Back dismissed it. No speech output was measured.
This is not a TalkBack pass. Copy, Share, and Web search were not activated.

## TalkBack: external host block

TalkBack is installed as `com.google.android.marvin.talkback`, version `16.0.0.738667889`.
The worker enabled it through Android Settings and its permission dialog.
Screenshots 09–10 show the enabled switch, not successful speech or focus navigation.
The retained Android report shows the service enabled but `Bound services:{}`.
Live inspection also reported `touchExplorationEnabled=false` and active `Ui Automation`; the retained excerpt does not include those two fields.

Read-only disassembly of the host's shipped snapshot-helper APK shows its `tryGetConnectedUiAutomation` calling the no-flags `getUiAutomation()` overload.
This is consistent with the automation helper suppressing other accessibility services.
No supported concurrent-TalkBack mode appeared in the bound CLI help or installed package documentation.
No helper patch, binding reset, unsupported installation, or adb UI workaround was attempted.
`talkback-host.txt` retains the narrow service and helper excerpts without unrelated window/client listings.

Actual TalkBack speech, reading order, focus movement, link activation, control labels, and return focus remain blocked in `t2-u76g`.
An accessibility snapshot is not substituted for those checks. No Bookfin defect is inferred from an unbound TalkBack service.
TalkBack was disabled again through Settings. The final no-service state matches the baseline meaning.

## Shared global appearance

The user chose one saved global mode, not a reader-only override.
Reader Night must select global Night. Reader Cream must select global Day. Automatic must remain available.
These are normal-app UI checks on `17c9e6b`, not diagnostic calls that set appearance.

The worker selected size 22, intentionally moved to Reflow page 2 of 5, then tested both directions.
The top visible text is the tail of passage 4: “follows these words in their written order without a network connection.”
Passage 5 follows it. The snapshot omits that leading tail; the screenshots do not.
The saved EPUB address is `epubcfi(/6/6!/4/14/1:85)` in the final publication.

| Action | App and reader result | Evidence |
| --- | --- | --- |
| Reader Night, then leave reader | Book details turns dark; the saved global mode reads `night` | Screenshots 15–16, `night-app-record.json` |
| Reopen reader | Night, size 22, same address, same visible text, page 2 of 5 | Screenshot 17, `night-reopen-document.json` |
| Restart app process, then Read | Library and reader remain Night; size 22 and same address remain | Screenshots 18–19, `night-restart-record.json`, `night-restart-document.json` |
| Reader Cream, then leave reader | Book details turns cream | Screenshots 20–21 |
| Reopen and restart app, then Read | Global `day`, size 22, same address, same visible text, page 2 of 5 | Screenshots 22–24, `day-restart-record.json`, `day-restart-document.json` |
| Open Appearance | Day selected; Automatic remains available | Screenshot 25 |
| Restore Automatic | Automatic selected; no city; follows the light system appearance | Screenshot 26, `automatic-offline-record.json` |

Distinct process IDs confirm restarts: 7474 → 8481 for Night and 8481 → 9049 for Day.
The offline restart later changes 10931 → 11695.
The narrow readbacks include only global appearance and the worker's synthetic account reading records.
Appearance comes from Android DataStore; reading records come from the shared-preferences XML.
The earlier `day-before-record.json` has no stored appearance value. It is not evidence of an explicit saved Day mode.

## Test and artifact audit

The fixture started with three meaningful failing tests, then passed.
A fourth regression reproduced the mixed-stylesheet fixture issue before its correction.
The initial red capture used port 7364 before the observer received its separate port 7365.
The red captures remain historical evidence, not byte-for-byte records of today's test source.
Final checks use project Nix only, with one heavy command at a time:

| Check | Result | Retained log |
| --- | --- | --- |
| Fixture tests plus existing observer safety tests | 9 passed | `final-fixture-tests.txt` |
| Production EPUB admission/resource tests on current source | 14 passed | `current-admission-tests.txt` |
| Installed final APK against built APK | Identical SHA-256 and bytes | `provenance.json` |
| Theme records, request events, sink counts, font glyphs, fixture hashes | Assertions pass | `artifact-audit.json` |
| Public artifacts against generated fixture passwords and tokens | No matches | `public-audit.json` |
| Whitespace | `git diff --check` passes | Recorded at commit |

No repeated full suite, coverage, mutation testing, soak run, or release APK claim.
The earlier 353/27 suite results and the parent's 356 Flutter results are not presented as executions by this worker.
All 51 retained screenshots were visually audited in ordered contact sheets; key outcome images were also inspected at full size.
No unrelated notification screenshot is published.

## Cleanup and failure audit

Screenshots 44–45 show removal of this worker's EPUB download and sign-out.
Screenshot 51 shows final empty sign-in fields after setting restoration.
The prior accounts' records were neither exported nor erased.
The synthetic account's remaining reading-history entries are noncredential preferences; app-wide data was not cleared.

| Owned state | Final result |
| --- | --- |
| Device settings | `font_scale=1.0`, airplane off, Wi-Fi on, mobile data on, TalkBack disabled, original helper input method retained |
| Global app appearance | Automatic, no city; synthetic account reader size returned to 20 |
| Servers and routes | Ports 7364/7365 have no listeners; disposable Jellyfin and observer exited; own reverse and diagnostic forwards removed |
| Build/test processes | Focused checks exited; own Gradle daemon stopped; another worker's Gradle process untouched |
| App and device binding | Bound session close reported success; device released with `shutdown:false`; emulator left running. A later readback still found Bookfin PID 11695. App-process termination is not proven. |
| Unrelated route | Existing `tcp:51800` scrcpy forward retained; helper-managed forward disappeared on successful session close |
| Private fixture files | Runtime account/token/password files and private captures removed after audit; ignored APK readbacks retained |

The first sign-in field refused focus. Its advised debug retry succeeded once.
A stale pinned reference and a misquoted selector each succeeded after the reported correction.
An attempted cross-origin stylesheet inspection failed; the diagnostic now reads stylesheet URLs without weakening the sandbox.
Unsupported help names were corrected using the tool's supported help, not a UI fallback.
During offline restart, a shifted button reference opened Remove instead of Read.
The worker chose Keep download, then the actual Read button; screenshot 38 records the unconfirmed dialog.
No download was deleted until the explicit final cleanup confirmation.
The first final sign-out capture still showed the notification shade. It was excluded from public artifacts; Back exposed the app for screenshot 51.

The session close returned `Closed: t3-0687f49c0b8d6053d5bd7d54`, but later `pidof dev.bookfin.bookfin` returned 11695.
That was the prior app process, not a new process launched by this worker.
A single explicit named-app close through the same bound command then failed with `No such file or directory` after device release removed its executable.
No binding reset or adb UI workaround followed. Ticket `t2-y0ce` records this host cleanup boundary.
The app was signed out with empty fields before release; no fixture server, reverse route, or diagnostic forward remains.
The last observed Bookfin process is the remaining cleanup limit, not an app security or reading failure.

The open limits remain actual TalkBack acceptance, isolated native permission callbacks, arbitrary remote HTTPS interception, physical-device coverage, and verified app-process termination.
Parent review, integration, and ticket closure remain separate work.

Artifacts: `tool/evidence/reader/android-remaining/`.
Screenshots: `docs/evidence/reader/images/android-remaining/`.
