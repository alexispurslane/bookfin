---
id: boo-52d6
status: closed
deps: []
links: []
created: 2026-11-11T00:07:39Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Install and verify an optimized release build on Pixel 8

User explicitly requests release mode for the Pixel installation. Build normal lib/main.dart with Flutter release ARM64; sign with the same existing local certificate to update in place without data removal; verify AOT artifacts, debuggable false, native/OCR packaging, signature/alignment, installed certificate and package flags. No Pixel UI input. Long-term distribution key configuration remains t5-vbno.


## Notes

**2026-11-11T00:11:29Z**

Installed optimized normal ARM64 Flutter release app on Pixel 8 in place. Clean build source 04586bb84748bb05c5c8305d37d1fbfbce2f1964. APK SHA256 daf1ec4cbc78ce1bcef69d238da08db031d19b0f1b068b6878ace6fa27c22a85 (44,768,888 bytes). Built through Nix with flutter build apk --release --target-platform android-arm64; aligned and signed using the existing local certificate because distribution signing configuration remains t5-vbno. The local certificate does not change release compilation mode. Both native package and OCR package verification passed, including signature and 16 KiB alignment. Verified lib/arm64-v8a/libapp.so present, debug kernel absent, manifest not debuggable. Pulled the installed previous APK and verified identical signer before adb install -r returned Success. Installed package flags omit DEBUGGABLE. Pulled the installed replacement and verified its SHA256 exactly equals the checked release artifact. No uninstall, data clearing, or Pixel UI operation. Logs: /tmp/bookfin-pixel-release-build.log, /tmp/bookfin-pixel-release-install.log, /tmp/bookfin-pixel-release-installed-hash.log; manifest/certificate/package diagnostics use the same prefix. Prior combined source checks remain 2649 passed,21 skipped with clean analysis/format; no app source changed for this installation. No measured performance verdict: emulator UI remains blocked under boo-kdc6; user owns phone use and acceptance.
