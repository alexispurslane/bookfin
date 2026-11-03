# Remaining normal-app Android acceptance

Exclusive November 3, 2026 acceptance lane. Full results and required-stop limits:
`docs/evidence/reader/android-remaining-20261103.md`.
Application source: `71af2886e722b7366d4d335622e55e18a151a3e0`.
Evidence base: `772d8a50b64cafa99baf534f8f74274a9882126c`.
No production change, reset, uninstall, private-row write, ticket closure, or publication.

Active recognition and one Cancel dispatch were observed on the normal APK.
The next snapshot and its one advised retry failed. Device UI work stopped.
Do not rerun `ui.py`, `fixture.py`, or device capture helpers under this stopped lane.
Only the host-only audit below can be repeated without renewed device authorization.
An initial successful snapshot omitted an unchanged tree. The local selector guard
dispatched no input; subsequent complete snapshots use `--force-full` explicitly.

| Evidence | Purpose |
| --- | --- |
| `artifact.json`, `corpus.json` | Exact installed APK and new ordinary scan inputs |
| `baseline.json`, `normal-installed.json` | All 69 prior actions retained through normal update |
| `during-dense.json` | A new ordinary resume action is genuinely pending |
| `stop-audit.json`, `final-retained.json` | All 69 prior actions unchanged; new action acknowledged; device state |
| `stop-server.json` | Exact real plugin action, payload hash, identity, and causal context |
| `dense-active-cancel-before.txt`, `dense-active-cancel.txt` | Fresh complete active-recognition snapshot and Cancel dispatch |
| `dense-canceled.txt`, `cancel-recovery.txt`, `snapshot-diagnostics.json` | Initial snapshot failure and single failed retry |
| `events.ndjson`, other `.txt` files | Bound commands, timestamps, complete snapshots, radio settings, downloads |
| `recovery-inventory.json` | Read-only search of eight conventional existing fixture backups; no match |
| `cleanup.json`, `read-only-logs.json` | Host cleanup and precise device cleanup still required |
| `binding-release.json` | Successful release of the owned binding, without shutdown or app cleanup |
| `audit.py`, `audit.json` | Host-only comparisons and evidence hashes, not acceptance of invisible behavior |

An action is one retained personal-record change. Pending means its upload is not
acknowledged locally. Account strings are hashed before exported action content;
payload hashes cover the original bytes before sanitization. No passwords, tokens,
raw private databases, or private raw logs are committed. Temporary private database
copies are deleted automatically. The generated fixture and credentials were removed
only after its sole new action exactly matched the real plugin with zero new pending
actions. Original 28 pending actions remain unchanged and unrecovered.

The shared emulator remains signed in and running, with two owned downloads and
airplane/Wi-Fi/mobile-data `1/0/0`. Media is muted; system text size remains large.
The owned server, credentials, and reverse route are removed. Binding release does
not sign out or close the app. See the report for the release result.

The only repeatable command for this stopped lane is:

```sh
nix develop --command python3 tool/evidence/reader/integrated/20261103/remaining/audit.py
```

Fixture reproduction requires the pinned sync shell, unchanged plugin package,
and existing `generated-english.png`. The dense page draws that exact image 22
times in two columns at 1600 by 4000 PDF points. It contains no PDF text layer.
The second page and both pages of the separate blank PDF have zero drawing
commands and no text layer. Blank-page application acceptance was never reached.
