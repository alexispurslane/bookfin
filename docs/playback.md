# Downloaded audio playback

Ticket: boo-sthf. Base: `c13748198f0b7f73ad0ba1ec2b7ac84fbe989627`.

Android now plays a downloaded audio edition through its ordered local files. The production library opens the player from an edition's Listen action. A mini-player remains available in the library, Downloads, and book details. Listening is the existing third navigation destination, not a second navigation system. The full player uses the shared cream/sepia theme and bundled fonts. Its sheets use the application's reduced-motion-aware route transitions.

This ticket does not stream audio, acquire remote files during playback, implement an ebook reader, or implement history, bookmarks, Undo, conflict resolution, or full personal-record sync.

## Ownership and boundaries

| Module | Responsibility |
| --- | --- |
| `lib/playback/playback.dart` | Own the selected account, book, edition, source-relative position, playback state, speed, short jumps, and sleep timer. Serialize commands and durable writes. |
| `lib/playback/native.dart` | Decode local files with `just_audio`. Route Android media-session commands through the same playback owner. Configure the speech audio-focus policy with `audio_session`. |
| `lib/playback/store.dart` | Store versioned, account-scoped resume records with `shared_preferences`. |
| `lib/playback/reporting.dart` | Send current live-session start, progress, and stop requests through `JellyfinClient`. Never persist a queue of old live events. |
| `lib/playback/screen.dart` | Display the owner's state and send user commands. It stores no separate listening position. |
| Existing Downloads | Authorize and verify application-private local files. Playback calls `Downloads.localFile(SourceFile)` for every required source. |

The decoder accepts only verified `file:` locations. A missing part prevents the recording from opening. Playback never calls the download request operation and never constructs a remote media URL. It checks local availability again before an explicit Play action. A file that disappears or cannot decode stops playback, retains the last position, and produces an error message.

The shared `MediaPolicy` still controls media acquisition. Small live playback reports use its connected Wi-Fi/mobile network observations separately from its media-transfer permission. Unknown or disconnected networks disable reports. An unavailable server delays another attempt for 30 seconds rather than sending a request for every position sample. A network change permits a fresh current-session attempt. No retry sends an old offline event.

## Positions and ordered files

An audio position retains `AudioPosition.editionId`, `sourceKey`, `revision`, and `milliseconds`. Milliseconds measure recorded audio within that source, not elapsed wall time. Speed never multiplies the stored position. Storage is scoped by the complete `AccountScope.key`, including normalized server URL, server installation ID, and user ID. Each edition retains its own last source position.

Whole-edition time is derived from the ordered files. A seek or short jump can cross a file boundary. Chapters retain their own source identity and source-relative start. A source with no chapter at zero gets a file-start entry; file boundaries do not replace real chapter boundaries. If an earlier duration is unknown, the player does not invent a whole-edition time. Source/chapter seeking remains available.

A restored position must pass `AudioPosition.fits` before use. Changed or empty revisions never validate a prior position. The original record remains stored. Recovery for a replacement source is deliberately undecided in `t8-ld5q`: confirmed fresh start with the original record retained, or reconciliation before listening. This ticket does not silently choose either recovery.

## Durable local resume

The storage namespace is `bookfin.playback.v1.<AccountScope.key>`. Its version-1 record contains the selected edition, a map of edition resumes, speed, and both short-jump lengths. An edition resume retains source key, revision, milliseconds, and `pendingOffline`.

The owner serializes saves about once per recorded second, and at commands, account changes, and application lifecycle transitions. A process kill can lose the interval since the last completed disk write. Ordinary pause, explicit flush, and account transitions wait for relevant writes. On restart, the recording is restored paused after Downloads verifies the files. Account changes immediately hide the old selection and invalidate work still verifying its sources. A command arriving during restoration waits for restoration rather than overwriting the saved position with zero.

`pendingOfflineResume` says that the selected edition has retained local activity from a disconnected or unknown network. It is not a proof that other activity reached Jellyfin. Live reporting does not clear this flag or reconcile the record with another device. A successful standard playback report does not establish full personal-record sync. Intentional rewinds remain valid positions; no greatest-position rule exists here.

## Native controls and interruptions

The pinned native dependencies are `audio_service 0.18.19`, `just_audio 0.10.6`, and `audio_session 0.2.4`. Android declares a media-playback foreground service, a media-button receiver, wake-lock permission, and the Android 14 media-playback service permission. MainActivity extends the plugin's `AudioServiceActivity` while retaining the existing download/network channels.

The media session publishes the book title, author, recording label, known whole-edition duration, recorded-time position, and current speed. Play, pause, stop, seek, rewind, fast-forward, and system seek actions use the playback owner's commands. Stop removes the active native session without deleting the selected resume. A late paused sample cannot reactivate a stopped session. Completion explicitly clears the decoder's play intent, so a later chapter seek remains paused until Play.

The speech audio-focus policy pauses for a transient interruption rather than mixing spoken books with the interrupting audio. The native service remains in the foreground while paused to permit background media-control resumption on recent Android versions. Stop ends that native foreground activity. The sleep timer pauses the same owner and clears itself. Restart does not restore an old sleep deadline or start audio automatically.

## Jellyfin live reporting

| Event | Supported endpoint |
| --- | --- |
| Start | `POST /Sessions/Playing` |
| Progress | `POST /Sessions/Playing/Progress` |
| Stop | `POST /Sessions/Playing/Stopped` |

Each report uses the actual source's Jellyfin item ID and media-source ID. Position ticks are source-relative milliseconds multiplied by 10,000. There is no invented parent-book progress field. A file transition stops the previous source session and starts the new source session. Pause reports the paused state. Completion, stop, account changes, and replacement selections end the relevant live session.

The catalog transport now accepts the successful empty HTTP 204 response used by these endpoints. Redirect refusal, token headers, server-path prefixes, and account guards remain intact. The production reporter uses the same secure persistent device identifier as the catalog.

An offline restart creates no start/progress/stop requests. Reconnection does not replay the previous live-session sequence. A currently playing source can establish a fresh live session from its current position. Pending durable local positions remain separate from that live activity. Server conflict policy and historical activity backfill are not implemented.

## Downstream interface

History and bookmarks should use this existing owner, not create another player or position cache.

| Interface | Meaning |
| --- | --- |
| `Playback.book`, `edition`, `position` | Current selected book, explicit recording, and typed source-relative audio position. |
| `Playback.addListener` | Observe current state after owner changes. It is not a listening-history event stream. |
| `seekSource(sourceKey, milliseconds)` | Restore a chapter or a typed audio bookmark in the current edition. |
| `seekEdition(milliseconds)` | Seek by derived whole-edition recorded time when durations are known. |
| `play`, `pause`, `stop`, `jump`, `setSpeed`, `setJumps`, `setSleep` | Shared commands for the UI and native controls. |
| `flush` | Wait for queued commands and persist current state. It also waits for current report work. |
| `ResumeStore` | Replaceable persistence boundary for durable scoped records, not an agreed server-sync protocol. |
| `checkInvariants` | On-demand check available in every build. Tests or a debug action can call it. |

The owner invariant checker requires a selected book, edition, and source position to appear together. A selected source must belong to its edition and have an account. Playing requires a selected position. Internal programming errors are not converted into successful playback.

History still needs to define and persist the previous/resulting positions around accepted user commands. This ticket does not invent that ticket's event schema or implement a second position mechanism.

## Verification

See `docs/evidence/playback/acceptance.md` for commands, meaningful failing tests, Android observations, and explicit limits. Coverage and mutation testing remain with the parent after acceptance. The parent owns review, integration, and ticket closure.

The integrated real-server follow-up is `docs/evidence/playback/integrated-android.md`.
The later bounded final-head repeat is `docs/evidence/playback/final-head-android.md`.
Its test-only discrete interrupted Pause route is reproducible with
`nix develop --command bash tool/acceptance/run_interrupted_pause.sh emulator-5554`
after opening the device through T3. It requires two T3-supplied synthetic call actions.
Its native-adapter correction keeps cross-file positions with the matching source and excludes unconfirmed loading placeholders.
Confirmed paused seeks still update the visible recorded position without starting audio.
Native Pause retains the last recorded position while releasing the decoder and revoking pending interruption recovery.
