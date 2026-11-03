# KF8 character restoration host evidence

Ticket: `t2-42og`. Parent: `a22e0b865a4fe70848849bdd539bad0b9bd4f224`.
The explanation and remaining Android acceptance are in
`docs/evidence/reader/kf8-character-restoration.md`.

## Results

| Evidence | Result |
| --- | --- |
| `red-exact-corpus.txt` | Unchanged parent engine assets. Ordinary Next passes. Six restoration cases fail on the actual visible-passage assertion. |
| `layout-green.txt` | All 20 layout-runner tests pass, including the seven Alice behaviors and all prior startup/resource/queue regressions. |
| `engine-green.txt` | All 35 JavaScript-runner tests pass. The Alice fixture also runs the production Dart importer and admission. |
| `flutter-reader-green.txt` | All 68 focused Flutter reader tests pass. |
| `flutter-full-suite.txt` | All three environment scripts pass. 431 Flutter tests pass. Three existing opt-in cases are skipped. |
| `flutter-analysis.txt` | No issues found. |
| `format.txt` | One Dart file checked, zero changes. |
| `asset-verification.txt` | All four runtime asset hashes match the manifest. |
| `exact-fixture-green.txt` | Standalone exact-archive fixture passes, including original, edition, converted SHA-256 and admitted-resource equality. |
| `corpus.json` | Source, converted archive, edition identity and package path from the successful fixture. |

The three skipped cases require optional external inputs. They are journal
growth measurement, live storage-plugin integration, and storage-plugin
upgrade integration. This task does not start or install a live server.
The existing Nix native hooks report unavailable iOS SDKs. The native-tool
script also deliberately exercises invalid signatures and unsupported flags.
These expected diagnostics are not Android runtime proof.
The analysis transcript omits trailing terminal padding.

## Commands

Every build and test command runs through the existing project Nix shell.
Set `CHROME_BIN` if Chromium is not at the existing default macOS path.
No global toolchain or browser installation is required or performed.

```sh
nix develop --command flutter pub get
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && npm ci --no-audit --no-fund'
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && npm run build && npm run verify'
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && node --test test/layout.test.cjs'
nix develop --command flutter test --no-pub test/reader --reporter expanded
nix develop --command bash -c 'cd packages/flutter_epub_viewer/engine && npm test'
nix develop --command bash tool/bookfin test
nix develop --command bash tool/bookfin analyze
nix develop --command dart format --output=none --set-exit-if-changed tool/reader/kf8_layout_fixture_test.dart
```

To repeat the red run, export `epub.js` and `reader.js` from the parent commit
into an ignored directory. Set `BOOKFIN_TEST_ASSETS` to that directory's
absolute path. Run this command in the Nix shell from the engine directory:

```sh
node --test --test-name-pattern='converted Alice' test/layout.test.cjs
```

The candidate assets are not replaced during the red run. The fixture uses
temporary directories and removes them after the run. All HTTP test listeners
bind to `127.0.0.1`. Browser processes and listeners close before handoff.
No APK build, device action, interactive browser action, coverage, mutation,
account-record rewrite, ticket closure, or PR occurs in this task.
