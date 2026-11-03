# Dedicated Jellyfin storage experiment

This disposable experiment supports boo-dez0, not production installation.
The one shared C# source now lives in `plugin/Bookfin.Storage/`.
Read `plugin/Bookfin.Storage/README.md` for candidate packaging and upgrade proof.
Historical evidence below describes the earlier research build, not a released plugin.
Read `docs/research/jellyfin-dedicated-storage.md` for results and limits.
Do not install this DLL on a production server.

Run from the checkout root on Apple Silicon macOS:

```sh
nix develop ./tool/research/sync --command bash -c '
  set -e
  mkdir -p .cache/plugin
  dotnet build plugin/Bookfin.Storage/Bookfin.Storage.csproj \
    -c Release -p:JellyfinDir="$BOOKFIN_SYNC_SERVER" \
    -o .cache/plugin/build --nologo
  PYTHONDONTWRITEBYTECODE=1 python3 tool/research/plugin/run.py
'
```

The existing research flake pins nixpkgs, .NET SDK 10.0.401, Python,
FFmpeg, and the official Jellyfin 12.4 macOS ARM64 archive.
The plugin references that archive's assemblies without extra NuGet packages.
No global installation or shell-profile change is needed.

The runner creates fresh synthetic administrator, Alice, and Bob accounts.
Alice and Bob are ordinary users. It accepts no external origin or credentials.
The server uses only `127.0.0.1:7464`, with HTTPS disabled on reserved port 7465.
Ports 7364 and 7365 are untouched. Enhanced is not installed.
No earlier fixture, app, device, browser, or production server is used.

Each run has its own `.cache/plugin/run-*/` directory. The runner stops
only its own child process, including after test failure. Waits are bounded.
Discovery stops after 128 requests and fails rather than accepting an incomplete
inventory. The suite includes three clean restarts and one forced process stop.

Successful runs write sanitized `evidence/runtime.json`. It records source and
DLL hashes, test outcomes, object counts, byte counts, restarts, and cleanup.
If private red-test logs exist under `.cache/plugin/`, it also retains their
failure headings and assertion messages. A fresh run need not have those
earlier captures. Committed evidence preserves the original red phases.

Passwords, tokens, databases, and server logs remain under ignored
`.cache/plugin/run-*/`. Directories have mode 0700; account files and
databases have mode 0600. Private state is retained, not automatically removed.
After the suite, neither experiment port has a listener.

The fixture sets `BOOKFIN_STORAGE_CHECK_INVARIANTS=1` for explicit database
checks when the store opens. `ObjectStore.CheckInvariants()` remains callable
in release builds and is not an HTTP endpoint. The local pending-action store
has its own explicit `check_invariants()` method.

Run the earlier research regression suite separately:

```sh
nix develop ./tool/research/sync --command bash -c '
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
    -s tool/research/sync -p "test_*.py"
'
```

The project test command remains `nix develop --command bash tool/bookfin test`.
Do not run coverage or mutation jobs from this experiment. Those remain
orchestrator-owned after user acceptance.
