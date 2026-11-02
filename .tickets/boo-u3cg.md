---
id: boo-u3cg
status: closed
deps: [boo-gxm8]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Build book catalog series and edition relationships

Implement sign-in, book-only library selection, cached browsing, source identities, edition relationships, series order, and explicit corrections.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Behavior tests cover account separation, single/multi-file audio, distinct recordings, ambiguous title matches, ebook pairing, and offline browsing.


## Implementation unblocked

Appearance foundation is integrated at 3f84b54; its remaining city input is independent of catalog behavior. Public and authenticated research establish useful Jellyfin catalog routes and bounded download behavior, with admin-only and absent-ebook limits. Full storage proof stays in boo-p58t and continues to gate sync. Ordinary-user, denied-download, multi-file ordering and ebook-pairing integration acceptance is preserved in boo-2cgp, which gates release hardening. Catalog implementation can use synthetic behavior fixtures while those deployment checks remain open. Do not claim research endpoint permission enforcement is correct until parent fixes review F1.

User clarified production UI: one navigation system, bottom navigation anchored to screen edge, no gallery development labels or explanatory filler, immersive reading with controls available on tap. Preserve approved feature structure and aesthetics; the development gallery is not the production layout contract.

## Notes

**2026-11-02T02:25:23Z**

Implementation is ready for parent integration from baseline e2f2b4e. Real HTTPS sign-in and book-only selection now feed one account-scoped, persisted catalog. Explicit book links, separate recordings/text editions, confirmed multi-file groups and order, fractional series corrections, source item/media-source identities, and distinct audio/text positions are implemented. Production has one screen-edge bottom navigation; unavailable media destinations are disabled. Appearance modules and the separate development gallery are preserved. Downstream contracts and verification are documented in docs/catalog.md.

Verification through the pinned Nix dev shell: flutter test --reporter expanded passed 94 tests; flutter analyze reported no issues; flutter build apk --debug passed; flutter build web --release passed. SDK platform 34 is now provided alongside dependency platform 35 and application platform 36 without adding emulator images or changing any shared SDK. The Java 8 dependency warnings and legacy secure-storage WebAssembly/font warnings did not block builds. Red-green evidence includes strict API fields, selected book-only Audio items, denied access, pagination completeness, stale account responses, cancelled refreshes, secure sign-out, invalid account switching, unreadable caches, ambiguous matching confirmation, replacement revisions, retained file order, dismissal of corrections after revoked access, and named recording choices with final confirmation.

No children, private credential files, live authentication, target-server writes, devices, preview servers, coverage, or mutation jobs were used. Android runtime/secure-store restart and authenticated acceptance remain for the parent; boo-2cgp still gates ordinary-user isolation, denied-download, real multi-file ordering, and ebook pairing. Full personal-record sync remains boo-p58t. Local sign-out does not revoke the remote Jellyfin token, and browser sessions intentionally remain memory-only. Follow-up t7-fyql tracks removing the temporary macOS native-hook dependency pin. Keep boo-u3cg in_progress until integration.

## Parent review corrections and integration

F1-F4 were each reproduced with a failing behavior test: denied cache reappeared after restart, permission recovery removed CatalogHome, removed recording anchor split survivors, and linking into separated Zebra retained Apple details. Account cache now encodes known denial; successful access refresh clears it. Recording links retain their saved identity without a live anchor. Linking captures chosen target details in existing corrections. Route dismissal occurs only for account changes or newly blocked access. F5 uses Source Serif 4 for book-detail titles.

Integrated current main city search, dataset/license, opaque route transitions and constrained-height fixes. Production-city tests now inject disconnected catalog storage and inspect appearance through its settings sheet, rather than relying on the removed setup-screen labels. Parent SDK-link checks and all110 application tests pass through nix develop. Deployment acceptance remains boo-2cgp; no parent live credentials or Android UI operation occurred in this correction pass.

Parent final verification: full analysis clean; Android debug APK and JavaScript web release build passed. WebAssembly remains unsupported by the dependency as documented. Live and Android runtime acceptance stays in boo-2cgp.
