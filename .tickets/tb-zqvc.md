---
id: tb-zqvc
status: in_progress
deps: []
links: []
created: 2026-11-02T17:24:51Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Open ordinary Jellyfin Book EPUBs without Container metadata

Fresh authorized Android acceptance of d9d238b with exact recorded APK c1380e6caee8fbdb782a878c920f900463fdd74239a8dff2b8bc58f472ee2ff6 signed in to real Jellyfin12.4 core, downloaded synthetic EPUB successfully, then Read showed Choose a single-file EPUB edition. Other formats are not supported by this reader. Real Book DTO has Container:null and MediaSources:null. Catalog uses an unknown container fallback, while ReaderSession.open requires container epub. No fixture response rewriting or implementation change performed. Public evidence: docs/evidence/reader/android-candidate.md (forthcoming), screenshot03.

## Acceptance Criteria

Normal production app signs in to actual ordinary Jellyfin12.4 Book library, downloads a real EPUB whose DTO omits Container/MediaSources, and renders readable chapter text without test entry or forged observer metadata. Identify formats safely without bypassing bounded EPUB admission. Add regression and rerun authorized Android reader journey.


## Notes

**2026-11-02T17:33:13Z**

Public catalog evidence now distinguishes absent fields: containerFieldPresent=false and mediaSourcesFieldPresent=false in docs/evidence/reader/android-candidate-catalog.json. Original and app-private downloaded EPUB SHA256 both 6efe84b320af9a0f9997dfc6c54b172bc982e6b06978a2c3d75359161da0ce96. No forged format header/DTO, test entry, app implementation change, or approval. Parent owns correction/integration and a named-build Android rerun.

**2026-11-02T17:43:14Z**

Correction203f870 passed independent static review. Starting named-build Android continuation under existing user authorization: prior attempt stopped for application format refusal, not a failed device-tool retry. Test corrected candidate while R1-R4 continue separately; keep ticket open until chapter rendering observed.
**2026-11-02T17:38:17Z**

Parent reproduced missing metadata refusal using actual catalog shape and real verified-file admission. Removed catalog-container prerequisite for single-file text editions; bounded EPUB admission still required. Verified non-EPUB and tampered-file controls reject.335 app tests/analysis pass; awaiting review, combination with R1-R4 and Android rerun.
