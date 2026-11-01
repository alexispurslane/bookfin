# Bookfin

Bookfin is an Android audiobook and ebook companion for Jellyfin.
This checkout contains a setup shell, not a working library or player.
The approved product plan is in `docs/plans/bookfin.md`.
The approved mockup remains in `docs/mockups/bookfin.html`.

## Development

Use the pinned Nix shell on an Apple Silicon Mac.
Run these commands from the checkout root.
The first command downloads the pinned Flutter, Dart, Java, and Android tools.
It also downloads an Android ARM64 emulator image.
No global toolchain installation is needed.

```sh
nix develop --command flutter pub get
nix develop --command bash tool/bookfin test
nix develop --command bash tool/bookfin analyze
nix develop --command bash tool/bookfin build-web
nix develop --command bash tool/bookfin build-android
```

The Android command builds a debug APK, an installable Android package.
It does not produce a signed release.
The output is `build/app/outputs/flutter-apk/app-debug.apk`.
The web output is `build/web`.

## Shared testing

Start the loopback-only web server, then open port 7357 through T3 Preview.
Loopback means that only this machine can connect directly.
Use T3's authenticated connection for remote viewing.
Do not bind the server to a public address.

```sh
nix develop --command bash tool/bookfin web
```

For Android setup, device control, and the hot reload fixture, read `docs/setup.md`.
The fixture is separate from the Bookfin boot shell.
It does not implement a product feature.

## Current limits

- No Jellyfin sign-in, catalog, download, reader, playback, or sync exists yet.
- The boot shell uses cream and sepia colors, but the full appearance ticket is separate.
- Phone viewing and input require the user to confirm the same T3 session on their phone.
