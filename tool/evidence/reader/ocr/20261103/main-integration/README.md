# Main source integration

Reviewed source head: 07814afaa983ed05c9cbc4ebe82e4ca000c9e0ce.
Main integration head: c45c0f9 (full SHA available from Git).

Eight OCR implementation/correction/evidence commits cherry-picked cleanly. The builder's 78ce699 format-admission cherry-pick was omitted because the same correction already exists on main as 44d53af. Production files under lib, android, nix, flake.nix and pubspec.yaml match the reviewed head except lib/catalog/transport_io.dart, which retains main's separately reviewed UTF-8 sync correction.

Focused integrated checks: 25 pass (focused.txt), covering OCR read lifetime, real download ownership, SQLite saved positions and Unicode sync retry. This run starts no plugin fixture and does not establish Android behavior. The reviewed branch full run recorded 480 passes and three opt-in skips; no unchanged full-suite repetition was needed for this clean integration.

All previous OCR APKs predate the integrated corrections. Build and verify the final combined candidate after the separate KF8 correction review, then perform normal-app Android acceptance. No OCR ticket closure or distribution approval.
