---
id: boo-j7gh
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Count visible book characters with one walker and measure the outline once

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/speech/book_words.dart:94-164 and lib/reader/book_map.dart:528-531 each walk a section and count visible characters, and the two counts must agree to the character. Only one fixture test compares them. A change to what counts as visible in one walker moves every speech landing silently. `BookWords` also calls `measureTextOutline` again, though Crossings already holds that outline. Use one walker that yields each text run with its visible offset, and pass the kept outline into the read job.

## Parent caller audit and settled scope — 2026-11-13

At `950ad803`, `countSection` and `bookWordsOf` parse body events independently.
Both count non-whitespace UTF-16 code units; `isWhiteSpace` already matches
Dart's whitespace expression. Speech tokenization additionally joins inline
markup, separates block boundaries and splits at dashes/ellipsis while counting
that punctuation. Malformed sections roll back their entire contribution.
`bookWordsOf` calls `measureTextOutline` again only to locate back matter.
Crossings already owns kept/in-flight outlines by edition/file revision, and
every `SpeechPair` already carries its outline. Its `words` callback currently
passes only the text edition through main.dart to `bookWordsReader` and the
BookSearch worker. This is settled reuse/extraction, with no product fork.

Use one section traversal for the shared visible-character rule and text-run
offsets. Keep word normalization/tokenization in its existing owner and outline
measurement/cache ownership in Crossings. Feed the existing outline through
the actual speech read job instead of measuring it again. Preserve first-ID
offsets, navigation/CFI behavior, Unicode and UTF-16 units, whitespace, entities,
CDATA, inline/block boundaries, punctuation, empty/malformed sections, missing
resources and back-matter exclusion. Preserve current body-event semantics;
this ticket does not redefine visibility as CSS visibility or rendering.
The worker must capture only transferable data, keep its existing cache/revision
identity, remain off the UI isolate and never persist admission/conversion data.
Preserve the download hold and remove/read rules. No global cache or second
outline owner, no speech-anchor persistence or place-map redesign.

Read `docs/plans/bookfin.md` and `docs/plans/cross-edition-places.md`. Likely owned
paths: speech/book_words, reader/book_map and text_outline, reader platform
factories, crossings speech wiring, the narrow main.dart callback and tests.
Audit all callers before choosing the smallest internal interface. Preserve
the integrated section stylesheet and admitted-record changes. Another ticket
may remove gallery startup branches in main.dart; do not duplicate its work.

Required proof: meaningful failing-then-passing behavior/work-count tests for
avoiding repeat outline measurement through a real worker read, and broad
agreement of speech offsets with book-map/outline offsets under the cases
above. Exercise EPUB and prepared MOBI reopen plus actual Crossings speech
landings, cache reuse and file-revision changes. Preserve existing worker and
write-ownership evidence. Counts establish avoided work, not Android latency.
Nix checks: focused speech/book_words, book_search, reader/book_words_reader,
text_outline/book_map and crossings speech tests; affected reader, crossings,
speech and app suites; full Flutter suite; changed-file format and affected
analysis/diff checks. Flutter concurrency two and one heavy command per owner.
One Astra xhigh lead builds/fixes, exactly one fresh read-only Astra high
reviewer assesses the complete diff. No second review, device/browser work,
coverage, mutations, publication or closure. Parent integrates and closes.
