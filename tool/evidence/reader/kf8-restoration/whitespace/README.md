# Preserve addressable whitespace

Correction base: 168b7af9de1bf239d9c82101aba82e5eca5e569a.

The review found that the exact-Alice correction skipped preserved whitespace. Three real-layout regressions in red.txt fail against that candidate: preformatted and pre-wrap destinations move from horizontal coordinate 17 to 841 CSS pixels; nonbreaking-space measurement moves from vertical coordinate 1 to 121 CSS pixels. These are browser layout coordinates, not physical-device pixels.

The correction uses the computed white-space style and only advances through ASCII characters that the style collapses. Preformatted content and nonbreaking spaces retain their addressed geometry. The same existing destination-measurement operation still owns restoration. Stored CFI, source identity, queue ownership and durable records are unchanged.

focused.txt records the engine rebuild and three passing whitespace regressions. engine.txt records all 38 engine tests passing, including exact-Alice restoration and existing layout/queue cases, plus verification of all four runtime assets. flutter.txt records the required environment checks and 431 passing Flutter tests with three existing opt-in skips. analysis.txt records final static analysis. The exact commands run through nix develop; no global toolchain was installed. git diff --check passes.

No APK, device acceptance, source integration, ticket closure, publication or coverage/mutation claim. Owned test browser processes and loopback fixtures finish through the existing test cleanup paths. The previous provenance file identifies the earlier candidate; hashes.json identifies this follow-up's source and generated assets.
