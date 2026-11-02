# Disposable Jellyfin application acceptance

This suite calls Bookfin's production modules over real HTTP.
The earlier research client supplies fixture setup, not application behavior.
The only supported origin is `http://127.0.0.1:7364`.
Use only this checkout's synthetic accounts, libraries, and media.
Never copy another checkout's runtime or use production credentials.

The existing research flake pins the official Jellyfin 12.4.0 archive and hash.
This run uses Jellyfin core only, without Enhanced.
The application flake supplies Flutter. No toolchain is installed globally.

## First run

Run from the repository root on Apple Silicon macOS.
If port 7364 has a listener, stop here. Do not stop an unrelated service.
Start the server in one terminal:

```sh
umask 077
mkdir -p .cache
chmod 700 .cache
lsof -nP -iTCP:7364 -sTCP:LISTEN
nix develop ./tool/research/sync --profile .cache/sync-shell --command bash -c \
  'export BOOKFIN_SYNC_CORE_ONLY=1; exec python3 tool/research/sync/fixture.py serve' \
  </dev/null >.cache/jellyfin-server.log 2>&1
```

The first `lsof` must report no listener.
In another terminal, run each command sequentially:

```sh
umask 077
nix develop .cache/sync-shell --command python3 tool/research/sync/fixture.py wait
nix develop .cache/sync-shell --command python3 tool/research/sync/fixture.py seed
nix develop .cache/sync-shell --command python3 tool/acceptance/jellyfin_fixture.py
nix develop --profile .cache/dev-shell --command flutter pub get
nix develop .cache/sync-shell --command python3 tool/acceptance/collect_evidence.py
```

Preparation adds an accessible non-book library and identical public item titles.
Real track and disc numbers remain unchanged.
The source-replacement check temporarily appends synthetic bytes to one audio
file, then restores its original bytes and refreshes Jellyfin.
Cleanup also restores and checks the original item title after the scan.
The publisher deletes stale observations, runs the live Flutter suite itself, and
requires its successful exit, including cleanup, before reading results. It also
refuses sources that differ from their original hashes. A separate earlier test
run cannot authorize publication.

The live suite stays outside the default `test/` directory.
Without the explicit Dart definition, the live checks are skipped.
Run only one live suite against this fixture at a time.

## Repeat and stop

Retain `.cache/sync/runtime/` for restart.
Do not rerun `seed` or preparation on a completed fixture.
Start the same core-only server, run `wait`, then rerun the live suite.
The suite creates private temporary storage and restores changed user policy.

Stop only this recognized fixture:

```sh
nix develop .cache/sync-shell --command python3 tool/research/sync/fixture.py stop
lsof -nP -iTCP:7364 -sTCP:LISTEN
```

The server terminal must exit. The final `lsof` must report no listener.
Passwords and tokens remain in ignored mode-0600 files under the mode-0700
runtime directory. The server log stays private and ignored.

## Evidence boundaries

`JellyfinClient`, its normal IO transport, `CatalogController`, `buildBooks`,
and `LocalDownloads` are production code.
The HTTP observer returns each real response unchanged.
It records no bodies or authentication headers and rejects nonfixture addresses.

`DiskCredentials` and `DiskCatalog` are test-only storage implementations.
They exercise session serialization, account-scoped cache serialization, and a
new controller's restoration. They do not exercise native secure storage.
Download bytes and manifests use the production filesystem implementation.

Read `docs/acceptance/jellyfin-app.md` for results and release gates.
Real Jellyfin omits a strong HTTP ETag on Download.
This suite proves safe full-restart recovery, not real-server range resume.
The synthetic transfer suite separately proves strict Range/If-Range handling.
