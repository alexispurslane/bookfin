---
id: t9-dcld
status: in_progress
deps: []
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules]
---
# The app shell rebuilds only for the tab, sign-in and theme, and an account binding owns source binding

Rules: UI rule 1 (only controllers cause side effects). UI rule 3 (depend on the minimum). Engine rule 1 (run independent asynchronous work concurrently).

Breaks:
- lib/main.dart, _BookfinAppState._refresh: setState rebuilds MaterialApp every 30 seconds (_clock) and on every AppearanceController notification, save-state changes included. The theme changes only at sunrise, at sunset, on a mode change and on a platform brightness change.
- lib/main.dart, runBookfin: awaits appearance.restore, createDownloads, layout.restore and createCovers one after another before runApp. These steps are independent.
- lib/catalog/screen.dart, _CatalogHomeState._accessChanged and _bindDownloads: the shell widget binds Downloads, Playback and the reader to the account and the books. Binding is a side effect, and the shell is not a tab or page controller.
- lib/catalog/screen.dart, CatalogHome.build: wraps DownloadsPage in a ListenableBuilder on the catalog, the layout and Downloads, so each byte notice rebuilds the Downloads tab. It wraps SettingsPage in a ListenableBuilder on the catalog and the layout.
- lib/main.dart, _AppearanceSheet: a widget that calls appearance.selectMode and selectLocation and pushes CitySearch.
- lib/catalog/screen.dart, _LibraryTab: it lives in the shell file, so the library ticket cannot change how it uses LayoutToggle.

Target design:
- AppearanceController (lib/appearance/preferences.dart) owns the theme decision. It exposes a ValueListenable<AppearanceDecision> that changes only when the brightness or the description changes. It sets its own timer for the next sunrise or sunset. The shell reports platform brightness and lifecycle changes to it. MaterialApp listens only to the decision and to the reduced-motion flag.
- runBookfin starts the independent restores together with Future.wait. Playback still waits for Downloads. Extract the startup into a function that a test can call with fakes.
- A new AccountBinding (lib/app/account_binding.dart) owns binding. It listens to the catalog's session, access and books, selected by identity as today. It binds Downloads, then Playback, then the reader, with today's generation check. main creates it. The shell keeps only the navigation that follows an account change: the tab reset and popUntil.
- The shell calls stable tab entry widgets: LibraryTab (moved from _LibraryTab into lib/catalog/library_view.dart), DownloadsTab(services) in lib/downloads/screen.dart, and SettingsTab in lib/settings/screen.dart. In this ticket each entry wraps today's page with today's listeners. The tab tickets then change only their own files.
- The appearance sheet content becomes a leaf that reports onMode, onChooseCity and onRemoveLocation. A showAppearance function on the controller side wires them, as changeDownload does for downloads.

Owned files: lib/main.dart, lib/catalog/screen.dart, lib/appearance/preferences.dart, lib/appearance/appearance.dart, lib/app/account_binding.dart (new), and their tests. This ticket also adds the entry widgets to lib/catalog/library_view.dart, lib/downloads/screen.dart and lib/settings/screen.dart, with no other change to those files. No other ticket in its wave owns those three files.

## Acceptance Criteria

- With a fake clock, 30 minutes without a sunrise or sunset rebuild nothing above the tab pages. A passed sunset rebuilds the theme once.
- An appearance save-state change does not rebuild MaterialApp.
- AccountBinding: a new book list binds Downloads, then Playback, then the reader. A stale binding stops. An account change unbinds Playback and the reader first. The current catalog/screen tests for these behaviors pass.
- The startup function, called with fakes, starts every independent restore before the first one completes.
- The appearance sheet leaf calls no AppearanceController method (a fake that throws proves it).

