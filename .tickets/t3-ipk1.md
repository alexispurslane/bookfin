---
id: t3-ipk1
status: open
deps: [boo-73yj]
links: [boo-73yj, boo-mx5i]
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
