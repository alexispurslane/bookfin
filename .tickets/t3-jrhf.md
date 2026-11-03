---
id: t3-jrhf
status: closed
deps: []
links: [boo-mx5i, t0-ebxa, t3-ipk1]
created: 2026-11-03T13:38:32Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Identify original ebook format when Jellyfin Book omits Container

Normal Android source 4ae8c6c exact APK SHA256 610fb123b835858d675302c550e4b6476ddfcd12372aaebac85a7f2f4b51f7ef downloads the pinned NIST original through ordinary Jellyfin 12.4.0 /Items/id/Download (85781 bytes), but Read reports Unsupported EPUB ZIP directory. Ordinary Book DTOs omit Container and MediaSources even with requested fields; source container remains empty and the normal reader selects EPUB. Evidence is being recorded in tool/evidence/reader/formats/20261103/android-normal/. No production edit by acceptance lane.

## Acceptance Criteria

Actual unchanged ordinary Jellyfin Book download opens the matching PDF or MOBI reader without forged DTO fields or app-private state edits. Preserve original integrity, account ownership, EPUB compatibility and original-download permission rules. Add meaningful regressions, then repeat normal-app PDF/MOBI/KF8 Android acceptance.


## Notes

**2026-11-03T14:16:49Z**

Confirmed independently with ordinary generated plain MOBI after the NIST PDF failure. Both original files match pinned/generated corpus hashes in app-private completed downloads. Both Read produce the same EPUB ZIP rejection, and no derived MOBI directory is present. Generated EPUB opens with actual font/image/native reading evidence, isolating the missing-format admission issue from a general reader failure. Parent must fix with red-green tests and repeat the blocked PDF/MOBI/native-replacement gates; acceptance lane makes no production edit. Exact report and raw evidence now prepared.

## Parent correction

Reproduced four meaningful host failures through real buildBooks ordinary-Book
DTO admission, extensionless downloaded-file paths and native importers: PDF,
plain MOBI, PalmDOC MOBI and KF8 all reached EPUB. Existing verified local-file
loader now selects PDF/MOBI by bounded header inspection when Container is
absent; parser validation and explicit metadata behavior remain intact.
EPUB/rejected invalid bytes/symlink controls pass. 17 focused and 431 full tests
pass (three opt-in skips), analysis clean. Evidence:
tool/evidence/reader/formats/20261103/missing-container/. Independent review,
corrected-build Android format/native-replacement acceptance still required.

Independent read-only review approves 2ece46b..44d53af for bounded source
integration with no actionable finding. The corrected normal APK and matching
source are prepared from exactly 44d53af; verification records are under
missing-container/android/. Prior 4ae8c6c rejection remains valid baseline
evidence. Corrected runtime acceptance and ticket closure are still pending.

**2026-11-03T15:44:19Z**

Corrected exact 44d53af normal APK now opens genuine ordinary Jellyfin Book downloads with neither Container nor MediaSources: intact NIST PDF, plain MOBI6, PalmDOC MOBI6 and pinned Alice KF8. Installed APK hashes verified. No forged DTO/private-state substitute. Finite acceptance report docs/evidence/reader/android-corrected-formats-20261103.md. Distinct visible KF8 place failure t2-42og and pending sync t2-00a4 remain; no closure by acceptance lane.


2026-11-03 parent acceptance: close the bounded missing-format-admission bug. Reviewed correction 44d53af is integrated and actual corrected normal Android evidence verifies genuine metadata-absent PDF/plain MOBI/PalmDOC/KF8 originals open through their readers without forged DTOs or private-state edits. Existing EPUB/integrity/ownership host controls remain. This closure does not close boo-mx5i, t2-42og, t2-00a4, OCR, or distribution acceptance. See docs/evidence/reader/android-corrected-formats-20261103.md.
