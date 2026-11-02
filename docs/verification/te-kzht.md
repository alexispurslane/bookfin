# Production city selection verification

Date: November 1, 2026, America/New_York. Android inspection finished at approximately 20:23 EST.
Base: `3f84b54`, the integrated appearance foundation with the navigation contrast and gallery-control corrections.
Branch: `t3/offline-city-sunrise`.
Checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-49ef0401`.
This records implementation evidence, not user acceptance, parent integration or ticket closure.

## Automated evidence

All formatting, generator, test, analysis and build commands ran through the pinned Nix development shell.
The full application suite ran once after the final code changes. It was not repeated after device-owner interruptions or documentation-only changes.

| Check | Command | Observed result |
| --- | --- | --- |
| Focused city behavior tests | `nix develop --command flutter test test/appearance/cities_test.dart test/appearance/production_city_test.dart` | All 9 passed |
| Full application tests and SDK-link safety | `nix develop --command bash tool/bookfin test` | All 43 Flutter tests passed. SDK-link safety script passed |
| Root application analysis | `nix develop --command flutter analyze` | No issues found |
| Production Android ARM64 debug build | `nix develop --command bash tool/bookfin build-android -t lib/main.dart` | Initial build passed in 196.6 seconds. Final asset-only rebuild passed in 12.1 seconds |
| Formatting | `nix develop --command dart format --output=none --set-exit-if-changed lib/appearance/cities.dart lib/appearance/city_search.dart lib/main.dart test/appearance/cities_test.dart test/appearance/production_city_test.dart tool/prepare_cities.dart` | No changes needed |
| Source-to-asset regeneration | `nix develop --command dart run tool/prepare_cities.dart /tmp/bookfin-cities` followed by comparison with the committed asset | Byte-identical output |

The root analyzer excludes the independent reader research packages, as in the supplied base.
No independent reader package was changed or retested.
Flutter reported five newer package versions outside the current dependency constraints. Dependencies and locks were not upgraded for this ticket.

The production artifact is `build/app/outputs/flutter-apk/app-debug.apk`.
Its final SHA-256 is `92756ecaa7bca354ada55726288babb091189b395444b6a90f97036171740545`.
It uses `lib/main.dart`, not the design gallery entry point.
The installed and inspected APK had SHA-256 `8a92bd30adec4374aa5522b68b88f411d7d73a0d898be55deb8280a30cbd22ec`.
Installation with `adb install -r` succeeded through `nix develop`.
After device release, the final rebuild removed only an extra blank line at the end of the bundled license text.
Application code was unchanged. The final asset-only rebuild was not reinstalled, and the unchanged full test suite was not repeated.
The APK is a debug build, not a signed release.

Local logs are retained outside version control:

| Path | Evidence |
| --- | --- |
| `/tmp/te-kzht-red.log` | Four meaningful initial production failures because Choose city was absent |
| `/tmp/te-kzht-data-red.log` | Invalid dataset behavior failed because invalid input returned a catalog instead of a format error |
| `/tmp/te-kzht-city-green.log` | All nine focused city tests passed |
| `/tmp/te-kzht-full-tests.log` | Full application suite and SDK-link safety |
| `/tmp/te-kzht-analysis.log` | Clean root application analysis |
| `/tmp/te-kzht-android-build.log` | Successful production APK build |
| `/tmp/te-kzht-android-final-build.log` | Successful final asset-only APK rebuild |
| `/tmp/te-kzht-relaunch-debug.log` | Successful single diagnostic retry of a device-command relaunch |

The production widget tests load the actual bundled GeoNames extract before testing the interface.
A test-only asset bundle supplies that text synchronously so Flutter's simulated test clock does not wait on background UTF-8 decoding.
Search, selection, the appearance controller and the solar calculation are real application code, not mocked decisions.
Widget tests bracket New York sunset on March 20, 2026, and sunrise on March 21 with a controlled clock.
They also restore a new controller from the stored record, remove a selected city, retain a manual override, and return to explicit system fallback.
Catalog tests cover region/country filtering, ASCII spellings, duplicate labels, ordering, bounded results, invalid data and the full bundled extract across six continents.

The integrated navigation-opacity and missing-gallery-control regression tests remain green in the full suite.
Their implementation was not changed. No production reader or navigation redesign was added to this city task.

## Android observations

Device: host `local`, device `emulator-5554`, virtual device `bookfin-api36`.
The app was opened and controlled only through this task's `device_open` binding, session `t3-149c7a5b78046065946b77d6`.
Launches used `--no-test-ime`, so the real Android keyboard remained visible during search.
Screens were inspected with T3 `device_screenshot` and screenshots from the same bound command.

Observed in the installed production app:

- Appearance offers Choose city without a development-gallery gate or permission request.
- Searching Springfield shows separate Missouri, Massachusetts, Illinois, Oregon and Ohio results with region and country labels.
- Searching Springfield Illinois narrows the list to the Illinois result.
- Selecting that result shows After sunset for Springfield, Illinois, United States in Automatic mode.
- A process relaunch retains the selected Springfield and its automatic after-sunset appearance.
- An unknown query shows No matching city rather than creating a free-text location.
- The ASCII query sao paulo finds São Paulo, São Paulo, Brazil.
- Selecting Tokyo from tokyo japan shows Daylight for Tokyo, Tokyo, Japan and the day palette at the same review time.
- Manual Night overrides Tokyo daylight. A process relaunch retains manual Night and the selected Tokyo.
- Remove selected location clears Tokyo while retaining manual Night.
- Selecting Automatic after removal shows System appearance with no location selected. A process relaunch retains that fallback.

Final application state: Automatic, no selected city. No Android appearance, connectivity, animation or permission setting was changed.
No visual overflow was observed at the emulator's existing text scale with the real keyboard open.
This is not a complete accessibility audit or a physical-phone acceptance claim.

Screenshots are local ignored artifacts under `.cache/city-evidence/` in this checkout:

| File | Evidence |
| --- | --- |
| `production-fallback.png` | Production Appearance with system fallback and Choose city |
| `springfield-search.png` | Same-name cities distinguished with region and country, real keyboard visible |
| `springfield-selected.png` | Selected city drives automatic after-sunset appearance |
| `springfield-relaunch.png` | Selected city persists across process relaunch |
| `no-match.png` | Unknown query does not offer a selectable location |
| `sao-paulo-search.png` | ASCII query finds the accented city name |
| `tokyo-daylight.png` | Selected Tokyo drives automatic daylight appearance |
| `manual-night-relaunch.png` | Manual Night persists across process relaunch |
| `removed-manual-night.png` | City removal preserves the manual override |
| `removed-system-fallback.png` | Automatic returns to explicit system fallback after removal |
| `fallback-relaunch.png` | City removal persists across process relaunch |

## Device-command limits and cleanup

Earlier inspection attempts stopped at DEVICE_IN_USE for sessions owned by other tasks.
Only those owners released their sessions. This task did not borrow or close them.
After release and reservation, this task acquired its own binding and completed the observations above.

One relaunch returned `Android app dev.bookfin.bookfin remained foreground after close`.
The command advised a diagnostic retry. The single retry with `--debug` succeeded, and the resulting snapshot confirmed persisted manual Night.
A bare connectivity-read command returned `settings wifi requires a state: on|off.`
Its usage was inspected, and connectivity was left unchanged. No radios-off smoke test is claimed.
The offline implementation uses only bundled data and local calculation. It adds no remote lookup or location permission.

After inspection, this task called `device_close` for `local/emulator-5554` with `shutdown:false`.
It returned `{}` without error, and this task's bound command was absent afterward.
The emulator and installed production APK were preserved for the next task.
Neither loopback preview server on port 7357 or 7358 was changed or used.

## Remaining limits and ownership

Dataset coverage, attribution, source hashes and the update procedure are in `docs/city-data.md`.
The list does not cover every village or alternate-language city name. Population is a ranking hint, not a current census claim.
Sunrise and sunset remain approximate, with the existing foreground refresh interval of up to 30 seconds.
No real-time sunrise or sunset boundary was observed on Android during this short inspection. Controlled application tests cover both boundaries.
The production shell still has no catalog, reader or playback implementation. The gallery remains only a design-language preview.

The parent owns postacceptance coverage, mutation testing, review, integration and ticket closure.
`te-kzht` remains `in_progress`, and `boo-61vt` continues to depend on it until parent integration.
