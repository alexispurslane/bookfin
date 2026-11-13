# Downloaded audio playback

Ticket: boo-sthf. Base: `c13748198f0b7f73ad0ba1ec2b7ac84fbe989627`.
Personal records: boo-6h8w. Base: `e8fe9c7`.

Android now plays a downloaded audio edition through its ordered local files. The production library opens the player from an edition's Listen action. A mini-player remains available in the library, Downloads, and book details. Listening is the existing third navigation destination, not a second navigation system. The full player uses the shared cream/sepia theme and bundled fonts. Its sheets use the application's reduced-motion-aware route transitions.

Playback does not stream audio, acquire remote files, implement an ebook reader, resolve sync conflicts, or provide full personal-record sync.

## Ownership and boundaries

| Module | Responsibility |
| --- | --- |
| `lib/playback/playback.dart` | Own the selected account, book, edition, source-relative position, playback state, speed, short jumps, sleep timer, history, and bookmarks. Serialize commands and durable writes. |
| `lib/playback/native.dart` | Decode local files with `just_audio`. Route Android media-session commands through the same playback owner. Configure the speech audio-focus policy with `audio_session`. |
| `lib/playback/store.dart` | Store versioned, account-scoped personal records with `shared_preferences`. |
| `lib/playback/records.dart` | Define immutable listening actions, bookmarks, and their stored representation. |
| `lib/playback/reporting.dart` | Send current live-session start, progress, and stop requests through `JellyfinClient`. Never persist a queue of old live events. |
| `lib/playback/screen.dart` | Display the owner's state and send user commands. It stores no separate listening position. |
| `lib/playback/records_screen.dart` | Display account history, restore controls, bookmark editing, and save failures. Use the existing navigator and shared theme. |
| Existing Downloads | Authorize and verify application-private local files. Playback calls `Downloads.localFile(SourceFile)` for every required source. |

The decoder accepts only verified `file:` locations. A missing part prevents the recording from opening. Playback never calls the download request operation and never constructs a remote media URL. It checks local availability again before an explicit Play action. A file that disappears or cannot decode stops playback, retains the last position, and produces an error message.

The shared `MediaPolicy` still controls media acquisition. Small live playback reports use its connected Wi-Fi/mobile network observations separately from its media-transfer permission. Unknown or disconnected networks disable reports. An unavailable server delays another attempt for 30 seconds rather than sending a request for every position sample. A network change permits a fresh current-session attempt. No retry sends an old offline event.

## Positions and ordered files

An audio position retains `AudioPosition.editionId`, `sourceKey`, `revision`, and `milliseconds`. Milliseconds measure recorded audio within that source, not elapsed wall time. Speed never multiplies the stored position. Storage is scoped by the complete `AccountScope.key`, including normalized server URL, server installation ID, and user ID. Each edition retains its own last source position.

Whole-edition time is derived from the ordered files. A seek or short jump can cross a file boundary. Chapters retain their own source identity and source-relative start. A source with no chapter at zero gets a file-start entry; file boundaries do not replace real chapter boundaries. If an earlier duration is unknown, the player does not invent a whole-edition time. Source/chapter seeking remains available.

A restored position must pass `AudioPosition.fits` before use. Changed or empty revisions never validate a prior position. The original record remains stored. Ticket `t8-ld5q` implements the approved confirmed fresh start: the user confirms before replacement audio starts at zero. Cancel keeps the current selection and all records. A failed load does not commit a replacement position. A canceled or obsolete confirmation cannot commit after a delayed load.

Resumes remain separate for each set of source keys and source revisions within an edition. A source revision identifies one version of an audio file. Changing a revision cannot overwrite the original recording's resume, even when both recordings start with an unchanged file. Correcting file order preserves the resume within its source and reloads the decoder in the corrected order. Returning to either recording restores that recording's own resume. History and bookmarks retain their original source positions; the existing source checks still decide whether a restore is safe. No record is rewritten to match changed audio.

## Durable local resume

The storage namespace remains `bookfin.playback.v1.<AccountScope.key>`. The payload now uses version 3. Version-1 and version-2 resumes migrate in place after a successful read. The selected edition, speed, and short-jump lengths retain their meanings. Each edition now retains a list of resumes. Each resume retains source key, revision, milliseconds, and `pendingOffline`, plus the set of source keys and revisions for a known recording. Version 2 introduced history and bookmarks; version 3 keeps them unchanged. Legacy resumes retain their original source scope until a matching recording is loaded. Migration never invents a changed source revision for a legacy position.

The owner serializes saves about once per recorded second, and at commands, account changes, and application lifecycle transitions. A process kill can lose the interval since the last completed disk write. Ordinary pause, explicit flush, and account transitions wait for relevant writes. On restart, the recording is restored paused after Downloads verifies the files. Account changes immediately hide the old selection and invalidate work still verifying its sources. A command arriving during restoration waits for restoration rather than overwriting the saved position with zero.

`pendingOfflineResume` says that the selected edition has retained local activity from a disconnected or unknown network. It is not a proof that other activity reached Jellyfin. Live reporting does not clear this flag or reconcile the record with another device. A successful standard playback report does not establish full personal-record sync. Intentional rewinds remain valid positions; no greatest-position rule exists here.

## History, Undo, and bookmarks

The playback owner records accepted position changes through one transition operation. Slider release, short jumps, chapters, native controls, Undo, and restores use it. `AudioEngine.seek` returns the decoder's confirmed source and time. History retains that result, rather than assuming that the requested time was accepted. The native adapter still rejects loading placeholders and accepts confirmed zero positions.

Each action retains a stable random identifier, UTC timestamp, action kind, previous position, resulting position, book title, and recording label. Both positions include edition ID, source key, source revision, and recorded milliseconds within that source. Restores between editions retain both edition IDs. Pauses, resumes, interruptions, stops, and completion use the same action representation. Decoder time updates save resumes but do not create visible history rows.

A slider drag retains its starting position in the playback owner. The slider displays a proposed target during dragging without moving the decoder. Release submits one completed seek. Another position command, account change, or recording selection invalidates an unfinished drag. The slider's proposed target is not another listening position.

Undo restores the previous position of the latest accepted position action. Dismissing Undo hides only its immediate control. The original action remains in persistent history. The History control opens account-wide history from the existing Listening destination, even when no recording can open. Each position action offers its previous position and its result separately. A pause or interruption offers its recorded place. Every successful restore appends a new action. No operation erases the action that it reverses.

Bookmarks retain a stable identifier, source-relative position, creation time, recording identity, optional title, and optional note. The bookmark editor retains the position that it showed when opened. Editing title or note does not move the bookmark. Delete requires confirmation. Bookmark restores use the same transition operation as other seeks.

Restores require the current account's record, a matching source revision, a valid source-relative position, and verified local files. Changed or unavailable sources keep their records without applying them. The unresolved recovery choice in `t8-ld5q` remains open. Missing files and decoder failures do not append successful restore actions.

Unreadable or unsupported personal records disable saving for that restoration attempt. A new recording cannot start until an account restoration succeeds. Flush, sign-out, and later commands cannot overwrite those stored records. A failed write leaves the latest complete account snapshot available for retry in the running process. Account changes hide that snapshot from other accounts. Returning to the account restores its pending snapshot before attempting another write. The interface warns that records are not saved and offers Retry saving. Closing the process before a retry succeeds can lose those unsaved changes. No durable success is claimed for a failed write.

History has no silent pruning or expiry. Bookmark deletion is local deletion, not a selected deletion protocol for synchronization. No history transport, merge policy, remote retention rule, or long-offline recovery policy is implemented here.

## Native controls and interruptions

The pinned native dependencies are `audio_service 0.18.19`, `just_audio 0.10.6`, and `audio_session 0.2.4`. Android declares a media-playback foreground service, a media-button receiver, wake-lock permission, and the Android 14 media-playback service permission. MainActivity extends the plugin's `AudioServiceActivity`. It owns no channel: the download, network, device, speech and power channels belong to the engine plugin in `HostChannels.kt`, because the cached engine outlives an Activity.

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
| `Playback.addListener` | Observe state after owner changes. Use the owner's retained history rather than inferring actions from notifications. |
| `seekSource(sourceKey, milliseconds)` | Select a chapter in the current edition. |
| `seekEdition(milliseconds)` | Seek by derived whole-edition recorded time when durations are known. |
| `beginSliderSeek`, `finishSliderSeek` | Retain the drag's origin and accept one target at release. |
| `history`, `restoreHistory`, `undoSeek`, `dismissUndo` | Read immutable account history and recover positions without removing prior actions. |
| `bookmarks`, `addBookmark`, `editBookmark`, `deleteBookmark`, `restoreBookmark` | Manage bookmarks through the same account and command owner. |
| `unsavedChanges`, `saveFailed` | Distinguish queued or failed writes from durable success. Retry through `flush`. |
| `replacementStart`, `confirmReplacement`, `cancelReplacement` | Offer a fresh start and accept or cancel that exact offer. Account or catalog changes invalidate earlier offers. |
| `play`, `pause`, `stop`, `jump`, `setSpeed`, `setJumps`, `setSleep` | Shared commands for the UI and native controls. |
| `flush` | Save the current confirmed place and retry pending records for every account. Wait only for local record writes. Await a command's own future when its result is needed. Teardown stops audio and drains live reports. |
| `refreshPersonalRecords` | Adopt durable history, bookmarks, and resumes without waiting for audio commands or account restoration. Keep the current decoder position. Reject a snapshot after local changes, account replacement, or close. Leave rejected records stale for retry. |
| `ResumeStore` | Replaceable persistence boundary for durable scoped records, not an agreed server-sync protocol. |
| `checkInvariants` | On-demand check available in every build. Tests or a debug action can call it. |

The owner invariant checker requires a selected book, edition, and source position to appear together. A selected source must belong to its edition and have an account. Playing requires a selected position. History identifiers and bookmark identifiers are unique within their record types. Undo references a retained action. An unfinished slider origin fits the selected edition. Every failed account write retains a pending snapshot. A replacement offer belongs to a restored account and an edition in its current catalog. Tests can call `checkInvariants` in every build. Internal transition assertions compile out of release builds. Internal programming errors are not converted into successful playback.

Record refresh waits for local writes that already started. It refuses adoption while a write remains pending or the account has not restored. The account generation identifies one binding lifetime, including when the user leaves an account and returns. Refresh captures that generation before any wait. The record revision counts changes to the live records. Refresh checks it after reading, so a concurrent local save cannot disappear. Adopting a snapshot advances that revision too. An older overlapping refresh cannot replace a newer adoption. Only adoption calls `acceptSnapshot`. Undo then refers to the adopted history entry with the same identifier, or ends if that entry was deleted. Read failures reach sync without stopping audio. Programming errors still reach the caller.

Sync awaits that guarded refresh before completing each sync operation. A rejected snapshot stays stale and can be retried after restoration or a later sync. No refresh task continues after its future completes. An exchange can finish while audio remains held, including an incomplete upload that still receives records. Each audio command still saves its own confirmed result through the existing record writer. See `docs/evidence/playback/record-refresh.md` for the controlled tests and their limits.

## Verification

See `docs/evidence/playback/acceptance.md` for commands, meaningful failing tests, Android observations, and explicit limits. Coverage and mutation testing remain with the parent after acceptance. The parent owns review, integration, and ticket closure.
See `docs/evidence/playback/personal-records.md` for the history and bookmark implementation's red/green tests, builds, and runtime limits.

The integrated real-server follow-up is `docs/evidence/playback/integrated-android.md`.
The later bounded final-head repeat is `docs/evidence/playback/final-head-android.md`.
The later personal-record runtime attempt is `docs/evidence/playback/personal-records-android.md`.
It stopped before sign-in after device-command failures and adds no runtime acceptance pass.
Its test-only discrete interrupted Pause route is reproducible with
`nix develop --command bash tool/acceptance/run_interrupted_pause.sh emulator-5554`
after opening the device through T3. It requires two T3-supplied synthetic call actions.
Its native-adapter correction keeps cross-file positions with the matching source and excludes unconfirmed loading placeholders.
Confirmed paused seeks still update the visible recorded position without starting audio.
Native Pause retains the last recorded position while releasing the decoder and revoking pending interruption recovery.

Cross-edition recovery commits selection and history only after the decoder confirms a position. If loading or confirmation fails, the old selection and Undo remain. Decoder readiness means that its loaded files match the selected edition. A failed load clears readiness, so its samples cannot change the retained position. Play and seek reload that selection before using the decoder again. The invariant checker requires every ready decoder to have a selected edition.

Slider origins are captured at gesture start, before any wait for queued disk writes. Explicit Pause and Stop records describe command effects independently of playing-state observations. The shared mini-player exposes Undo and stays available on History.

Completed slider releases retain separate immutable origins while they wait in the command queue. A gesture-cancellation counter invalidates releases after account changes, selection changes, or non-slider seeks. Completing another slider gesture does not change that counter. Loading and seeking report whether they applied the requested transition. A reload that cannot find a required file does not clear Undo.
