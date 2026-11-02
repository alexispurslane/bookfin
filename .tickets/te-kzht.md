---
id: te-kzht
status: in_progress
deps: []
links: []
created: 2026-11-01T23:32:51Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement offline production city selection

The approved plan authorizes selected-city input. No new user decision is required. Implement a useful searchable offline city selection with documented dataset provenance and coverage through the existing appearance controller. Approximate foreground location can remain a later enhancement; do not request precise/background location or use remote lookup. This ticket completes original boo-61vt acceptance and gates it.

## Acceptance Criteria

Production users can search, select and remove a city. Selected coordinates persist through the existing controller and drive local sunrise/sunset appearance. Removal restores explicit system fallback; manual overrides remain. Validate input, distinguish same-name cities, document dataset coverage/license and test selection, persistence and Android interaction. Correct obsolete approval-gate claims in UI/docs.

## Notes

**2026-11-02T01:25:07Z**

Implemented the approved production offline selected-city route from 3f84b54. Bundled reduced GeoNames cities15000: 34,195 places, 244 country/territory codes, 2,395,206 bytes; attribution, full CC BY 4.0 license, pinned source hashes, coverage and regeneration procedure documented. Search/selection/removal use the existing AppearanceController and appearance record; no parallel preference, location permission, remote lookup or background service. Meaningful red: four production tests failed on absent city chooser; invalid catalog input returned a catalog before guards. Green: nine focused tests, all 43 app tests plus SDK-link safety, clean analyzer, formatting/regeneration checks and production ARM64 debug APK build/install. Android production search, same-name distinction, ASCII names, selected-city relaunch persistence, Springfield night/Tokyo daylight, manual Night relaunch persistence, removal retaining manual Night and persisted Automatic system fallback observed. Earlier device-owner conflicts resolved only by their owners. One relaunch diagnostic retry succeeded. Own device session released with shutdown:false; emulator preserved. Evidence: docs/verification/te-kzht.md. No browser servers touched, no reader/navigation scope added, no postacceptance coverage or mutations run. Leave in_progress for parent review/integration; boo-61vt remains dependent.
