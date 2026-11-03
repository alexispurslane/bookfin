# Corrected format-routing Android artifacts

Source 44d53afbe491f28cec0205584ba7f023ec8a10b6, independently source-reviewed.
Normal build through `nix develop --command bash tool/bookfin build-android`
succeeds; verifier checks 29 notices and exact pinned PDFium bytes.

Normal: .cache/artifacts/bookfin-44d53af-formats.apk, 159289190 bytes,
SHA-256 f062456644d1c6e8829b289d130e6047e582eb7fd67b139b1b7263be926615e7.
Matching clean-tree source export: .cache/artifacts/bookfin-44d53af-source/.
Source and dependency hashes are in source-manifest.json.

Same-debug-key modified-library companion:
.cache/artifacts/bookfin-44d53af-replacement/bookfin-replacement.apk,
SHA-256 e5bdcd3bacfe9f06233c4f845fa56af54e24d19cd0c0cfce9d2479a5506d44f9.
Host KF8 conversion, APK signature/alignment and package comparison pass;
only lib/arm64-v8a/libmobi.so differs among application entries. Exact commands
and proof are retained in replacement.txt. Neither APK installed by parent.
No runtime/native replacement/compliance acceptance inferred from preparation.
