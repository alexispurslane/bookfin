# Named-candidate Android saved-page observation

Date: November 2, 2026. Source: `9e62d821970aad67f63a5f45d429ae5f60839f3e`.
Base: `5d3239315038d88e6f590efd7cbe885093a2a3fb`. The checkout fast-forwarded from that base.
This report covers only that earlier candidate. The later integrated revision has a separate report, `android-saved-page-final.md`.

The user renewed device authorization after the previous worker stopped. This worker obtained its own binding for host `local`, device `emulator-5554`.
No device command failed. No binding reset or ADB input fallback ran.

## Exact artifact

An APK is an Android installation file. SHA-256 identifies its exact bytes.
The reused normal ARM64 debug APK contains 100150955 bytes. Its SHA-256 is
`f5fd6238fc9b34b30836ab079b9f645e3925d8ed5fd93a5d878ddc198fe15d2a`.
Both installed readbacks match that size and hash. The package is `dev.bookfin.bookfin`.
The recorded normal entry is `lib/main.dart`. There is no test entry or extra application instrumentation.

The recorded build-input tree is `f38a0ea40e671b352e5d77c5a240dc609417791a`.
Its runtime source paths match the named candidate. Their patch from the base has SHA-256
`94ea4d87fd293dc88192469626ad6069fd583e811aba38fdec77686bfccabc31`.
All four packaged reader files match both the recorded hashes and the candidate files.
`tool/evidence/reader/android-saved-page/provenance.json` retains these checks.
The worker did not rebuild or rerun the host suite for this earlier candidate.

## Fixture and observation

The worker started its own core-only real Jellyfin 12.4.0 and unchanged HTTP observer.
Both listeners used free loopback ports, 7364 and 7365. No private account or public server was used.
The app signed in as the synthetic ordinary user, selected Synthetic public, downloaded the book, and opened Read.
The original and downloaded EPUB each contain 135959 bytes and have SHA-256
`6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96`.
No response metadata or EPUB bytes were forged. The fixture has no table.

A CFI is an EPUB document-and-character address. CSS pixels measure the reader layout, not Android screenshot pixels.
A preserved address means that actual Android preferences retain the address, and the requested text stays visible.
After a layout-size change, the containing page can start before the requested character.
That is not an exact first-line guarantee across different text sizes.

Screenshot names below are in `images/android-saved-page/`.

| Priority | Result on this candidate | Evidence |
| --- | --- | --- |
| Default 20 CSS pixels, first chapter | Pass. Two Next actions reach passage 5. Preferences save `epubcfi(/6/2!/4/26/1:0)`. | 03, 04; filtered location readback |
| Back then Read | Pass. Passage 5 remains the first visible text. The same CFI and quote survive. The label remains Page 3 of 5. | 04, 05, 06 |
| Process restart, server unavailable | Pass. Both listeners stop. The app process changes from 17470 to 19046. Read still starts at passage 5, with the same persisted CFI and Page 3 of 5. | 07, 08, 09 |
| Intentional Next and Previous | Pass. Next advances to the column containing the tail of passage 9 and passage 10, with a new CFI and Page 4 of 5. Previous returns to passage 5, its original CFI, and Page 3 of 5. | 10, 11 |
| Bookmark restore | Pass. A passage-5 bookmark survives a move to the next page. Selecting it restores passage 5 and its original CFI. | 12; bookmark and resume readback |
| Appearance and text-size changes | Pass for address visibility. At 22 pixels, passage 5 remains visible within Page 3 of 6. Returning to 20 pixels restores it to the top of Page 3 of 5. Night colors preserve the address. | 13, 14, 15 |
| Reader viewport resize | Pass for address visibility. Hiding controls changes the viewport from 667 to 839 CSS pixels high. Passage 5 remains visible lower on its containing page. Showing controls restores passage 5 to the top, with the same CFI. | 16, 17; layout samples |
| Second-chapter control, 22 pixels | Pass. Before and after Back then Read, Page 3 of 6 starts with the tail of passage 5, then passage 6. The CFI remains `epubcfi(/6/4!/4/18/1:100)`. | 18, 19, 20 |

Readable screenshots were captured before diagnostic attachment. Read-only document-tree samples then checked browser font status and actual paragraph rectangles.
The Back/Read, process-restart, hidden-controls, and second-chapter reopen captures each include 40 samples over about ten seconds.
The settled samples report fonts loaded. The first-chapter address stays in the visible column, rather than only appearing in a transient opening frame.
Page labels track the observed columns for the named cases. This does not certify every label or exact font identity.

The server-unavailable case stopped both listeners. It did not change radios or enable airplane mode.
Android airplane mode remained 0. Android font scale remained 1.0.
Raw preferences stay private. Public readback contains only this fixture account's reading records.

## Review limits and cleanup

The parent reported two independent source blockers in this candidate: resize can remove an iframe during an unresolved render, and neighboring-chapter navigation can hide resource failures.
These happy-path device observations do not accept those cases, establish review approval, or approve integration.
The later source correction requires its own APK and observations.
Theme persistence remains separate unresolved ticket `t8-j809`. No new blocker was inferred from that known scope.
Native denial, TalkBack, adversarial publications, exact font identity, long-running stability, and physical devices were not tested.

Before the later revision, this run removed its download through the confirmation screen and signed out to empty fields.
It restored reader text size to 20 and cream colors. Its own observer exited 143, and Jellyfin exited zero after authenticated shutdown.
Its reverse route and diagnostic forwards were removed. Existing unrelated forward state remained untouched.
The binding stayed open solely for the user's explicit extension to the integrated revision. Final binding release is recorded in the later report.
No production files, children, PR, host-suite rerun, coverage, mutation run, global toolchain change, or ticket closure occurred.
