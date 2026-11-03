# Bookfin Storage local deployment candidate

Ticket: `t6-il6y`. This package is not a published production release.
Do not install it on a live server without parent and user approval.
Package creation does not establish Android acceptance or deployment acceptance.

## Tested server and package identity

The disposable proof runs Jellyfin `12.4.0` on Apple Silicon macOS.
The build uses .NET SDK `10.0.401` and targets `net10.0`.
Other server versions, operating systems, and architectures remain untested.
The DLL contains managed code, but that alone does not prove cross-platform compatibility.
The package does not include a Jellyfin server or its dependencies.

| Property | Preserved value |
| --- | --- |
| Plugin identifier | `55fb5a92-7fbd-411c-9838-6ee4c88d168b` |
| Assembly filename | `Bookfin.Storage.dll` |
| Candidate assembly version | `0.1.1.0` |
| Previous research assembly version | `0.1.0.0` |
| HTTP address | `/BookfinStorage/v1/objects` |
| Database filename | `bookfin-storage-v1.sqlite` |

The display name changes from `Bookfin Storage Research` to `Bookfin Storage`.
The identifier, database, schema, and HTTP contract do not change.
The storage and controller source move here without logic changes.
The research tests and app tests build this same source.

`meta.json` contains `targetAbi: 12.0.0.0`, the Jellyfin loader compatibility field.
That field is not a tested server-version range.
Only Jellyfin `12.4.0` was exercised for this candidate.
Do not infer compatibility with `12.0`, `12.3`, later versions, or a different .NET runtime.

## Build and reproduce

Run from the checkout root on Apple Silicon macOS:

```sh
nix develop ./tool/research/sync --command bash -c '
  set -e
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tool/plugin -p "test_*.py" -v
  PYTHONDONTWRITEBYTECODE=1 python3 tool/plugin/package.py
'
```

The pinned shell supplies every build tool.
`tool/research/sync/flake.lock` pins nixpkgs.
`tool/research/sync/sources.json` records the server archive URL and SHA-256 hash.
A SHA-256 hash identifies the exact bytes of a file.
The builder rejects an unexpected SDK version or server assembly hash.
The builder uses the Jellyfin assemblies directly, without extra NuGet packages.
Build processes do not use persistent compiler servers.

The default output directory is `.cache/plugin/package/`:

| File | Contents |
| --- | --- |
| `Bookfin.Storage_0.1.1.0.zip` | DLL, Jellyfin metadata, and exact source/hash manifest |
| `Bookfin.Storage_0.1.1.0.sources.zip` | Every build script, C# source, project file, and Nix pin needed to rebuild |
| `Bookfin.Storage_0.1.1.0.sha256` | Hashes for both ZIP files |

The package manifest records every source hash and every referenced Jellyfin assembly hash.
It also records the DLL hash, metadata hash, SDK version, and server archive pin.
ZIP entry order, timestamps, and permissions are fixed.
Compiler source paths use one fixed prefix.
The proof compares two builds with separate output and intermediate directories.

To reproduce from the source ZIP, extract it into an empty directory.
Run the same `nix develop ./tool/research/sync` package command there.
The source ZIP intentionally contains build inputs, not the Flutter app or proof tests.
Compare the resulting package hash with the original `.sha256` file.
The `.sha256` file proves byte equality, not publisher identity.
Signing and distribution remain user decisions.

## Installation procedure after approval

This section documents a manual procedure. No script installs on a live server.
First rehearse the procedure on a disposable copy of the intended server version.

The program-data directory is Jellyfin's writable server-state directory.
It is the directory supplied by `--datadir`, not the server executable directory.
Jellyfin reports its actual paths in its startup log.
The plugin directory is `plugins/` inside that program-data directory.
The plugin database uses Jellyfin's `IApplicationPaths.DataPath` directory.
In the disposable fixture, the database is `data/bookfin-storage-v1.sqlite` inside the program-data directory.
Do not create a replacement database if you cannot find the existing database.

1. Confirm the exact Jellyfin version and installation owner.
2. Obtain approval for that server and package hash.
3. Stop that Jellyfin service with its normal service manager.
4. Make the stopped backup described below.
5. Verify both ZIP hashes against the approved `.sha256` file.
6. Extract the package ZIP into `plugins/Bookfin Storage_0.1.1.0/` inside the program-data directory.
7. Give the Jellyfin service account read access to those three package files.
8. Preserve the existing service account's write access to the database directory.
9. Start Jellyfin with its normal service manager.
10. Confirm one active `Bookfin Storage` plugin with the preserved identifier and version `0.1.1.0`.
11. Confirm ordinary-account Bookfin sync and record discovery without changing server or user identities.

Do not replace Jellyfin's own DLLs with files from this plugin package.
Do not install both research and candidate directories at once.
Do not remove Bookfin client databases or clear pending changes to fix installation problems.
If loading fails, stop the service and preserve the private logs for diagnosis.
Use the rollback procedure rather than creating a new database.

## Backup and restore

A stopped backup is a copy taken after Jellyfin exits.
Use it to keep related server files from different moments out of one restore.
The backup must include these items:

| Item | Why it is required |
| --- | --- |
| Whole Jellyfin program-data directory | User identifiers, server identity, plugin binaries, and plugin database |
| Separate Jellyfin configuration directory | Configuration files supplied by `--configdir` |
| Plugin package ZIPs and their hashes | Exact software needed for rollback |
| Existing Bookfin client storage | Local records and pending changes that are not yet on the server |

Keep the database with its `-wal` and `-shm` files if those files remain after shutdown.
Do not copy only the main SQLite file while Jellyfin writes to it.
For a live database backup, an administrator needs a separate, validated SQLite backup procedure.
That live procedure is not proved here.

Keep backups private and encrypted where appropriate.
Server backups contain account information and authentication material.
Plugin payloads are plaintext personal records, not end-to-end encrypted data.
Jellyfin administrators and filesystem owners can read the database.
Keep access to the API behind authenticated HTTPS outside the local fixture.

To restore, stop Jellyfin and preserve a separate copy of the failed state first.
Restore the complete matching program-data and configuration backup with its original file ownership.
Start the matching Jellyfin version and original plugin package.
Confirm server identity, user identities, plugin version, and record discovery before clients reconnect.

Do not clear or roll back client storage merely because the server was restored.
Clients can contain later offline changes that the server backup does not contain.
The proof restores a stopped server snapshot and checks its complete original inventory.
It does not prove automatic reconciliation between restored server state and later client activity.
Coordinate that recovery before reconnecting clients.

## Upgrade procedure after approval

The proved transition is research `0.1.0.0` to candidate `0.1.1.0` on the same Jellyfin `12.4.0` server.
It does not upgrade Jellyfin or migrate the database schema.
The database path does not depend on the plugin display name or version directory.

1. Retain all Bookfin clients, local records, and pending changes.
2. Stop Jellyfin and make a complete stopped backup.
3. Move the previous Bookfin plugin directory outside Jellyfin's `plugins/` directory.
4. Install the verified candidate package in its version directory.
5. Keep `bookfin-storage-v1.sqlite` and its directory in place.
6. Start the same Jellyfin version with the same program-data and configuration directories.
7. Confirm exactly one active plugin with the preserved identifier.
8. Confirm existing ordinary-account records before uploading new records.
9. Reopen Bookfin clients and confirm pending uploads, deleted records, and unresolved resume conflicts.
10. Make a fresh stopped backup after confirming the upgrade.

The upgrade does not expire history or remove superseded actions.
A deletion marker prevents an old object from being uploaded again.
The app also retains immutable journal actions, including actions that delete visible records.
Removing a visible bookmark is not a promise to erase every historical payload from server storage or backups.
Journal growth remains tracked by `t6-t9po`.

For rollback, restore the matching stopped backup and original package.
Do not downgrade arbitrary future database schemas with the old DLL.
Do not delete user records, deletion markers, or pending actions to reduce storage.

## Disposable proof

Prepare the Flutter dependencies, then run the bounded proof:

```sh
nix develop --command flutter pub get
nix develop ./tool/research/sync --command bash -c '
  PYTHONDONTWRITEBYTECODE=1 python3 tool/plugin/prove.py
'
```

The proof accepts no external server address or credentials.
It reserves loopback ports `7464` and `7465` before creating a fresh server.
It never uses Android, the Device panel, or ports `7364` and `7365`.
Every server process belongs to the proof and stops in cleanup.
Private disposable state remains under ignored `.cache/plugin/` with restricted file permissions.
Successful runs write sanitized `tool/evidence/plugin/packaging.json`.

The proof covers these behaviors:

1. Two clean builds produce identical package and source ZIP bytes.
2. The installable candidate passes the existing 21 storage and pending-action tests.
3. The original research DLL loads from source taken from commit `a0b3155`.
4. Two durable SQLite clients create concurrent records through the existing Flutter HTTP transport.
5. One client retains an offline pending bookmark while the server plugin changes.
6. Every object, sequence, payload, deletion marker, and client database remains unchanged across replacement.
7. Reopened clients upload the pending bookmark and retain audio, reading, history, deletions, and resume conflicts.
8. Choosing a resume position keeps both conflicting positions as bookmarks.
9. Ordinary-account isolation and authentication remain enforced before and after upgrade.
10. Restart preserves the new records and the existing app integration test passes.
11. Restoring the stopped server backup recovers the original package and complete original inventory.

The proof does not cover physical Android behavior, host power loss, disk exhaustion, or lifetime storage limits.
It does not establish compatibility with other Jellyfin versions or grant live deployment approval.
