# Integrated Android EPUB acceptance: visible-page restoration still fails

Date: November 2, 2026. Times use UTC, except Android logcat and the device
status bar, which use EST, five hours behind UTC.
Source: `f8868495509d9100146c3cc24835fada98ebaaf3`.
Primary blocker: `t8-jj2s`, still in progress. No production changes ran.

This is a new build and Android acceptance run of the integrated source,
including reviewed R1–R4, storage corrections, and metadata admission.
It does not reuse an earlier candidate APK or accept those corrections from
earlier screenshots. The parent reported 353 passing Flutter tests and clean
analysis before this run; this agent did not repeat that host suite.

## Artifact identity

An APK is an Android installation file. SHA-256 identifies its exact bytes.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Fresh normal ARM64 debug APK | 100150407 | `4e7350789b0df08d6d23c05fdee8ba9340872e47092660cfe0fd0a7d97975bbc` |
| Installed readback before launch | 100150407 | `4e7350789b0df08d6d23c05fdee8ba9340872e47092660cfe0fd0a7d97975bbc` |
| Installed readback after cleanup | 100150407 | `4e7350789b0df08d6d23c05fdee8ba9340872e47092660cfe0fd0a7d97975bbc` |
| Original synthetic EPUB | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |
| Downloaded EPUB readback | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |

The build used `nix develop --profile .cache/dev-shell --command bash -c
'export PUB_CACHE=/Users/alexispurslane/Development/bookfin/.cache/pub;
export GRADLE_USER_HOME="$PWD/.cache/gradle"; bash tool/bookfin build-android'`.
It used normal `lib/main.dart`, without a test entry, private application API,
or extra diagnostic application code. Gradle completed in 238.4 seconds.
The shared dependency cache was read; this checkout owned its Gradle cache.
The exact command, source archive hash, logs, and artifact paths are in
`tool/evidence/reader/android-integrated/provenance.json` and `build.txt`.
The source archive SHA-256 is
`641a6513cd0d827313ec2e7407c63ae152a7085f4eaa4e91b2038b7be61fd4b9`.

## Fixture and device

The run used an exclusive own T3 binding for host `local`, device
`emulator-5554`. All launches, relaunches, taps, entry, navigation, screenshots,
and app closure used its returned bound `agent-device` command.
T3 `device_screenshot` inspected the reader. No device command failed.
ADB only installed, read files and settings, collected logs and process IDs,
and managed owned port routes. No ADB UI control or binding reset ran.

Both ports were free before startup. Own core-only Jellyfin 12.4.0 PID 71227
listened on `127.0.0.1:7364`; the existing unchanged observer PID 71928 used
`127.0.0.1:7365`. The observer forwarded real responses without changing
metadata or book bytes. The own reverse route connected Android port 7365
to host port 7365. No public server or production account was used.

The ordinary synthetic user was not an administrator. Its actual Book response
omitted both `Container` and `MediaSources`, even when requested. See
`tool/evidence/reader/android-integrated/catalog.json`. The normal app signed
in, selected Synthetic public, displayed Synthetic Work under Ebooks,
downloaded 135959 bytes, and opened readable text with PNG and JPEG squares.
The observer recorded HTTP 200 for the real Download request.

## Observed cases

Screenshot paths are relative to `images/android-integrated/`. A saved location
means the EPUB location string and quote read from actual Android preferences,
not a location inferred from the page number. A CFI is an EPUB location string.

| Case | Observed result | Screenshots |
| --- | --- | --- |
| Sign-in, library, download, Read | Successful ordinary-user journey through real Jellyfin. Readable first chapter and both local image squares. | `01-ordinary-library.png`, `02-downloaded.png`, `03-readable-first-chapter.png` |
| Later page, 20 CSS-pixel text | Two Next actions displayed `Harbour passage 5.` at the top. Saved CFI was `epubcfi(/6/2!/4/26/1:0)` with the matching passage-5 quote. | `04-later-page-before-reopen.png` |
| Back then Read, same process | Failed. The visible page instead started `Visit the lantern room`, followed by passage 1. Readback changed to `epubcfi(/6/2!/4/18/1:0)` with a passage-1 quote. It did not return to the chapter heading in this run; it returned to the previous page. | `05-after-reopen.png` |
| Bookmark restore, same process | Saved a passage-5 bookmark, moved to passage 10, and restored the bookmark. The visible top was passage 5 again. The bookmark and resume readback both retained the passage-5 CFI. | `06-bookmark-restored.png` |
| Process restart with server unavailable | Stopped both own listeners first. Process ID changed from 1163 to 4280. Saved library and downloaded EPUB remained available. No reverse-route repair occurred. | `07-server-unavailable-after-restart.png` |
| Read after that restart | Failed. Before restart, the saved resume and bookmark were both passage 5. Read instead displayed `Visit the lantern room` and passage 1. Readback became `epubcfi(/6/2!/4/16/2/1:0)`, quote beginning `Visit the lantern room`. | `08-restart-loses-later-page.png` |
| Bookmark after restart | Passed for visible text. The retained bookmark restored passage 5. Its location stayed separate from the overwritten resume. | `09-bookmark-after-restart.png` |
| Larger text and night override | One Larger text action saved 22, and Night reading theme visibly darkened the page. Back then Read retained 22 and the same visible-start text, but returned to cream. Theme lifetime needs the parent decision in `t8-j809`. | `10-larger-night.png`, `11-larger-reopen-cream.png` |
| Second chapter, 22 CSS-pixel text | Contents opened The lantern room. Two Next actions reached a page starting `could keep this place while the room grew dark.` before passage 6. Saved CFI `epubcfi(/6/4!/4/18/1:100)` and the actual visible-start text survived Back then Read. This case passed; it does not erase the 20-pixel failures. | `12-second-chapter-before-reopen.png`, `13-second-chapter-after-reopen.png` |
| Bounded diagnostic repeat, 20 CSS-pixel text | Returned to 20, selected the first chapter, and moved twice to passage 5. Saved the same passage-5 CFI as the first failure. Back then Read again displayed the earlier link/passage-1 page, and saved passage 1. | `14-default-size-before-diagnostic-reopen.png`, `15-default-size-diagnostic-reopen.png` |
| Cleanup | Removed only this run's download through its explicit confirmation. Signed out to empty fields. | `16-cleaned-signed-out.png` |

The page-number labels are not reliable evidence of visible position here.
For example, screenshot 04 says Page 2 of 5 and screenshot 06 says Page 3 of 5,
although both start with passage 5 at the same text size and viewport geometry.
Screenshot 12 says Page 2 of 6 and screenshot 13 says Page 3 of 6 while their
visible text and saved CFI agree. These are related layout/progress symptoms,
recorded with `t8-jj2s`, not proof that bookmark text restoration failed.

## Bounded causal evidence

`tool/evidence/reader/android-integrated/location-readback.json` contains only
this run's edition locations, text sizes, and bookmark anchors. Other accounts'
records and raw preferences were excluded. Both the original and processed
publication hashes stayed unchanged. The fixture contains no table.
The failure therefore persists without a source-identity change, a table
normalization case, a missing later-page write, or a live Jellyfin request.

After retaining the primary failure screenshots, the agent used an owned ADB
port forward and the WebView's existing diagnostic socket for read-only DOM
sampling. DOM means the browser's document tree. No navigator method, private
application state, JavaScript handler, publication input, style, event listener,
or production file was changed. Sampling read iframe rectangles, computed
styles, text rectangles, and the browser's font-load status every 250 ms for
40 samples. It did not pause the renderer. The earlier failures occurred
before diagnostic attachment. The larger-text control case and repeated
default-size failure were both sampled. Raw bounded samples and deduplicated
changes are retained beside the location readback.

Geometry uses CSS pixels relative to the reading viewport, not screenshot
pixels. The reading viewport was 412 pixels wide and 667 pixels high.
An iframe is the browser document that contains the admitted book chapter.
Its horizontal position is measured relative to the reading viewport's left
edge; a negative position places earlier columns outside that viewport.

The default-size repeat observed these stages:

| UTC time | Font status | Iframe width | Iframe horizontal position | Observation |
| --- | --- | ---: | ---: | --- |
| 20:13:21.791, before exit | loaded | 2060 | -823.62 | Passage 5 begins at chapter-coordinate 841, so it is visible about 17 pixels from the viewport's left edge. Saved CFI points to passage 5. |
| 20:13:51.453, reopening | no iframe yet | — | — | New reading document starts. |
| 20:13:54.493 | loading | 1236 | -824 | Passage 5 again begins at chapter-coordinate 841, initially putting it in the visible column. Computed text size is already 20 pixels. |
| 20:13:54.952 | loading | 2472 | -824 | Chapter text rectangles and column extent change while font loading continues. |
| 20:13:55.455 | loaded | 2472 | -824 | The first observed font-loading phase completes. |
| 20:13:55.969 | loading | 1236 | -411.81 | A second observed loading/layout phase uses the earlier horizontal position. This is not evidence of a second application appearance call. |
| 20:13:56.438 | loaded | 2060 | -411.81 | The visible column starts with the internal link and passage 1. The final preference readback contains passage 1 instead of passage 5. |

The larger-text control case also changed from `loading` to `loaded` and from
iframe width 2884 to 2472, but retained horizontal position -824 and the same
saved CFI. Font reflow alone is therefore not a complete causal explanation.
The browser's `loaded` status does not identify the exact font face applied.
The computed body font family was `BookSerif, serif`; exact font selection
remains unaccepted.

Source order, not an instrumented method-call trace, shows appearance
configuration before the requested initial location. The following exact
excerpt is from `packages/flutter_epub_viewer/assets/reader.js`:

```javascript
    await configure(settings.fontSize, settings.night, false);
...
    await rendition.display(initial ? initial.cfi : void 0);
```

where

- `configure` applies the requested reading styles and text size.
- `settings` holds the configuration passed when opening this viewport.
- `settings.fontSize` is the requested text size in CSS pixels; this repeat used 20.
- `settings.night` selects the dark reading colors; this repeat used false.
- `false` disables the configuration function's own restore operation at initial opening.
- `rendition` is the EPUB engine object that lays out and navigates the chapter.
- `display` requests the page containing the supplied EPUB location string.
- `initial` is the saved location after its document and quote checks succeed.
- `initial.cfi` is that saved EPUB location string.
- `void 0` supplies no saved location when `initial` is absent.

No runtime trace of `readerLocation`, `configure`, or `display` calls was added.
The evidence narrows the failure to startup restoration and subsequent
layout/location handling, but does not prove which callback replaces the
correct initial column. The parent should reproduce delayed font/layout
changes with the actual iframe engine at 20 pixels and assert both final
visible-start text and the retained saved anchor. A unit test that only accepts
a location event or verifies a store write will not cover the observed failure.

Android logs show renderer termination code -1 at intentional reader exits,
including 20:13:23 before the diagnostic reopen. The new reader then reached
the requested column before moving to the earlier column. The retained logs
contain no further renderer termination during that sampled move. Do not
attribute this failure to renderer termination from those exit messages.
No matching Flutter unhandled exception or Java fatal-exception line appeared.
`filtered-runtime.log.txt` retains the bounded renderer and console messages.

## Limits and cleanup

The server-unavailable test stopped both loopback listeners. Wi-Fi and other
radios remained unchanged. Android airplane mode stayed 0, and Android font
scale stayed 1.0. This was not airplane mode, complete network loss, an OS
large-text acceptance run, or a changed-media-source test.

Core restoration failed, so native request/navigation/permission denial,
adversarial EPUBs, SVG display, exact font identity, TalkBack, long-running
stability, and physical-device behavior were not accepted. Accessibility-tree
text and labeled controls were available to the device tool, but that does
not establish screen-reader usability. Search and arbitrary fragments were
not rerun on this named build. No earlier screenshots substitute for them.

Jellyfin accepted authenticated shutdown and exited zero. The observer exited
143 after SIGTERM. Neither own loopback port had a listener afterward.
Only the own reverse route and two diagnostic forward allocations were
removed. Existing unrelated forwards were preserved. The raw final download
file listing was empty. Sign-out removed the active synthetic account; its
scoped records were preserved rather than deleting unrelated app data.
The own log collector stopped, and the own Gradle cache reported one daemon
stopped. The final installed APK matched its original build hash.
The bound app session closed and T3 released the device with `shutdown: false`.

All 16 screenshots were visually audited. They contain synthetic content or
empty sign-in fields. Public evidence was checked against this fixture's
generated passwords and tokens. Credentials, raw preferences, server state,
APKs, raw logs, and diagnostic forward details remain ignored under `.cache`.
No children, PR, coverage, mutation run, global SDK change, production edit,
ticket closure, or reader approval occurred. The parent owns correction,
regression tests, integration, and final acceptance.
