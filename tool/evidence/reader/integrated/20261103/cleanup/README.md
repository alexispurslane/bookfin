# Authorized device cleanup, November 3, 2026

The user renewed authorization after the combined acceptance lane stopped.
The parent opened an exclusive binding for local emulator-5554 and used its
returned agent-device command for every app, input and settings action.

Canceled the unsaved bookmark dialog. Removed Alice KF8, Empty scan, English
scan, Historical scan and Long English scan through ordinary download controls.
Downloads then showed no downloads and no retained files. Signed out and closed
Bookfin. Restored airplane mode off, Wi-Fi on and mobile data on. Media remained
muted. No reset, uninstall, database write or personal-record deletion occurred.
The installed companion package and bundled English model remain installed.
The existing large system text size and Alice reading preference were unchanged.

The read-only audit ran in the pinned Nix shell. All 69 retained action identities,
exact payload hashes and pending flags match the previous stop audit. The original
28 pending actions remain pending. SQLite integrity is ok. No Bookfin process
remains. No book originals or derived OCR page caches remain in the files directory.
The temporary private database copy was automatically deleted after inspection.

The initial Cancel action succeeded but its settle observation was unavailable;
a fresh snapshot verified dismissal. The sheet Dismiss tap did not remove the
sheet; ordinary system Back did. No command failure or recovery retry occurred.
The binding was released with shutdown:false after the audit. No further device
actions followed release. This closes the cleanup portion of the stop only;
it establishes no additional OCR, field-entry or sync acceptance.

Evidence: downloads.txt, signed-out.txt and audit.json.
Reproduction of the read-only audit: nix develop --command python3
 tool/evidence/reader/integrated/20261103/cleanup/audit.py
