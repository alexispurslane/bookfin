# KF8 character restoration candidate

This is the implementation candidate for `t2-42og` from parent
`a22e0b865a4fe70848849bdd539bad0b9bd4f224`. It is host proof, not Android
acceptance. The orchestrator owns independent review, integration, and the
Android rerun. The ticket remains in progress.

## Exact source and converted archive

The regression uses the committed Project Gutenberg Alice KF8 original and
the production MOBI importer. It does not substitute a short synthetic book.
The original archive terms remain in the committed source.

| Identity | SHA-256 |
| --- | --- |
| Original KF8, 255,506 bytes | `d8211269aed55ded8302f289950936db8368b4d4d384c463b722034152f8f1d2` |
| Converted Android EPUB, 204,423 bytes | `2f6de175d5f69498afb7d8e941dfed0253e11881cfd1628556f959db71ec8fa8` |
| Stored edition identity | `3d0b0318cf5d0455722a2b8ccf93ac5ec0be08e0c198a831d41d4990be1f10d7` |

The original Android cache was removed during the earlier acceptance cleanup.
The converter stamps ZIP entries with its current local clock. The fixture
restores only those header timestamps to November 3, 2026, at 09:56:26.
ZIP timestamps contain no time zone. The fixture then asserts the full
converted-archive SHA-256 against the Android evidence. No other archive
byte differs. This recreates the exact converted corpus without retaining a
second copy of the ebook in Git.

`tool/reader/kf8_layout_fixture_test.dart` passes that exact archive through
production passive EPUB admission. It asserts that every admitted resource
equals the ordinary production conversion, including a second import through
the existing cache. The layout test receives these admitted resources, the
actual bundled Source Serif font, and the actual bundled reader engine.
The fixture changes no production converter or admission rule.

## Reproduction and cause

The saved CFI is a character address within the EPUB:
`epubcfi(/6/10!/4/2[pgepubid00003]/4/1:260)`.
Its resource is `OEBPS/part00004.html`. Its quote starts with a space before
`Alice “without pictures or conversations?”` and continues into
`So she was considering in her own mind`.

At a 412-by-630 CSS-pixel viewport and a 22-CSS-pixel font size, ordinary Next
shows page 2 of 21 and saves exactly that CFI. These are host test dimensions,
not a claim about the Android screen dimensions. CSS pixels measure the
browser layout, not physical screen pixels.

The space at character 260 has no painted width at the column boundary.
Chromium assigns its collapsed caret rectangle to the end of page 1. The
following word, `Alice`, begins page 2. The existing destination measurement
tries to extend a collapsed range to the next space. At character 260, that
space is the current character, so the range remains collapsed.

Before the correction, reopen and bookmark navigation measure page 1 while
reporting the unchanged requested CFI. The saved quote alone therefore
cannot prove visible restoration. The real character rectangles show the
failure independently of reader location events.

| Measurement in the fixed host viewport | Parent assets | Candidate assets |
| --- | --- | --- |
| `Alice` left edge, CSS pixels from the viewport left edge | 429, outside viewport | 17, visible |
| `Alice` top edge, CSS pixels from the iframe top edge | 3 | 3 |
| `So she was consideri` left edge, CSS pixels from the viewport left edge | 451, outside viewport | 39, visible |
| Chapter heading left edge, CSS pixels from the viewport left edge | 17, visible | -395, on preceding page |
| Reported chapter page | 1 of 21 | 2 of 21 |
| Reported saved CFI and quote | Unchanged | Unchanged |

The failure reproduces in an ordinary host reader without native-library
replacement. Native-library replacement is not necessary for this failure.
This does not establish every cause of the earlier Android observation.

## Correction and ownership

`Contents.locationOf` remains the owner of destination geometry. The added
code is:

```js
						if (range.startContainer.nodeType === TEXT_NODE) {
							const followingCharacterOffset = range.startContainer.textContent.slice(range.startOffset).search(/\S/);
							if (followingCharacterOffset >= 0) {
								range.setStart(range.startContainer, range.startOffset + followingCharacterOffset);
							}
						}
```

where

- `range` is the temporary DOM range used to measure the destination.
- `startContainer` is the node that contains the saved start character.
- `nodeType` identifies the kind of DOM node.
- `TEXT_NODE` is the existing DOM text-node type, with value 3.
- `textContent` is the text of that node.
- `startOffset` is the saved position in that node, in UTF-16 code units.
- `slice` returns the text at and after that position.
- `search(/\S/)` finds the first non-whitespace character in that remaining text.
- `followingCharacterOffset` is its distance from the saved position, in UTF-16 code units, or -1 if none exists.
- `setStart` moves only the temporary measurement range to that character.

The existing noncollapsed-range measurement then selects the correct column.
The stored CFI, resource, quote, and edition identity do not change. No record
migration, second navigation path, timer, or corrective display command is added.
Existing startup resource readiness and both navigation queues remain unchanged.
No OCR, PDF, sync, or immutable action code changes.

## Regression results

The test first checks normal Next. It then checks restoration independently
through six paths. Every check measures actual word and passage rectangles,
the heading position, the page label, and the retained CFI and quote.

| Behavior | Exact-corpus parent run | Candidate run |
| --- | --- | --- |
| Ordinary Next saves the observed nonzero-character position | Pass | Pass |
| Reopen through a fresh reader runtime | Meaningful visible-passage failure | Pass |
| Bookmark within the current chapter | Meaningful visible-passage failure | Pass |
| Bookmark from another chapter | Meaningful visible-passage failure | Pass |
| Restore in a fresh browser process | Meaningful visible-passage failure | Pass |
| Restore after height change from 600 to 630 CSS pixels | Meaningful visible-passage failure | Pass |
| Restore after 24-to-22-CSS-pixel font-size change | Meaningful visible-passage failure | Pass |

The fresh browser process receives the serialized saved address. This tests
the real engine restart boundary, not Android application persistence.
The tests do not alter or replace any account record.

Raw evidence is under `tool/evidence/reader/kf8-restoration/`. The exact-corpus
red run uses the two unchanged parent JavaScript assets through the existing
`BOOKFIN_TEST_ASSETS` test setting. All six restoration checks fail on visible
passage assertions, while ordinary Next passes. Candidate verification results
and reproducible commands are recorded with that evidence.

Final Nix checks pass: 68 focused reader tests, 20 layout-runner tests,
35 JavaScript-runner tests, and 431 full-suite Flutter tests. Three existing
opt-in full-suite cases are skipped because their external inputs are absent.
The three environment scripts, Flutter analysis, Dart formatting, and the
four-asset hash verification also pass. No APK build is part of this candidate.

## Remaining acceptance and risk

The parent must independently review the candidate before Android proof.
On the exact normal application build, repeat ordinary cached reopen,
bookmark return, process restart, and relevant size changes. Compare visible
text and retained records, not only reported CFIs. Repeat the same-key
in-place library replacement check without resetting data or rewriting actions.

The candidate is not installed or observed on Android. No physical-device,
TalkBack, WebKit, SVG-resource, or distribution acceptance is claimed.
No coverage or mutation hardening runs in this task. All test HTTP listeners
bind only to loopback and close with their owned headless browser processes.
