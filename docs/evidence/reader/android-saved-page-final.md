# Integrated Android saved-page priority checks

Date: November 2, 2026. Times in the evidence use UTC. The Android status bar uses EST, five hours behind UTC.
Tested source: `c279fd6d9fe6a792d04c8b6a15c519c4077aebde`.
Source tree: `0e65708efa5d34015af701fdb72ecb57d13dd85c`.

The parent explicitly extended this worker's device authorization to this exact integrated revision.
The checkout fast-forwarded to that revision without losing its earlier observations.
The source tree matches reviewed revision `5447da32`. The parent reported independent correctness/design review and green host checks for that revision.
This worker did not perform that review or rerun the host suite. The earlier `9e62d82` observations remain separate in `android-saved-page.md`.

The named Android priority checks pass on this fresh build. This is not release-wide acceptance, proof of every asynchronous error path, or ticket closure.

## Build and installed identity

An APK is an Android installation file. SHA-256 identifies its exact bytes.
All build commands ran through the pinned project Nix development shell. The machine had ten logical CPUs and 61 percent free memory.
The initial one-minute load average was 19.30. The build ran at lower scheduling priority, with the existing limit of two Gradle workers.
Only one heavy command ran at a time. No global SDK or toolchain change ran.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Fresh normal ARM64 debug APK | 100151015 | `e620a4eb5f61ead9a7e0e227f1c05189a74f0f9eaa624023ac36a4e4b90c6bd7` |
| Installed readback before opening | 100151015 | `e620a4eb5f61ead9a7e0e227f1c05189a74f0f9eaa624023ac36a4e4b90c6bd7` |
| Installed readback after cleanup | 100151015 | `e620a4eb5f61ead9a7e0e227f1c05189a74f0f9eaa624023ac36a4e4b90c6bd7` |
| Original synthetic EPUB | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |
| Fresh download readback from the final build | 135959 | `6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96` |

The package is `dev.bookfin.bookfin`. The normal entry is `lib/main.dart`, without a test entry or diagnostic application code.
The build completed in 235.2 seconds. It retained existing Java 8 target and deprecated/unchecked dependency warnings.
All four packaged reader files match the final source and `ASSETS.sha256`.
The packaged EPUB engine hash is `b49f65af43b0c7abb3f19964fb8c31fe0c993ec447774a34cd0cc82f04cc16be`.
The earlier candidate APK was not reused for this final-source observation.

Exact build commands, source archive hash, all packaged file hashes, and artifact paths are in
`tool/evidence/reader/android-saved-page-final/provenance.json` and `commands.txt`.
The full bounded build output is `build.txt`. No production source changed during acceptance.

## Ordinary-user journey and saved addresses

The worker retained exclusive ownership of host `local`, device `emulator-5554`.
It used its own freshly authorized T3 binding throughout both named-source runs.
All app launches, inputs, navigation, screenshots, and app closure used the returned bound `agent-device` command.
T3 `device_screenshot` inspected the reader. Every input used an immediately refreshed snapshot reference.
No input, launch, navigation, or screenshot command failed. No interaction retry or ADB input fallback ran.
ADB only installed, read files/settings/process IDs, and managed explicitly owned routes.

The same owned, core-only real Jellyfin 12.4.0 restarted on `127.0.0.1:7364` with PID 41984.
The unchanged HTTP observer used `127.0.0.1:7365` with PID 42234.
Both ports were free before restart. The observer forwarded real responses without replacing metadata or book bytes.
The app signed in again as the synthetic ordinary user. It reused its selected Synthetic public library, downloaded the EPUB again, and opened Read.
No private production account, public server, forged response, test entry, or modified publication was used.

A CFI is an EPUB document-and-character address. CSS pixels measure the reader layout, not Android screenshot pixels.
Saved address means an address read from actual Android preferences, rather than inferred from a page label.
Address visibility after a text-size change means the requested character stays on the containing page.
It does not mean that a different text size must put that character on the first line.

The saved bookmark was created by this worker on the earlier candidate and retained across installation of the final APK.
The final reader first resumed the second chapter at 20 pixels, then restored that bookmark into the first chapter.
Next and Previous established fresh final-build navigation before the main Back/Read check.
This exercises bookmark restoration across chapters and an app update. It does not claim a second bookmark-creation check on the final build.

Screenshot numbers below refer to `images/android-saved-page-final/`.

| Priority | Final-source result | Evidence |
| --- | --- | --- |
| Sign-in, library, fresh download, Read | Pass. The ordinary-user app journey succeeds with the original 135959-byte EPUB. | 01, 02; HTTP events and downloaded readback |
| Bookmark restoration | Pass. The final reader restores the first chapter's passage 5 from the second chapter. Bookmark and resume addresses agree. | 03; filtered location readback |
| Intentional Next and Previous | Pass. Next shows the tail of passage 9 followed by passage 10, with Page 4 of 5 and a new address. Previous restores passage 5 at Page 3 of 5. | 04, 05 |
| Default 20-pixel Back then Read | Pass. Before and after, the actual first visible text is Harbour passage 5. The address remains `epubcfi(/6/2!/4/26/1:0)`, with the same saved quote and Page 3 of 5. | 05, 06, 07 |
| Process restart with server unavailable | Pass. Both listeners stop before restart. The process changes from 22498 to 23878. Read still starts at passage 5, with the same saved address and Page 3 of 5. | 08, 09, 10 |
| Text-size change and return | Pass for address visibility. At 22 pixels, passage 5 remains visible within Page 3 of 6. Returning to 20 pixels puts passage 5 at the top of Page 3 of 5. The saved address never changes. | 11, 12; layout and preference readbacks |
| Second-chapter control, 22 pixels | Pass. Contents selects The lantern room. Two Next actions reach Page 3 of 6. Before and after Back/Read, the same page starts with the tail of passage 5, then passage 6. The saved address stays `epubcfi(/6/4!/4/18/1:100)`. | 13, 14, 15 |
| Cleanup | Pass. The download is removed through confirmation. The account signs out to empty fields. | 16; cleanup record |

Readable screenshots precede each diagnostic attachment. The worker then used an owned ADB forward to the existing WebView diagnostic socket for read-only document-tree samples.
No publication, style, event listener, navigation method, private application state, or bridge callback was changed.
The sampler source is retained in the evidence directory.

The Back/Read, process-restart, and second-chapter reopen observations each retain 40 samples across about ten seconds.
All those samples report browser fonts loaded. The reader viewport is 412 by 667 CSS pixels.
The visible-column rectangles remain stable, with the requested text visible.
The settled screenshots follow those samples, not only the first opening frame. Preference readback brackets each reopen and agrees with the later text-size checks.
The second-chapter command briefly returned “Laying out the book” before the next screenshot showed settled readable text.
That transient snapshot is not the basis of the pass result.
Page labels match the actual visible columns in these named cases. This is not an exhaustive page-label check or proof of exact font-face selection.

The server-unavailable case stops both own listeners. Radios remain unchanged, and airplane mode stays 0.
This is not airplane mode or complete network-loss acceptance. Android font scale remains 1.0.

## Cleanup and remaining limits

Jellyfin accepted authenticated shutdown and exited zero. The own observer received SIGTERM and exited 143.
Neither port retained a listener. Both explicitly allocated diagnostic forwards and the own port-7365 reverse route were removed.
After app closure and T3 release, the forward listing matched the original unrelated forward.
No unrelated route, app data, download, or account was erased.

The worker removed its own download and signed out. Account-scoped reading records remain, rather than clearing shared application data.
Reader text size returns to 20 pixels, and cream colors remain selected. No Android setting changed.
The own Gradle cache reports one daemon stopped. No own build or fixture command remains running.
The bound app session closed successfully at 21:58:53 UTC. T3 release returned success with `shutdown: false`.
Its action log then records two redundant close attempts at 21:59:10 UTC, both with `SESSION_NOT_FOUND`.
Those cleanup-only errors follow the successful close. No further UI action ran. They do not replace or invalidate the earlier completed observations.

All 16 final-source screenshots were visually audited. They contain only synthetic content or empty sign-in fields.
Public evidence was scanned against this fixture's generated passwords and tokens.
The owned fixture credentials and server data were removed after the public audit.
Raw preferences, APKs, and raw private logs remain ignored under `.cache`.
Only this fixture account's reading records appear in public preference readback.

Theme persistence remains separate unresolved ticket `t8-j809`.
Night colors and hide/show-controls resizing were observed on `9e62d82`, not repeated or certified on this final source.
Native request/permission denial, TalkBack, adversarial publications, SVG, exact font identity, long-running stability, physical devices, and failure-injection error paths remain outside this run.
No production edits, children, PR, host-suite rerun, coverage, mutation testing, or ticket closure occurred.
The parent owns integration of this evidence and the final decision to close `t8-jj2s`.
