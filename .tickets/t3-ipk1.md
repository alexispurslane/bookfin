---
id: t3-ipk1
status: closed
deps: [boo-73yj]
links: [boo-73yj, boo-mx5i, t3-jrhf, t0-ebxa, t2-42og]
created: 2026-11-02T10:46:17Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove libmobi Android redistribution and replacement compliance

Before shipping a libmobi-enabled Android APK, define and demonstrate the LGPL-3.0-or-later redistribution path for pinned libmobi 0.12 and the bridge that includes upstream mobitool.c. Merely putting libmobi.so in an APK is not the compliance proof. Research notice assets are not a complete release source or relinking offer.

## Design

docs/plans/bookfin.md; docs/research/reader-formats.md and the November 2 Android follow-up. Parent owns approval of the production package and license approach.

## Acceptance Criteria

Archive exact libmobi source, bridge modifications, toolchain pins and build scripts with LGPL and GPL texts. Provide applicable corresponding source/application code and required installation information. Demonstrate replacing/relinking an interface-compatible modified library, rebuilding/re-signing and installing the Android package without blocking ordinary reader operation. Review store/signing/reverse-engineering terms and retain PDFium/transitive license notices. Record a qualified compliance review before release.

## Notes

**2026-11-03T00:39:14Z**

Bounded packaging preparation starts after b81b472 while parent handles final sync R1/R2. Native notice test fails meaningfully before registry implementation; 29 exact upstream/native notice assets now load through the real Flutter license stream, including Latin-1 PDFium notices. Normal APK build pins/verifies Android PDFium bytes and all notice assets. Replacement preparation changes mobi_version marker in copied source, builds host/Android interface-compatible libraries, converts real pinned KF8 on host, and replaces only ARM64 libmobi.so in APK; v2/v3 signature and 16KB ZIP alignment verify. No device connection or install. Source export/build/install instructions prepared. Android ordinary reading after replacement and qualified compliance/distribution review remain mandatory, not bypassed.

**2026-11-03T00:40:52Z**

Source preparation milestone 4ee30c6 is committed. Clean-tree export succeeds: .cache/artifacts/native-reader-source/ contains complete Bookfin commit archive, exact libmobi source, complete LGPL/GPL texts and build/install instructions; SHA-256 inventory recorded separately in packaging/source-bundle.txt. Normal notice-complete APK .cache/artifacts/bookfin-4ee30c6-reader-notices.apk SHA256 fd5879f0672b73f8c1a8ff774e427214de3a38a26b71d92f47c67f81540dcaf3; replacement .cache/artifacts/native-reader-replacement/bookfin-replacement.apk SHA256 a2574c211f3c3ec73a469975ec418acd5702197e7cf4e7e3a1bb1d4a53316801. Parent alone coordinates review/install, no Android runtime or legal acceptance claim. Raw upstream notice bytes intentionally retain their whitespace.

**2026-11-03T14:16:49Z**

Renewed normal-app attempt verifies the exact 4ae8c6c source export hashes and normal installed APK 610fb123b835858d675302c550e4b6476ddfcd12372aaebac85a7f2f4b51f7ef. Ordinary MOBI Read fails before converter entry (t3-jrhf), so no normal MOBI bookmark/resume prerequisite can be established. Same-key companion SHA256 3a1dd3864a5aa4361750b71430c626f4a3531e8eb056047ad7db7f86688f7849 remains unchanged and uninstalled; installing it behind unreachable conversion would not prove modified converter loading. No EPUB/cache/private-state substitute, data reset, legal approval, or closure. Report docs/evidence/reader/android-normal-formats-20261103.md.

**2026-11-03T15:44:19Z**

Same-debug-key companion e5bdcd3bacfe9f06233c4f845fa56af54e24d19cd0c0cfce9d2479a5506d44f9 installs IN PLACE over normal f062456644d1c6e8829b289d130e6047e582eb7fd67b139b1b7263be926615e7 with all 44 action payload hashes unchanged. Normal MOBI reading/bookmarks precede replacement. UI removal proves plain original+derived cache absent; redownload and fresh conversion then render river text/image. Installed modified libmobi SHA657b3a35ffa263b42899e48585163e9e5dd32d5c20bf76c4102d3f34516ee56c and converter bridge have executable mappings matching installed APK ZIP byte extents. KF8 saved visible location fails separately t2-42og; records remain retained. This is finite runtime replacement, not legal/store/signing approval. Report docs/evidence/reader/android-corrected-formats-20261103.md. No closure.

**2026-11-08T02:52:43Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
