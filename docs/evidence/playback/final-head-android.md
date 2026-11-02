# Final-head bounded Android playback observations

Date: November 2, 2026. All times below are UTC.
Base: `03ac7f5f8eafead7ff08420553406d5f51d4ccf6`.
Correction under test: `2edad39fefa1d06bbcbcc25dd4f8b3fb091a64ea`.
Tickets: `boo-sthf`, `t0-dqxp`, and `t0-60ea`.
The parent owns review, integration, acceptance, and ticket closure.

## Scope and source identity

No application playback code changed during this follow-up. No concrete
regression in the correction was observed. The earlier acceptance and its APK
hashes do not prove the builds described here.

`final-head-observations.json` contains the final source hashes, allowlisted
native states, synthetic media hashes, and actual Jellyfin report responses.
It contains no passwords, tokens, authentication bodies, or private device dumps.
It is manual runtime evidence, not output certified by the application HTTP
acceptance publisher. That publisher's larger suite was not rerun here.

| Artifact or source | SHA-256 |
| --- | --- |
| Final normal-app debug APK, also read back from the installed package | `71c55e1dfbfeeea00b5dbdd17430ac103ad4b36f57964508245d427f4ceef306` |
| Final Android integration-test APK | `373110187a0345295885bf860ccb1362f179b17b80e009b0a9baa67ef83aca28` |
| `lib/playback/native.dart` | `7c3abc5c57d652c39c380be617708d3f5f8130594fc013365bed7283fd685a14` |
| `lib/playback/playback.dart` | `ae0d43385e6b616321cbd1a81a721a874e48772a5f7a00c6fd4e7d821effe63a` |
| `integration_test/interrupted_pause_test.dart` | `f370385f462ad948048a22964df868ab96383fe3612ddd068c3261393b577ed5` |

The normal-app APK remains ignored at `.cache/production-verified.apk` in this
worktree. The test APK remains at `.cache/interrupted-pause-final-test.apk`.
Neither APK is committed.

## Chronology and build distinction

| Time | Observation |
| --- | --- |
| 08:52 | Preserved an initial normal-app APK, SHA-256 `9eda697e67fb2375f06fac49646ab70473700ca93ea1e533bec3df4bd9dde009`. This preceded the new development dependency. Its early manual observations are not used as final-APK acceptance. |
| 08:55 | First real-decoder interrupted Pause test passed at 30,746 milliseconds. Its separate test APK had SHA-256 `9f1eb6a5e048c0db9e3861866f9c8bd83f9fcc190f4c94803b14ef17647f163e`. |
| 09:07–09:08 | Repeated the test after replacing test log calls with Flutter's debug log function. The final test APK retained 34,642 milliseconds through focus return and passed. |
| 09:10 | Rebuilt the normal application after adding the development dependency and the Nix/Gradle test-plugin directory fix. The APK hash was `71c55e1d…`; a clean dependency refresh followed by another build produced the same hash. |
| 09:12–09:20 | Prepared the final normal-app run through the production screens, repeated the bounded playback checks, removed downloads, and signed out. The installed APK read back at 09:16 matched the full final normal-app hash above. |
| 09:20 | Sign-out survived process restart. Both owned servers exited, both ports had no listeners, network settings were restored, and the own device binding was released without shutdown. |

## Final normal-app APK observations

All positions are milliseconds of recorded audio, not elapsed wall-clock time.
An edition position counts from the beginning of the ordered two-file recording.
A source position counts from the beginning of one file. Jellyfin ticks are
100-nanosecond units, so 10,000 ticks equal one millisecond.

| Action on the final normal-app APK | Observed result |
| --- | --- |
| Native media-button Pause while playing | Android published `PAUSED` at 19,929 edition milliseconds. Jellyfin accepted the paused first-source progress at 199,290,000 ticks with HTTP 204. |
| Restart the process after native Pause | The selected recording restored to exactly 19,929 milliseconds. Android published inactive `NONE`, the screen offered Play, and audio did not restart. This is not mislabeled as an active paused decoder. |
| Native Play after restoration | A fresh real-server start retained the first source at exactly 199,290,000 ticks. No loading-zero progress appeared during this reactivation. |
| Paused seek to Beginning | Android stayed `PAUSED` at zero. Jellyfin accepted the intentional first-source zero position. This is a legitimate user seek, not a loading placeholder. |
| Paused seek to Ending | Android stayed `PAUSED` at 90,000 edition milliseconds; the screen showed 01:30 and Play. |
| Paused seek to the second file's beginning | Android stayed `PAUSED` at 180,000 edition milliseconds, with zero milliseconds relative to the second source. |
| Rewind ten seconds, then Play through the file boundary | The first source restarted at 1,700,010,000 ticks. Natural transition stopped the first source at 1,798,300,000 ticks, then started the second source at 210,000 ticks. Each real Jellyfin response was HTTP 204. No previous-source zero was inserted at the boundary. |
| Disable Wi-Fi and mobile data, and remove the own reverse forward | Diagnostic reads showed both settings zero, no reverse forward, and no active default network. Downloaded playback advanced from 224,589 to 242,387 edition milliseconds while disconnected. |
| Restart during disconnected playback | Restoration stayed inactive at 242,186 edition milliseconds, 201 milliseconds earlier than the last native sample. It restored the last saved sample, not zero, and did not autoplay. The screen identified the saved library and unreachable server. |
| Explicitly Play while still disconnected | Native playback advanced to 274,227 edition milliseconds without a default network or server forward. |
| Pause offline, restore connectivity, and refresh the catalog | The normal production refresh succeeded. The observer's total playback-request count stayed 37 before and after reconnect, over a 62-second observation interval. Native position stayed paused at 274,595 edition milliseconds. No obsolete offline report sequence was replayed. |
| Explicitly Play after reconnect | One fresh second-source start used 945,970,000 ticks, or 94,597 source milliseconds. Jellyfin returned HTTP 204. |

The final normal-app interval contains five starts, twelve progress reports, and
three stops. All twenty responses were HTTP 204 from the actual disposable
Jellyfin 12.4.0 server. The observer forwarded original response bytes; it did not
replace Jellyfin or invent file validators. The two downloads contained 796,707
bytes in total. Only generated AAC media and generated fixture accounts were used.

## Discrete Pause while focus was already lost

Audio focus is Android's coordination of which application may play audio.
The test waited for a real Android focus-loss event and for the real decoder
to report that playback had paused. Only then did it execute this test line:

```dart
        await handler.pause();
```

where

- `handler` = the existing production `PlaybackHandler`, attached to the production playback owner.
- `pause()` = its discrete audio-service Pause entry point, called by this integration test rather than a physical media controller.

T3 supplied both the incoming synthetic call and its cancellation. After the
call ended, the test waited three seconds and checked both the real decoder and
the playback owner. Neither resumed, and both retained exactly 34,642 milliseconds.
The production owner's invariant checker also passed. The test passed with its
final source hash listed above.

The decoder is the native component that reads the local file and produces
audio. This test uses the existing `LocalAudioEngine` and a real `AudioPlayer`.
Only the generated local-file lookup and resume storage use existing test
fixtures. Thus this test does not claim download-policy, Jellyfin, durable-store,
or external-controller dispatch acceptance. The normal-app run separately
exercises production downloads, storage, and Jellyfin reporting. No production
control, permission, or alternative player path was added.

The helper's documented phone hardware commands expose only a play/pause toggle.
Its TV command is documented as unsupported on phones. Neither was repeatedly
tried as a discrete Pause route, and no ADB media command was dispatched.

To repeat with a T3-opened Android device:

```sh
nix develop --command bash tool/acceptance/run_interrupted_pause.sh emulator-5554
```

At `FOCUS_TEST_READY`, send a call with the caller's own device-bound
`agent-device telephony call 5550199`. At `FOCUS_TEST_PAUSED`, end that call with
the same binding's `telephony cancel 5550199`. Each gate has a 120-second limit.
Use `device_open` to obtain a new binding; never reuse this run's closed binding.

## Verification and test infrastructure

| Check | Result |
| --- | --- |
| Existing focused native unit suite through the pinned Nix shell | 10 tests pass, including the parent's loading-state regression. |
| Final default Flutter suite through the pinned Nix shell | All 200 tests pass. |
| Final Android integration test through the pinned Nix shell | One test passes against the real decoder. |
| Final `flutter analyze --no-pub` | No issues. |
| Final Dart format check, shell syntax check, and `git diff --check` | Pass. |
| Normal debug APK after dependency refresh | Builds; installed bytes match the recorded final hash. |

Adding the SDK's `integration_test` development dependency initially made Gradle
reject its native directory in the read-only Nix store. This was an infrastructure
failure, not a meaningful failing playback regression. Android settings now copy
only that pinned SDK plugin's native directory to an ignored writable directory
when needed. Ordinary dependency refresh and normal application builds work;
the test runner does not leave a private generated-plugin metadata patch behind.

The exact Pause-during-loading schedule remains deterministic unit-test evidence.
The emulator checks observe retained Pause, reactivation, seeking, transitions,
and interruption behavior; they do not claim that a human command landed inside
that brief loading interval. No further application defect or fix was invented.

## Cleanup and remaining boundaries

The production Downloads screen showed No downloads yet after removal. Sign-out
survived a process restart, and native state returned to `NONE` at zero. Wi-Fi and
mobile data were both restored to their original enabled values. The own reverse
forward was removed. The own Jellyfin server exited normally; the own observer
exited on SIGTERM. Neither port 7364 nor 7365 had a listener afterward. The own T3
device binding was released with `shutdown: false`. Private synthetic fixture
state remains ignored under this worktree's `.cache` only.

One field-focus refusal recovered on the advised diagnostic retry. Stale field
references were replaced with current references or stable selectors. Unsupported
bare network-setting reads were not used as evidence; supported writes and
diagnostic reads established the network states. No prohibited UI driver was used.

This follow-up does not claim physical-phone behavior, a credential-locked screen,
background soak, full personal-record sync, coverage, or mutation testing.
Changed-source recovery `t8-ld5q` and real-server ETag behavior `t7-bzzg` remain
unchanged. Both original acceptance tickets remain for the parent to review and
close after integration.
