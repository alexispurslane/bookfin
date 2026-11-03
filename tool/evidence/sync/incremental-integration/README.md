# Reviewed incremental-storage integration

Source: 4ae8c6c2299e7ec7c16420663a8fc305e87e6c9a.
Main's tree matches independently reviewed 53e4d57 exactly before this
evidence-only update. No conflicts and no additional production edits.
Retain the 425 passing tests, 3 opt-in skips, clean analysis and actual-plugin
proof from the candidate; no redundant full-suite execution.

Normal Android build through pinned Nix:

    nix develop --command bash tool/bookfin build-android

The package verifier checks all 29 native notices and exact pinned PDFium bytes.
Matching full source export: .cache/artifacts/bookfin-4ae8c6c-source/.
Exact source/archive hashes are in source-manifest.json.

No install/device work or Android performance/migration/process-death acceptance
is claimed. Earlier 27bf44e packages predate incremental storage and cannot
establish its acceptance. The device lane awaits renewed authorization.

Normal APK: .cache/artifacts/bookfin-4ae8c6c-incremental-sync.apk,
159290067 bytes, SHA-256
610fb123b835858d675302c550e4b6476ddfcd12372aaebac85a7f2f4b51f7ef.

Modified-library companion:
.cache/artifacts/bookfin-4ae8c6c-replacement/bookfin-replacement.apk,
SHA-256 3a1dd3864a5aa4361750b71430c626f4a3531e8eb056047ad7db7f86688f7849.
Preparation verifies host KF8 conversion, signatures, alignment and APK byte
comparison; only lib/arm64-v8a/libmobi.so changes among application entries.
This is preparation, not Android installation or compliance acceptance.
