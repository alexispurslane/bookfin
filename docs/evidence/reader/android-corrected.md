# Android EPUB after the missing-format correction

Date: November 2, 2026. Times use UTC unless marked otherwise.
Correction: `203f870690a7aea36c5110e088daf74799b2f151`.
Built source: `ae8dcd918cb7791e841534461652501488d05c92`.
New runtime blocker: `t8-jj2s`. All tickets remain open for parent integration.

The normal Android app downloaded an unmodified EPUB from actual Jellyfin
12.4.0 and displayed readable chapter text. The ordinary user's Book response
omitted both `Container` and `MediaSources`. This satisfies the runtime case
that previously failed under `tb-zqvc`. It does not accept the whole reader.
Reopening a later page lost that page, and appearance preservation remains
unaccepted. No production application code changed during this test.

## Source and installation identity

This checkout started at `ac6a247` and merged the reviewed correction.
The merge retained both sides' additive ticket notes. Application, Android,
reader-package, dependency, and Nix sources exactly matched `203f870`.
The build ran afresh in this checkout. It did not use the old implementation
checkout APK, a test entry, or a package built after the concurrent corrections.

An APK is an Android installation file. SHA-256 identifies its exact bytes.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Fresh normal ARM64 debug APK | 100145127 | `a7c85ad40777950a1f797b1b6c35e7647855cb27d026cd11dc34a8c7b4f253da` |
| Installed APK read back before launch | 100145127 | `a7c85ad40777950a1f797b1b6c35e7647855cb27d026cd11dc34a8c7b4f253da` |
| Installed APK read back after cleanup | 100145127 | `a7c85ad40777950a1f797b1b6c35e7647855cb27d026cd11dc34a8c7b4f253da` |
| Generated original EPUB | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |
| Downloaded EPUB read back from app storage | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |

The build command was `nix develop --profile .cache/dev-shell --command bash -c 'bash tool/bookfin build-android'`.
It used the normal `lib/main.dart` entry and completed in 235.4 seconds of
Gradle work. Package inspection reported `dev.bookfin.bookfin`, version `0.1.0`,
version code `1`, minimum Android SDK `24`, and target SDK `36`.
The source archive hash and all artifact paths are in
`tool/evidence/reader/android-corrected/provenance.json`.
The build log is in the same directory as `build.txt`.

## Fixture and device boundaries

The test used a fresh own binding for host `local`, device `emulator-5554`.
All app launches, input, settings, and saved screenshots used the exact
device-bound `agent-device` command returned by T3. T3 `device_screenshot`
also inspected the device. ADB was limited to installation, readback, logs,
process identification, and reverse-forward operations. A reverse forward
routes a device port to the matching host port.

Ports 7364 and 7365 were free before setup. Only this checkout's core-only
Jellyfin and unchanged HTTP observer listened, on `127.0.0.1`.
Synthetic accounts and credentials remained private under ignored `.cache`.
No production account, public listener, borrowed runtime, or external book
server was used. The observer forwarded real responses without changing
format metadata, bodies, or response headers.

The existing fixture scripts generated a two-chapter EPUB with internal links,
local PNG/JPEG squares, and a licensed Source Serif 4 font. The original hash
matched the previous attempt's original hash. The downloaded bytes matched
this original exactly. Filtered actual catalog evidence is in
`android-corrected-catalog.json`. The account was not an administrator.

## Observed journey

All screenshot paths below are relative to `images/android-corrected/`.
Screenshots were captured as each case became available, not reconstructed.

| Case | Actual observation | Screenshots |
| --- | --- | --- |
| Sign-in, library, download | Ordinary sign-in and Synthetic public selection succeeded. Ebooks showed Synthetic Work. Download completed with 135959 bytes and one file. The real Download response was HTTP 200. | `01-downloaded-epub.png` |
| First readable chapter | Read displayed The quiet harbour with readable paragraphs and both local image squares. No format refusal appeared. | `02-readable-first-chapter.png` |
| Contents | Contents listed both chapters. Selecting The lantern room displayed that chapter's heading and distinct paragraph. | `03-contents.png`, `04-contents-destination.png` |
| Search | Submitting `starfish` produced a result. Selecting it displayed the paragraph containing that word in The lantern room. | `05-search-result.png`, `06-search-destination.png` |
| Reading bookmark | Bookmark this place created a saved reading place after search navigation. The bookmark list showed it. Restoring it after following the return link reached The lantern room again. | `07-reading-bookmark.png`, `12-bookmark-restored.png` |
| Text size and night theme | One Larger text action visibly increased text and reduced the text fitting on the page. Night reading theme produced a dark page with light text. Preservation was not reliable; see limits below. | `08-larger-text.png`, `09-night-theme.png` |
| Next, previous, internal link | Next displayed later numbered paragraphs. Previous returned to the chapter opening. Return to the quiet harbour displayed the first chapter and its images. | `10-next-page.png`, `11-internal-link-destination.png` |
| Reopen at the saved chapter opening | Back then Read reopened The lantern room. This only proves restoration at that opening, not later-page restoration. | `13-reopened-reader.png` |
| Android larger text and process restart | Android text size changed from multiplier 1.0 to 1.35. After process relaunch, normal Ebooks and Read still worked. Text was larger and reader controls remained visible. | `14-large-text-after-restart.png` |
| Server-unavailable restart | After both own servers stopped, relaunch displayed Cannot reach Jellyfin. Saved books are still available. The cached book still opened locally at The lantern room. The saved bookmark remained listed. | `15-server-unavailable-after-restart.png`, `16-reader-without-server-after-restart.png`, `17-bookmark-after-restart.png` |
| Later-page restoration failure | Next displayed Harbour passage 5 and later paragraphs. Back then Read instead displayed the chapter opening. A repeated attempt established a saved later-page location before reopening. | `18-later-page-before-reopen.png`, `19-reopen-loses-later-page.png`, `20-later-page-confirmation.png` |
| Late confirmation capture | The second reopen's settled text snapshot showed the chapter opening. The later screenshot unexpectedly showed Book details instead of the reader. This screenshot is not evidence of a readable resumed page. | `21-details-after-confirmation.png` |
| Cleanup | The own download was explicitly removed. Sign out returned empty input fields and disabled account-only destinations. | `22-cleaned-signed-out.png` |

## New blocker: later-page restoration

Ticket `t8-jj2s` records this observed failure. A CFI is an EPUB location string.
After Next, app-private preference readback contained
`epubcfi(/6/4!/4/16/1:91)` in `OEBPS/Text/two.xhtml`.
Its quote began `bookmark could keep this place while the room grew dark.Harbour passage 5.`
This proves a later-page location reached persistent storage before the
second reopen. A missing write alone does not explain this attempt.

After Back and Read, the settled device snapshot again showed The lantern room
heading and opening paragraphs. The next preference readback contained
`epubcfi(/6/4!/4/2[note]/1:0)` and a quote beginning `The lantern room`.
The saved location had changed to the chapter opening.
`tool/evidence/reader/android-corrected/location-readback.json` records only
the relevant locations, stored font size, and bookmark count.
Raw preferences stayed private. This fixture contains no table.

The first screenshot pair directly shows the loss. The repeat distinguishes
the saved location from the restored display. However, the final screenshot
at 18:08:45 showed Book details without a corresponding planned Back action
between the successful Read snapshot and that capture. The exact cause of
this unexpected return was not established. Do not treat that image as a
second successful reader capture.

Timestamped Chromium logs also reported renderer-process termination with
code `-1` at 18:05:41, 18:07:49, and 18:08:18 UTC. The first two were near
intentional reader exits; the last preceded the unexpected details capture.
These lines do not establish whether viewport disposal, navigation, or a
renderer failure caused each event. No Flutter unhandled exception or Java
fatal-exception line matched the retained filter. The log is
`tool/evidence/reader/android-corrected/filtered-runtime.log.txt`.
Its Android timestamps use local EST, five hours behind UTC.

No application instrumentation or correction ran. The failure is narrowed
to restoration/display after a valid later-page record existed. The precise
state-restoration or layout cause still needs investigation.

## Route observations

The own `tcp:7365` reverse forward existed before first launch at 17:50:02.
It existed before Download and before Read. Before the online relaunch at
17:59:43, the application process ID was 9143. After relaunch, at 18:00:10,
the process ID was 11538 and the same route still existed.
Real catalog requests succeeded after this relaunch.

Before the server-unavailable relaunch at 18:02:27, the process ID was 11538.
After it, at 18:02:41, the process ID was 12201 and the same route existed.
Both host listeners were already stopped. No route repair occurred during
either relaunch. This did not reproduce the earlier missing-route failure.
It does not prove stability beyond these two relaunches or explain that
earlier failure. Ticket `td-7yxu` remains open.

## Runtime limits

- The local PNG and JPEG visibly rendered. Their exact byte identity was established through whole-EPUB comparison, not pixel decoding analysis.
- The chapter used serif text and contained the publication font. Runtime font identity was not inspected, so exact publication-font application is not accepted.
- Immediate larger text worked, but text became smaller after chapter navigation/bookmark restoration while the stored font size remained 22. Appearance preservation needs the existing R4 owner's retest. This report does not create a duplicate correction for R4.
- The reader's initial Bookmark this place control was disabled. It became enabled after search navigation. The duration and cause were not isolated.
- Server-unavailable reading and restart worked with the downloaded file. Wi-Fi and other radios stayed unchanged. This was not an airplane-mode or complete network-loss test.
- Native WebView request denial, navigation interception, permission denial, adversarial EPUB behavior, and TalkBack were not tested. Source tests and Permissions-Policy warnings do not prove those protections.
- R1 through R4 corrections were not part of this build. Later corrected packages, table locations, exact later-page process-death resume, and long-running stability remain unaccepted.

No host suite, coverage, mutation job, child, PR, product approval, or ticket
closure ran. The only runtime device error was
`Error (COMMAND_FAILED): Field focus was refused` while entering the server.
Its hint said `Retry with --debug and inspect diagnostics log for details.`
The diagnostics and a fresh snapshot were read. One retry with `--debug`
succeeded in the same binding. Diagnostic ID: `mvzk1lq1-aeff3c8a`.
No replacement binding or failed second retry followed.
Password entry used stdin without `--record-as`; output remained private.

## Cleanup and public evidence

The explicit Remove download confirmation removed only this attempt's edition.
At 18:12:11, an app-private file listing found no files beneath
`files/bookfin-media`. Sign out left empty fields. No shared app-data reset
or preference deletion occurred. Synthetic reading records remain scoped to
the signed-out synthetic account.

Android text size was restored to its original `large` category, multiplier
1.0, and read back. No TalkBack, radio, permission, credential-lock, or other
device setting changed. Jellyfin PID 4913 accepted authenticated shutdown
and exited zero. Observer PID 7597 received SIGTERM and exited 143.
Both loopback ports had no listener. Only the owned `tcp:7365` route was
removed; the final route list was empty. The own Gradle daemon was stopped.
The T3 binding was released with `shutdown: false`; the emulator stayed booted.
The exact corrected APK remained installed and matched final readback.

All 22 screenshots were visually audited. They contain only synthetic book
content, app controls, or empty sign-in fields. Public text contains filtered
catalog data, request paths without query strings, hashes, and bounded logs.
Generated passwords and account tokens were checked against public files.
Screenshot hashes are in
`tool/evidence/reader/android-corrected/screenshots.sha256`.
Private runtime, credentials, APKs, raw preferences, and raw logs remain ignored.
