# Disposable Jellyfin research

For production application acceptance, use `tool/acceptance/README.md`.
It reuses this fixture in a fresh checkout-local runtime but tests the actual
catalog and download modules. These research experiments remain server evidence.

This directory runs an isolated Jellyfin server, not a shared machine service.
It never accepts a production origin or production credentials.
All accounts and media are synthetic. The production server was not contacted.

The supported host is Apple Silicon macOS. The dedicated flake pins nixpkgs,
the official Jellyfin 12.4 macOS archive, and the official Enhanced 12.14.0.0
Jellyfin-12 archive. Nix unpacks binaries. It does not compile Jellyfin, .NET,
or FFmpeg from source. `sources.json` records URLs and hashes.

## Run from the repository root

New `.nix` files must be tracked before a Git flake can see them.
These files are committed with this investigation.
The shell has Python, FFmpeg, and both server artifacts. No global installation
or shell-profile change is needed.

Run the server in one terminal:

```sh
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py serve
```

The server binds only `127.0.0.1:7364`. It disables discovery, UPnP, IPv6,
and remote access. Before first use, preparation refuses an occupied port.
The server uses its own data, configuration, cache, plugin, and log directories
under `.cache/sync/runtime/`. It does not use the user's Jellyfin directories.
It does not touch preview ports 7357, 7358, or 7359.

After startup, enter the same pinned shell in another terminal:

```sh
nix develop ./tool/research/sync --command bash
```

Run these commands inside that shell, one at a time:

```sh
python3 tool/research/sync/fixture.py wait
python3 tool/research/sync/fixture.py seed
curl --noproxy '*' --fail --silent --show-error --max-time 30 --max-filesize 4194304 \
  http://127.0.0.1:7364/api-docs/openapi.json -o .cache/sync/openapi.json
python3 -m unittest discover -s tool/research/sync -v
python3 tool/research/sync/experiments.py catalog
python3 tool/research/sync/experiments.py storage
python3 tool/research/sync/experiments.py read-side-effects
python3 tool/research/sync/experiments.py playlists
python3 tool/research/sync/experiments.py provenance
python3 tool/research/sync/fixture.py stop
```

Seeding creates one fixture administrator and two ordinary accounts. It generates
private passwords and writes account tokens only to ignored files with mode 0600.
Do not print or commit `accounts.json` or `passwords.json`.
Do not reuse these credentials outside this disposable instance.

`seed` is a first-use operation. `read-side-effects` is also a first-use
measurement. It removes only Bob's empty Enhanced directory before measuring
which GET requests create storage. It refuses a directory with existing files.
Run this phase after `storage`, before any other read of Bob's settings.

`catalog` needs the server's scan to finish. If the expected five audio files or
two chapters are not present yet, wait for the scan to complete and rerun that
phase. `seed-media` can add the two synthetic chapters to an older fixture.
The EPUB is deliberately tiny. It is not a reader conformance sample.

`storage` reads the served OpenAPI document from `.cache/sync/openapi.json`.
The listed curl command bounds that public schema download to 4 MiB.

The HTTP client rejects nonliteral hosts, remote addresses, URL credentials,
redirects, proxies, and responses larger than 2 MiB. A download needs an explicit
boolean permission. A denied Download request never triggers a File request.

## Restart and shutdown

After `stop` exits, wait for the server terminal to exit. Start the same `serve`
command again. The fixture data persists. Then run:

```sh
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py wait
nix develop ./tool/research/sync --command python3 tool/research/sync/experiments.py after-restart
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py stop
```

Shutdown authenticates as the generated fixture administrator. It first compares
the server identifier with the fixture's saved identifier. It refuses to stop an
unrecognized server. No launch agent, system service, emulator, browser, or
other process is stopped or changed.

When starting `serve` as a background shell job, redirect its input from
`/dev/null`. Otherwise, the terminal can suspend Jellyfin while it reads input.
`wait` accepts a startup response without a version as not ready. It has a
90-second deadline and a two-second timeout per HTTP request.

After shutdown, removing only `.cache/sync/runtime/` discards the synthetic
accounts and state. Do not remove another checkout's directories. Keep that
directory if the parent needs a restartable fixture. Evidence is bounded JSON in
`evidence/`, not server logs. Local logs contain synthetic names and remain
ignored. Stop the fixture after research instead of leaving it unattended.

## Evidence boundaries

`experiments.py` asserts the measured server behavior. It is not a Bookfin sync
implementation. Some assertions deliberately prove data loss in existing APIs.
The initial failing tests and later passing tests cover the research client's
behavior, not a change to Jellyfin.

`catalog-dtos.json` contains real disposable server responses with path prefixes
rewritten to `/synthetic/`. Its expected grouping describes the authored fixture.
It does not prove that the application mapper inferred that grouping. The parent
must run the application mapper against these responses before closing boo-2cgp.

See `docs/research/jellyfin-sync.md` for the storage decision gate. Private
playlists are a separate, promising candidate. Snapshot counterexamples do not
prove that every existing-storage protocol is impossible. No plugin or new
personal-record transport is selected by this research.

## Private playlist protocol follow-up: t3-7fv1

Read `docs/research/jellyfin-playlist-protocol.md` for the exact decision boundary.
This follow-up does not need the CustomPrefs or Enhanced storage phases above.
Use a fresh fixture in your own checkout; never copy generated account files
from another checkout or start a second listener on port 7364.

Start `serve` as above with stdin redirected from `/dev/null`. Wait for readiness,
then run `seed` once on the new fixture. Run these pinned commands sequentially:

```sh
nix develop ./tool/research/sync --command python3 -m unittest discover -s tool/research/sync -v
nix develop ./tool/research/sync --command python3 tool/research/sync/playlist_protocol.py confidentiality
nix develop ./tool/research/sync --command python3 tool/research/sync/playlist_protocol.py objects
nix develop ./tool/research/sync --command python3 tool/research/sync/playlist_protocol.py paging
nix develop ./tool/research/sync --command python3 tool/research/sync/playlist_protocol.py scan
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py stop
```

Wait for the server process to exit. Start the same `serve` command again with
the same isolated directories, then run:

```sh
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py wait
nix develop ./tool/research/sync --command python3 tool/research/sync/playlist_protocol.py restarted
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py stop
```

After the process exits, `lsof -nP -iTCP:7364 -sTCP:LISTEN` must show no listener.
Keep `.cache/sync/runtime/` to allow the parent to restart this disposable fixture.
The retained fixture from t3-b22c5e06 is stopped and restartable.

`confidentiality` tests Alice's positive payload read and Bob's negative read on
the same `GET /Items/{id}` route. It writes only statuses, a payload hash, and
absence checks to the public evidence. `objects` deliberately tests a public
toggle on a separate synthetic playlist: Bob reads the synthetic note only
after that explicit change, and the phase restores private visibility. It also
measures a real unread create acknowledgment, caller-ID deduplication, owner
management, and sampled create/update sizes. `paging` measures a deletion and a
separate insertion between offset pages. `scan` waits for a newly completed library scan rather than merely
observing an idle task before a queued scan starts. `restarted` checks the same
server identity and exact private payload after clean restart.

The initial research decoder is not an app transport. It combines equal operation
identifiers only when their payloads agree, and rejects conflicting duplicate
payloads. It does not implement current-record merging, retained deletion fences,
checkpoint compaction, replica retirement, or history retention. The new product
decision tickets are tb-5fyd and tb-887c. No production plugin is selected.

## Finite checkpoint continuation

Read `docs/research/jellyfin-finite-checkpoint.md` for the measured result and its
remaining blockers. `finite_journal.py` is the single checkpoint/coverage model;
`finite_runtime.py` applies it to real disposable server objects. It is research,
not an app transport. Fixed identities, no expiry, unresolved conflicts, batch
size 100, and the 64 KiB object envelope are research conditions, not product
policy. Deletion witnesses and actions above a gap remain stored without a
lifetime bound. No history retention or conflict winner was selected.

The research flake also pins the official 12.3 macOS ARM64 archive. Its fixed
output derivation unpacks that archive. `BOOKFIN_SYNC_OLD_SERVER` names it.
`BOOKFIN_SYNC_SERVER` still defaults to 12.4. The exact pair tested is runtime
12.3.0 to 12.4.0; it is not a general upgrade or rollback guarantee.

Use a fresh checkout-local fixture, not an existing stopped fixture. In the
server terminal, start the old version without Enhanced:

```sh
nix develop ./tool/research/sync --command bash -c \
  'export BOOKFIN_SYNC_CORE_ONLY=1 BOOKFIN_SYNC_SERVER="$BOOKFIN_SYNC_OLD_SERVER"; exec python3 tool/research/sync/fixture.py serve' </dev/null
```

In another terminal, run each command sequentially. The first command requires
the old runtime version explicitly. `seed`, `schedule`, and `workload` are
first-use operations and refuse reuse of their existing synthetic state.

```sh
nix develop ./tool/research/sync --command bash -c \
  'BOOKFIN_SYNC_VERSION=12.3.0 python3 tool/research/sync/fixture.py wait'
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py seed
nix develop ./tool/research/sync --command python3 -m unittest discover -s tool/research/sync -v
nix develop ./tool/research/sync --command python3 -O -m unittest discover -s tool/research/sync -p test_finite_journal.py -v
nix develop ./tool/research/sync --command python3 tool/research/sync/finite_runtime.py model-costs
nix develop ./tool/research/sync --command python3 tool/research/sync/finite_runtime.py schedule
nix develop ./tool/research/sync --command python3 tool/research/sync/finite_runtime.py workload
nix develop ./tool/research/sync --command python3 tool/research/sync/finite_runtime.py before-upgrade
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py stop
```

After the server exits and port 7364 has no listener, restart the same directories
with the default new binary. Do not run `seed` again:

```sh
nix develop ./tool/research/sync --command bash -c \
  'export BOOKFIN_SYNC_CORE_ONLY=1; exec python3 tool/research/sync/fixture.py serve' </dev/null
```

In the other terminal, measure and stop:

```sh
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py wait
nix develop ./tool/research/sync --command python3 tool/research/sync/finite_runtime.py after-upgrade
nix develop ./tool/research/sync --command python3 tool/research/sync/fixture.py stop
```

Wait for exit, verify the listener is gone, and repeat the new-binary start once.
Run `wait`, then `finite_runtime.py after-new-restart`, then `fixture.py stop`,
all through the same Nix shell. Verify process exit and no listener again.
Do not open the old binary against the migrated directories; rollback was not
tested. The current worktree's fixture is already seeded, stopped, and retained.
Its ignored expected-state files are measurement oracles, not a second sync
authority. Generated credentials and expected-state files remain mode 0600 under
the mode 0700 runtime directory. No credentials from another fixture are needed.

Final discovery uses all owner playlists, with namespace decoding locally.
It does not use `SearchTerm`: the captured 12.3.0 search omitted four of 16
acknowledged objects with page size four even while writes were stopped.
Two matching scans are not proof of a snapshot under concurrent changes. A
128-request safety budget aborts rather than returning an incomplete inventory.
The earlier filtered-query traces are retained separately from final unfiltered
workload evidence. Neither these probes nor the unit tests claim server-side
atomic checkpoint merging. Coverage and mutation testing remain parent-owned.
