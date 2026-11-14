# Bookfin

Bookfin is an Android app for audiobooks and ebooks on a Jellyfin server.
It keeps a copy of the library on the phone and works offline.
The landing page is [`index.html`](index.html).

## Features

- Library: a grid or list of books, series as stacked cards, filters, and search. An audiobook and its ebook show as one book.
- Downloads: separate audio and ebook downloads, Wi-Fi only by default, resumed after an interruption, and checked when complete.
- Player: chapter marks, bookmark marks, speed from 0.5× to 3×, a sleep timer, and lock screen controls. Playback uses downloaded files only.
- History: every pause, seek, chapter jump, and bookmark is a timeline entry. Undo after a seek or a chapter jump. Going back adds an entry and erases nothing.
- Reader: EPUB, unencrypted MOBI, and PDF. A PDF shows original pages or reflowed text. Scanned pages get on-device OCR (optical character recognition) with Tesseract, English only.
- Offline start: the app shows the cached library first and refreshes from Jellyfin in the background.
- Appearance: a day theme and a night theme. Night starts at local sunset for a city that you choose.
- Sync: playback progress goes to Jellyfin. Bookmarks, history, and reading places go to the Bookfin Storage plugin. Without the plugin, records stay on the phone.

## Requirements

- A build host with Nix and flakes: an Apple Silicon Mac, an x86_64 Linux computer, or WSL2 on an x86_64 Windows computer. The flake pins Flutter, Dart, Java, the Android SDK and NDK, and the native reader libraries.
- A 64-bit ARM Android phone or emulator.
- A Jellyfin server. The plugin was tested only with Jellyfin 12.4.0.

## Download the app

Download the newest signed APK from the [releases](https://github.com/alexispurslane/bookfin/releases/latest) on your phone, then open it to install it.

To get updates, add Bookfin to [Obtainium](https://obtainium.imranr.dev/), an app that installs and updates apps from their release pages. On your phone, open [Add to Obtainium](https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/alexispurslane/bookfin), or add the source `https://github.com/alexispurslane/bookfin` in Obtainium by hand. Each release carries one APK, `bookfin.apk`, and its tag matches the app's version, so Obtainium finds updates without a configuration.

## Publish a release

Push a version tag. The release workflow (`.github/workflows/release.yml`) builds the signed arm64 APK and publishes it as a GitHub release:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow runs `tool/release/build-release-apk.sh`, which you can also run locally in the dev shell. The release key stays out of the repository. Locally, the dev shell reads it from `~/.config/bookfin/release-signing.properties`. In GitHub, the secrets `BOOKFIN_RELEASE_KEYSTORE_BASE64` and `BOOKFIN_RELEASE_KEYSTORE_PASSWORD` hold it.

## Build and install the app

Run these commands from the checkout root:

```sh
nix develop --command flutter pub get
nix develop --command bash tool/bookfin test
nix develop --command bash tool/bookfin build-android
adb install build/app/outputs/flutter-apk/app-debug.apk
```

The first command downloads the pinned tools.
The build makes a debug APK.
In the app, sign in with the server address, your Jellyfin user name, and your password.

On WSL2, adb sees a USB phone only after you attach the phone to WSL with [usbipd-win](https://github.com/dorssel/usbipd-win).
The Linux shell has no Android emulator. The emulator runs on the Mac.
For the emulator and hot reload, read [`docs/setup.md`](docs/setup.md).

### Try it without a server

The fixture server is a small fake Jellyfin server with made-up books.
It listens on 127.0.0.1 only.

```sh
nix develop --command dart run tool/showcase_fixture.dart 8096
adb reverse tcp:8096 tcp:8096
```

In the app, sign in at `http://127.0.0.1:8096` with any user name and password.

### Run it on a Mac

The macOS desktop app needs Xcode from Apple, because Nix cannot supply it.
It signs in, shows the library, downloads and plays audiobooks, opens EPUB and PDF books, and syncs personal records.
It does not open MOBI books yet, and it does not recognize text on scanned PDF pages.
[`docs/plans/platforms.md`](docs/plans/platforms.md) lists each platform's state.

```sh
nix develop .#macos --command bash tool/bookfin run-macos
```

A locally built app has no stable signature.
After a rebuild, macOS asks once before the new build reads the saved sign-in.

## Build and install the Bookfin Storage plugin

The plugin stores bookmarks, history, and reading places for each Jellyfin user.
It keeps them as plain text in a SQLite database on the server, without end-to-end encryption.
It is not in a Jellyfin plugin repository.

Build the package from the checkout root:

```sh
nix develop ./tool/research/sync --command bash -c '
  PYTHONDONTWRITEBYTECODE=1 python3 tool/plugin/package.py
'
```

The package is `.cache/plugin/package/Bookfin.Storage_0.1.1.0.zip`.
The `.sha256` file next to it holds the hashes of the ZIP files.

Install it on the server:

1. Stop Jellyfin.
2. Make a backup of the Jellyfin program-data directory and the configuration directory.
3. Make sure that the hash of the ZIP file matches the `.sha256` file.
4. Extract the ZIP file into `plugins/Bookfin Storage_0.1.1.0/` in the program-data directory.
5. Start Jellyfin.
6. In the Jellyfin dashboard, make sure that Bookfin Storage 0.1.1.0 is active.
7. In Bookfin, open Settings, then Personal-record sync, then tap Sync now.

The program-data directory is the `--datadir` path. Jellyfin writes it in its startup log.
For backups, upgrades, and rollback, read [`plugin/Bookfin.Storage/README.md`](plugin/Bookfin.Storage/README.md).

## Project documents

- Product plan: [`docs/plans/bookfin.md`](docs/plans/bookfin.md)
- Approved design mockup: [`docs/mockups/bookfin.html`](docs/mockups/bookfin.html)
