# Disposable Jellyfin research

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
