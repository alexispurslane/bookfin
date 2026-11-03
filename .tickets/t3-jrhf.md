---
id: t3-jrhf
status: open
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
