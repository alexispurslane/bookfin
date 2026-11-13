---
id: boo-2gse
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Start the catalog restore before the other data sources open

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, size of the delay not measured. lib/main.dart:71-87 awaits `openSources` (appearance, Downloads, Playback with `AudioService.init`, covers) before `runApp`. `CatalogController` is built inside the widget tree (main.dart:260-269), so `restore()` starts only after that. The time to the saved library is the sum of the two, not the larger of the two. Build the controller in `runBookfin` with the other sources and start `restore()` before `await openSources`. Related: tf-mo5q, boo-8v53.

## Settled implementation scope, 2026-11-13

Parent inspection at `4c020d1e` confirms that the startup order still matches the finding. Start the existing local catalog restoration concurrently with opening the other data sources, before their completion can delay it. Hand the same controller and restoration work to the app; do not create a second catalog, restart restoration, duplicate refreshes, or add a second startup path. Keep one explicit owner for construction, lifetime and disposal. Preserve the existing caller-owned controller behavior used by tests and the gallery's avoidance of real account/server access.

Preserve cache-first display, the one-hour resume policy, expired-sign-in local access, account binding, and catalog-choice ownership. Inactive-account migration still waits until after the first frame and must retain its existing recovery notices and failure reporting. Catalog restoration, network refresh and migration retain their distinct dependencies: no network request or inactive-account migration may become a prerequisite for the first useful frame. Do not expand into the Android service-startup profiling or catalog-read profiling tickets, and make no measured Android speed claim.

Use the real startup coordination path in controlled tests. Prove a meaningful failure that the saved catalog cannot begin/complete while unrelated source startup is held; then prove it can after the fix. Cover the opposite completion order, exactly one restore/refresh, failed restoration or source opening, root disposal while work remains, supplied-controller ownership and gallery behavior where affected. Preserve local migration/notice tests and account/lifecycle tests. Avoid tests that exercise an unused helper instead of production startup. Extend the existing startup boundary only as required; no speculative bootstrap framework.

Primary ownership: `lib/main.dart`, `test/app/app_shell_test.dart`, `test/boot_shell_test.dart`, any narrow startup regression file and this ticket. Change catalog code only if its existing interface cannot support coherent ownership. boo-o3cm concurrently owns Downloads and AccountBinding; boo-3y46 owns remote record admission. Parent handles overlap. Read the integrated boo-jlhy, boo-7z9a and boo-721h behavior before moving startup code.

Required final checks through Nix: focused startup tests, `test/app test/catalog test/boot_shell_test.dart test/downloads test/playback test/sync`, affected analysis and formatting, and the full Flutter suite. Concurrency two; one heavy command at a time. Exactly one fresh read-only Astra reviewer at high; implementation and direct fixes use Astra at xhigh. No second reviewer, device work, browser work, coverage, mutations, deployment, push, PR or ticket closure. Parent owns integration, acceptance and hardening.
