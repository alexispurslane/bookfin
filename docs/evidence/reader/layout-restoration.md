# Visible-page restoration candidate for t8-jj2s

Date: November 2, 2026. Base: `5d3239315038d88e6f590efd7cbe885093a2a3fb`.
This is an implementation candidate, not Android acceptance. The parent owns
independent review, integration, device acceptance, and ticket closure.

## Reproduction before production changes

A CFI is an EPUB document-and-character address. CSS pixels measure the reader's
layout, rather than the Android screen's physical pixels.

The regression runs the bundled EPUB engine and reader bridge in headless
Chromium 138.0.7180.0. It uses actual iframe layout, column geometry, XML import,
stylesheet loading, image loading, font loading, location mapping, and bridge
events. It does not replace the renderer or its range measurements.
The test receiver records the production `readerLocation` payload at the
native-channel boundary. A saved event here is that payload, not an Android
preferences readback or proof of a durable native write.

The chapter repeats the synthetic text and element order from
`tool/acceptance/reader_fixture.py`. It uses the existing local PNG and Source
Serif 4 font. Both image elements use the PNG in this host fixture. It is not a
substitute for the original EPUB's PNG/JPEG Android acceptance.

The server holds the stylesheet response and then the font response behind
explicit test-controlled promises. No elapsed-time delay decides readiness.
The viewport changes from 412 by 671 to 412 by 667 CSS pixels. Those heights
match the supplied Android layout samples. A final real location measurement
checks the saved bridge event against the final rendered text.

Before changing production, this sequence lost the requested passage and
changed its saved anchor. The original render trace contains:

| Step | Observed original engine result |
| --- | --- |
| Requested restore | `epubcfi(/6/2!/4/26/1:0)`, Harbour passage 5 |
| Initial location report | `epubcfi(/6/2!/4/18/1:89)`, a character in passage 1 |
| Viewport resize | `onResized` requested that already-replaced passage-1 address |
| Final rendered result | Passage 5 was outside the visible column, at horizontal position 841 CSS pixels |
| Final bridge event | `epubcfi(/6/2!/4/2/1:0)`, The quiet harbour heading |

`tool/evidence/reader/layout-restoration/red-layout.txt` retains that failing run.
`final-test-against-baseline.txt` reruns the final regression with both original
bundled assets extracted from `5d32393`. It fails on the visible passage, not a
missing symbol, test syntax, or a mocked callback. Its recorded test exit is 1.

This identifies a real ownership defect: a layout-derived page boundary could
replace the requested reading address, then cause the next resize to restore
that wrong address. The supplied Android samples are consistent with this
defect. This agent did not trace the exact callbacks on Android, so that causal
link still needs device verification.

## One reading-address owner

`Rendition.location.start.cfi` remains the only current reading-address owner.
There is no additional durable position store or parallel transient anchor.
The reading address is the requested former visible-start character. After a
layout change, its containing page can begin before that character. That page
boundary is not a new user navigation request.

The core assignment is:

```js
				const anchor = cfi === undefined && this.location && this.location.start.index === located.start.index ?
					this.location.start.cfi : cfi;
				if (anchor) located.start.cfi = anchor;
				this.location = located;
```

where

- `this` is the active `Rendition`, the engine object that owns reading navigation.
- `cfi` is a requested CFI string, `null` for intentional page navigation, or `undefined` for a passive location report.
- `anchor` is the CFI that the completed report retains. A missing value permits the new measured visible-start CFI.
- `located` is the report measured from the actual iframe, including its current source-document page counts.
- `this.location` is the completed reading report used by subsequent restoration and bridge events.
- `start.cfi` is that report's reading address.
- `start.index` is the zero-based reading-order document number.

Explicit display supplies the verified CFI. Next and Previous request a newly
measured visible-start CFI. Passive location reports retain the current reading
address within the same document. Chapter metadata and page counts still come
from the newly measured layout. Bookmark restore uses the same display path.

Navigation remains in the existing rendition queue until the animation-frame
measurement completes. A resize reads the current reading address when its
queued display runs, rather than capturing an older address before it runs.
The existing reader command queue also owns appearance capture, so an
appearance command after Next cannot restore the address from before Next.

New iframes complete the existing content hooks and local stylesheet, image,
and font loading before their final column measurement. Existing iframes
complete resource readiness and reflow before display restoration. Image bounds
use the viewport layout height, not the unformatted document's height.
There is no new sleep or second corrective navigation. A resource failure
rejects display and reaches the existing reader failure event. It cannot leave
the display promise pending forever.

The rendition's on-demand `checkInvariants()` checks both report boundaries:
their CFIs belong to their stated reading-order documents, and their one-based
page numbers are within their source-document page counts. Tests call it after
navigation settles. It does not run automatically in release or recover from
an invariant failure.

An additional real-layout test moves the view by 0.4 CSS pixels. Before the
correction, the same passage changed from page 3 to page 2 because the column
calculation rounded down. `red-page-label.txt` records `2 !== 3`. Page numbers
now use the nearest aligned column. A separate failing test showed a queued
appearance command restoring the old address after Next. Its evidence is
`red-queued-appearance.txt`.

Canonical passive XML import, the passive resource sandbox, source verification,
processed identity, record compatibility, and theme lifetime are unchanged.
Theme ticket `t8-j809` remains separate.

## Verification

All commands use the project Nix development shell. The npm lockfile and
existing asset build remain unchanged. `UPSTREAM.json` records the patch.
`ASSETS.sha256` records the rebuilt JavaScript hashes. `provenance.json` records
the exact runtime patch, build input tree, browser, and normal APK identity.

| Check | Result |
| --- | --- |
| Actual-layout startup and height change | Final visible-start text is Harbour passage 5, at horizontal position 17 and vertical position 1 CSS pixels. Every saved event retains `epubcfi(/6/2!/4/26/1:0)`. Final page is 3 of 5. |
| Intentional Next and Previous | Next replaces the old address. Two subsequent height changes retain that new address. Previous returns to passage 5. Native character rectangles independently establish visibility. |
| Bookmark restoration | A page move followed by verified bookmark restoration returns to passage 5 and saves its CFI. |
| Appearance at 22 then 20 CSS pixels | The requested CFI survives both appearance changes. The final 20-pixel view returns to the same visible-start text. |
| Next followed immediately by appearance | The later appearance command retains the new reading address, not passage 5's old address. |
| Fractional column position | The same visible passage retains page 3 of 5. |
| Failed local stylesheet | Opening rejects with the real resource error and reports reader failure, without reporting a saved location. |
| JavaScript engine suite | 21 tests pass, including 6 actual-layout tests. |
| Focused Flutter reader suite | 43 tests pass. |
| Full Flutter suite and environment scripts | 353 Flutter tests pass. SDK link, platform compile, and native-tool checks pass. |
| Flutter analysis | No issues found. |
| Normal ARM64 debug APK | Build succeeds in 298.4 seconds. All four packaged runtime assets match the checked-in asset manifest. Not installed or accepted on Android. |

The APK contains 100150955 bytes. Its SHA-256 is
`f5fd6238fc9b34b30836ab079b9f645e3925d8ed5fd93a5d878ddc198fe15d2a`.
The build uses normal `lib/main.dart`, without diagnostic application code.
The build reports existing Java 8 target and deprecated/unchecked API warnings.
Those dependency warnings remain outside this ticket.

Host commands and bounded results are retained under
`tool/evidence/reader/layout-restoration/`. The actual-layout tests require a
local Chromium executable. Set `CHROME_BIN` outside the default macOS path.
The Node.js runner comes from Nix. The existing host Chromium installation is
identified in provenance. No global browser or toolchain installation ran.

Reproduce the engine checks with:

```sh
nix develop --profile .cache/dev-shell --command bash -c 'cd packages/flutter_epub_viewer/engine && npm ci --ignore-scripts --no-audit --no-fund && npm run build && npm run verify && npm test'
```

These tests prove real host layout, not Android WebView behavior, native
storage, offline process restart, font identity on Android, or physical-device
behavior. The 22-pixel host control uses the first chapter. It does not replace
the requested second-chapter Android control.

## Android stop and cleanup

This agent obtained its own T3 binding for host `local`, device
`emulator-5554`. The initially guessed package `com.example.bookfin` returned
`APP_NOT_INSTALLED`. The prescribed app lookup identified `dev.bookfin.bookfin`.
Opening that exact package and reading its sign-in snapshot succeeded.

The sign-in URL field then returned `COMMAND_FAILED: Field focus was refused`.
The prescribed single retry with diagnostics returned `COMMAND_FAILED: Ref @e5
belongs to an expired ref frame`. The failed retry did not dispatch input.
Device input stopped at that point, as required. No binding reset, alternate
session, ADB UI input, or other UI fallback ran. This was a command failure in
this attempt, not proof that Android or the app is unavailable.

The candidate normal APK was not installed or launched. No after-fix Android
passage screenshot, saved-anchor readback, Back/Read test, offline process
restart, bookmark test, or second-chapter 22-pixel control is claimed.
The parent must perform those cases in a separate authorized run.

Ports 7364 and 7365 were free before this agent started its own core-only
Jellyfin 12.4 fixture and unchanged observer. The fixture prepared the original
synthetic EPUB and ordinary synthetic accounts. No account signed in and no
download started. No production server or account was contacted.

Cleanup requested authenticated shutdown of the recognized fixture, which
exited zero. The own observer received SIGTERM and exited 143. Neither port
retained a listener. The own `tcp:7365` reverse route was removed. No diagnostic
forward was created. No OS setting changed. Initial readback was font scale
1.0 and airplane mode 0. T3 released the binding with `shutdown: false`.
The app was left at sign-in because the stop rule prevented further UI cleanup.
The ignored fixture runtime was removed after recording its public identity.
The checkout's own Gradle cache reported one daemon stopped.

No children, PR, coverage, mutation testing, ticket closure, theme persistence,
or production diagnostic instrumentation ran. The parent owns the remaining
Android acceptance and independent review.

## Follow-up review corrections

Review F1 reproduced removal of the loading iframe when resize ran before stylesheet release. Resize requests from both the public rendition interface and native viewport/orientation notifications now enter the rendition navigation queue. Dimension changes, view disposal and restoration complete as one queued operation, after active rendering. F2 reproduced successful completion of Next and Previous despite a failed destination stylesheet. Both navigation paths now propagate the resource rejection. Real-layout regressions cover blocked initial opening, an automatic resize during a neighboring-chapter load, and failed resources in both navigation directions. Red logs are review-resize-red.txt and review-neighbor-red.txt. Android evidence for the earlier candidate does not accept these follow-up changes.
