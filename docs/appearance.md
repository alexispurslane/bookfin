# Appearance foundation

This foundation supplies typography, palettes, appearance choices, and a screen container that retains its child state.
The production entry point is `lib/main.dart`.
The development entry point is `lib/gallery.dart`.
The gallery labels all books, positions, chapters, and download states as samples.
It has no server connection, audio engine, ebook parser, or download manager.
Unavailable controls stay disabled rather than simulating production behavior.

## State ownership

`AppearanceController` owns the user's appearance choice and selected location.
`AppearanceStore` is the local storage boundary.
`LocalAppearanceStore` uses `SharedPreferencesAsync` and stores one versioned JSON record.
The Android preference dependency needs platform 35 in the pinned Nix SDK.
Bookfin itself still targets platform 36; the flake adds no API 35 emulator image.
Android backup is disabled so the selected location is not enrolled in Android cloud backup.

`resolveAppearance` derives appearance from the current instant, current system appearance, and the stored choice.
It does not store a second copy of the calculated appearance.
`BookfinApp` observes system appearance, accessibility changes, and application lifecycle changes.
Screen widgets own their own filters, scroll positions, and other view state.
`BookfinScreenStack` retains every screen in an `IndexedStack` while animating the selected screen.
Changing a palette does not replace the screen subtree.

Initialize and restore one controller before starting the application.
Pass that controller to `BookfinApp`; do not create another controller in a screen.
Future catalog, player, and reader screens can use the same theme without owning or copying appearance policy.
The gallery's reading size and scroll positions are demonstration state, not persisted ebook positions.

## Automatic appearance

Automatic appearance is the default.
Without a selected location, it follows the system and displays “System appearance · no location selected.”
With a selected location, calculation uses the instant in UTC and the location's latitude and longitude.
Latitude is measured in degrees north of the equator, from -90 to 90.
Longitude is measured in degrees east of Greenwich, from -180 to 180.
Time-zone offsets and daylight-saving changes do not alter sunlight at the same instant.
The device's local calendar date is not substituted for the selected city's date.
Calculating from the current instant also handles a changed date, a changed clock, a leap day, and a changed time zone.

The solar calculation uses NOAA-style Julian centuries, solar declination, and the equation of time.
Daylight begins when the center of the sun is at least 0.833 degrees below the geometric horizon.
This conventional threshold approximates the sun's apparent radius and atmospheric refraction.
Polar day means the sun remains above that threshold for the rotation at the current declination.
Polar night means the sun remains below that threshold.
The settings describe polar day and polar night explicitly.
Terrain, weather, and unusual refraction can change observed sunrise or sunset.
Do not treat this appearance calculation as a navigation or safety instrument.

Calculation runs at startup, on preference changes, on system appearance changes, and on resume.
While visible, a 30-second timer also recalculates it.
The timer stops when the app leaves the resumed state.
No background alarm, background location service, or exact-alarm permission is needed for a hidden interface.
After resume, appearance reflects the current instant immediately.
While visible, a sunlight boundary takes effect within 30 seconds of its calculated crossing.

Manual Day and Night choices override both sunlight and the system.
They keep the selected location, so returning to Automatic uses that location again.
Removing the location restores system fallback.

Calculation reference: `https://gml.noaa.gov/grad/solcalc/calcdetails.html`.
The implementation uses no astronomy package, location service, geocoder, or network request.
Behavior tests bracket independently known sunrise/sunset windows rather than repeating the solar formulas.

## Saving choices and invariants

Changes take effect before the local write completes.
Writes run in selection order, so a slow earlier write cannot overwrite a newer choice afterward.
Only the newest selection changes the visible save status.
A failed write leaves the current choice visible and shows “Appearance not saved. Choose again to retry.”
The next choice retries storage.
An unreadable or unknown stored record produces an explicit warning and automatic fallback.
It does not erase the unreadable record merely by loading it.

The controller's invariants are:

- A pending save has no save warning.
- A failed save always explains that the choice is not saved.
- The appearance choice is authoritative; brightness is always derived, never stored beside it.

`checkInvariants()` checks the status and warning relationship on demand in every build.
Internal notifications call it through a debug-only assertion.
Failed invariant checks are programming errors and are not recovered from.
Selected locations use always-on argument guards for finite, valid coordinates and a nonempty name.

## Motion and readability

The palettes follow `docs/mockups/bookfin.html`.
Headings use Outfit; book titles and reading text use Source Serif 4.
Full TrueType fonts and licenses live under `assets/fonts`.
The application uses Android's font fallback for characters missing from the bundled fonts.

Screen changes take 420 milliseconds, chapter panels take 360 milliseconds, and palette changes take 600 milliseconds.
Control feedback starts from 200 milliseconds.
Reduced motion removes application screen, panel, and palette movement.
Flutter's remaining native-style control fades settle within a rendered frame in the widget acceptance test.
The interface respects the platform text scale rather than capping it.

Directly interpolating a light palette into a dark palette makes foreground and background colors cross at low contrast.
`BookfinThemeTransition` instead animates surfaces and adjusts foreground colors to retain a 4.5:1 contrast ratio.
If intermediate surfaces straddle the narrow range where no shared foreground works, they briefly share the paper color.
Foreground colors can change more quickly near that boundary; surfaces still animate.
This intentional behavior avoids unreadable text halfway through a theme change.
Endpoint and transition tests check normal text, muted text, accent text, and filled controls.
Endpoint tests also require a 3:1 ratio for essential outlines.
Quiet separators are decorative, not the sole means of identifying a control.
`BookfinSurface` paints the background and supplies the default text style from the same palette frame.
Use it beneath a Material surface, including dialogs, instead of letting Material independently animate the default text style again.
During a palette change, button theme durations are zero so their colors do not lag behind that frame.
Press feedback still runs when the palette is stationary.
Tests inspect both resolved theme colors and the text color supplied to the rendered paragraphs.
The appearance-control test samples every 16 milliseconds through the transition.
These checks do not claim that every anti-aliased screen pixel meets a text contrast ratio.

## Pending production location input

Production location acquisition is not settled by the product plan.
The controller already accepts and persists a selected named location.
The gallery offers three explicitly labeled city fixtures solely to exercise that boundary.
The production screen keeps the honest no-location fallback and offers manual appearance choices.
Ticket `te-kzht` tracks the user choice and production input work.

| Design | Example | Benefit | Cost |
| --- | --- | --- | --- |
| Bundled offline city picker | Select New York, then Automatic | No permission or service | Dataset coverage, updates, and city search |
| Approximate device location | Grant approximate foreground location, then Automatic | Works away from listed cities | Permission flow and Android plugin support |

Both designs calculate sunlight locally, persist through the existing controller, and allow removing the selected location.
Neither design needs precise location or background access.
No remote lookup is part of either proposed design.
Do not silently treat a development city fixture as the production picker.

The `geolocator` package was assessed but not added.
Its Android documentation allows coarse location alone, reports city-block accuracy, and warns that a first coarse fix can take minutes.
It also supports settings and permissions that this ticket does not authorize, including fine/background location.
If the user chooses it later, declare only foreground coarse permission and test refusal and unavailable-service fallback.
Package documentation: `https://pub.dev/packages/geolocator`.

## Running the two entry points

Build the production shell:

```sh
nix develop --command flutter build apk --debug -t lib/main.dart
```

Build the labeled development gallery:

```sh
nix develop --command flutter build apk --debug -t lib/gallery.dart
```

Both entry points share `dev.bookfin.bookfin`.
Rebuild the desired entry point before installing; an existing APK can be the other entry point.
Install through the normal Nix Android tools, then launch through the current device-bound `agent-device` command with `--no-test-ime`.
Do not replace the project's six saved T3 scripts with worktree-specific gallery commands.
Debugger reattachment after replacing the APK remains ticket `t3-4isz`; detach if the stale-endpoint failure recurs.
Phone keyboard and browser acceptance remain ticket `boo-a4gi`.

The new browser gallery runs separately on loopback port 7358 during this ticket's review.
It does not replace the old setup shell on port 7357.
Both primary font files load from the local bundle in that browser gallery.
Flutter web also requests Roboto and Noto fallback fonts from its font CDN.
Ticket `te-6x43` tracks an offline browser fallback; do not claim that the current web renderer is fully offline.
The Android application uses installed system fallback fonts instead.
