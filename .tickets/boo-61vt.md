---
id: boo-61vt
status: in_progress
deps: [boo-gxm8, te-kzht]
links: []
created: 2026-11-01T22:02:10Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Implement cream sepia typography motion and sunset appearance

Preserve the approved mockup structure nearly exactly. Implement cream and sepia day colors, warm dim night colors, Source Serif 4 reading text, Outfit headings, airy rounded controls, smooth transitions, and automatic local sunset/sunrise switching. Keep a manual override and an explicit system-theme fallback when no location is available.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Review day and night on Android and the shared T3 Device panel. Bundle fonts with licenses. Preserve feature layout and reading positions. Meet text/control contrast targets and respect reduced motion. Test sunset/sunrise, fallback, manual overrides, date/time-zone changes, and polar cases.


## Notes

**2026-11-01T23:32:51Z**

Implementation underway in assigned checkout. Meaningful red tests observed for missing appearance decisions (9 failed), preference persistence/order/failure handling (5 failed), and midway palette contrast. Pure NOAA-style UTC solar calculation now covers selected locations, date/DST boundaries, both polar seasons; automatic fallback is explicit. Production acquisition fork raised: offline selected city vs approximate foreground device location. Shared controller and development city fixtures proceed independently. No location plugin/permission/network service added.

**2026-11-02T00:20:17Z**

Implemented bundled full TrueType Outfit/Source Serif 4 and licenses, approved day/night palettes, contrast-preserving palette frames and painted text surfaces, retained-screen navigation, reduced motion, and local serialized appearance preferences. Added honest disconnected production shell plus explicitly labeled development library/player/reader fixtures; no Jellyfin/audio/ebook engine. Added pinned API 35 platform only for the shared_preferences native dependency; no global SDK overwrite or location permissions/plugin. Final Nix verification: SDK-link safety test and 31 Flutter tests pass, analyzer clean, production and gallery debug APKs built. Added a rendered-paragraph regression after Android recording exposed Material default-text fading; fixed it before the final builds. Scroll retention assertion also passes. Android day/night, Night after relaunch, New York/Tokyo automatic decisions, multilingual fallback, accessibility-large text, and animations-off controls observed. Broader coverage/mutation left to parent. See docs/verification/boo-61vt.md and docs/appearance.md.

**2026-11-02T00:20:17Z**

Pending product choice is tracked in te-kzht: bundled offline city input vs approximate foreground location. The production shell keeps honest system fallback; city buttons are development fixtures only. Browser gallery serves only loopback 127.0.0.1:7358, separate from untouched old 7357 shell. Browser hot reload observed at 681 ms; Flutter web fallback fonts still use its CDN, tracked in te-6x43. Android debugger attempt was bounded and detached after slow VM-service warnings; no Android hot reload claim and t3-4isz remains open. Phone keyboard/browser acceptance remains boo-a4gi. Ticket intentionally remains in_progress for parent review and integration.

**2026-11-02T00:34:02Z**

Final acceptance suite expanded to 32 passing Flutter tests, including explicit reading scroll-offset retention and updating an open polar explanation after a date change that keeps night appearance. Latest test/analyzer log: /tmp/bookfin-61vt-final-checks.log; analyzer clean. Production code is unchanged from the successful production/gallery APK builds. Active review handles, local evidence paths, API limitations, and follow-up ticket IDs are recorded in docs/verification/boo-61vt.md. No ticket was closed.

## Parent review corrections

Partial foundation integration only; ticket stays open. F1 reproduced painted navigation contrast near 2.0:1 against the required 4.5:1. Removed screen fading while retaining slide motion; regression samples rendered text with ancestor opacity in both palettes. F3 restores disabled chapter Jump/history Restore actions and the reader Audio stays close panel with working gallery-only Player navigation. F2 remains original implementation work in te-kzht: dependency reversed so city selection gates this ticket, and no new permission gate applies. Browser fallback-font work te-6x43 now gates release hardening.

Parent verification through nix develop: SDK-link safety checks and all 34 application tests passed. The retained-reading test now uses a visible nonzero scroll position after the restored panel lengthened the page. Root analysis initially discovered standalone research packages without their independent dependencies; root analyzer now excludes tool/research/readers, whose dedicated commands remain documented. Final flutter analyze has no issues. No new Android build or device inspection claimed for parent fixes.
