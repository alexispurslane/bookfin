---
id: boo-zs5i
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Hand typed conflict versions and typed record addresses to the sync screens

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `RecordConflicts` (lib/sync/coordinator.dart:54) passes raw action maps to the widgets. lib/sync/labels.dart:274-314 decodes positions by itself, beside the typed decoders that the store uses. Code parses the record address string with `jsonDecode` in lib/sync/journal.dart:159, lib/playback/store.dart:684-709 and labels.dart. A format change (ta-6ycs and ta-4fhn are queued) must find each decoder, and a missed one fails silently as "preview unavailable". The store hands out typed conflict versions from the decoders that validate actions, and a typed address (domain, collection, id) replaces the string parsing.

## Parent caller audit and settled scope — 2026-11-13

At `571b9e2e`, LocalResumeStore.conflicts returns detached raw action maps.
RecordSync passes them through RecordConflicts and compares them before
notification. labels.dart reinterprets resume/bookmark/history positions,
deletion, action identity, device name and saved time. The Sync page, book
conflict alert, Settings waiting-choice text and ConflictChoice resolution
callbacks all use these values. Journal validation, codec validation and
projection, stale-domain marking, and resolution independently decode the
three-part record-address string. The relevant paths remain present after
boo-3y46 and boo-gcu6. The queued reading-track and bookmark-label features
remain separate; this ticket changes the internal data interface only.

Use one validated representation of a record address and one decoding path
for supported personal-record values. The existing domain decoders in
playback/records.dart remain authoritative for listening/reading positions,
bookmarks and history. Reuse that decoding for validation and the typed
conflict values exposed by LocalResumeStore, so UI consumers cannot disagree
about the stored record shape. The address type owns its serialization
boundary and named domain, collection and record identity. Unknown future
domains/collections must remain representable at the journal boundary.
Keep causal journal operations and retained originals in their current owner;
the typed conflict view is a derived, detached, read-only view, not another
record store or a new action/persistence format.

Keep the current persisted/wire format and exact action/address identities.
In particular, do not silently normalize existing encoded address strings,
merge formerly distinct journal keys, rewrite retained original actions,
reject future-domain records, or expose unreadable future history kinds as
selectable choices. Preserve deletion, unsupported/damaged-record handling,
pending writes, causal ordering, recovery and account isolation. Resolving a
choice still uses the store's authoritative current versions, preserves the
same bookmark records and titles, and rejects stale selections as before.
Do not reconstruct a persistence action from the UI's derived typed view.

Preserve labels and interaction behavior: audio timing and source revisions,
reading source pages/quotes and unavailable previews, bookmark title/note,
history destinations, unknown books, legacy device/save-time fallbacks,
duplicate device names, choice order, whole-book audio tracks and deletion
choices. TextPosition's opaque anchor is not a license to tighten acceptance
of old or unknown reading anchors; reuse existing reader parsing where its
contract fits, and keep preview failure distinct from damaged personal data.
The existing resolution callbacks should carry typed addresses where needed;
widgets keep callbacks and narrow subscriptions, with no new side effects.
Keep unchanged conflicts from notifying merely because typed objects were
allocated again. There is no visual redesign or new product choice here.

Own record address/value decoding and conflict projection, necessary journal
and store callers, coordinator/labels/choice/alert/screen/settings consumers,
and affected tests. Follow real callers through lib, test, integration_test
and tool. Keep the integrated settings persistence and unreadable discovery
behavior. Concurrent boo-2bl9 owns Playback refresh independence from held
audio commands; do not implement its queue/refresh work. boo-w6m2 owns typed
whole-domain snapshots and incremental record queries, boo-n7no owns a shared
writer, and boo-56h7 owns Ask-at-Play behavior. None is part of this ticket.
Do not grow this refactor into general journal typing or a record framework.

Preserve existing behavior tests for the refactor, and add meaningful tests
for the new store-to-consumer contract and address boundaries. No missing
symbol or source-text assertion counts as behavioral red. If a concrete
behavior defect is found, first reproduce it meaningfully, then fix it.
Cover all supported domain/collection kinds, deletion, unknown addresses and
history kinds, exact legacy identities, detached ownership, labels, repeated
unchanged notifications and real conflict resolution. Run Nix focused codec/
journal/store/conflict-label/choice tests; affected sync/playback/reader-record/
durability/catalog/settings/app suites; the full Flutter suite; changed-file
formatting, affected analysis and complete original-base diff checks. Flutter
concurrency two, one heavy command per owner. No device/browser, coverage,
mutations, latency claims or timing-threshold changes. One Astra xhigh lead
and exactly one fresh read-only Astra high reviewer; parent integrates and
closes after verification. Report any genuine user-visible fork before
dependent work.
