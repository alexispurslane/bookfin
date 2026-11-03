# Saved-action validation and account-lifetime correction

Base: b81b472001cb65f87480f0914dfa90cf78e65c09. These changes address
independent review R1 and R2 without changing the format milestone or packaging.

The stored journal now passes every retained action through the same record
validator as downloaded actions before conversion or upload. This includes
superseded actions, not just the current projected records or pending uploads.
The existing broad validation catch is narrowed to format and checked-field
type errors; internal invariant and other programming failures are not caught.
Journal corruption preserves stored bytes and pending reader writes.

Reading refresh captures the existing account-generation counter before its
read. A refresh from a previous account binding cannot replace records or the
accepted-snapshot baseline after switching away and returning.

## Regressions

The retained red run reproduces both reported failures against the base:
an integer listening edition in an otherwise structurally valid saved action
raises a TypeError during a reading bookmark save; an old held refresh hides a
newly discovered bookmark after account A → B → A.

The first regression asserts unchanged damaged bytes, a normal save warning,
normal synchronization failure, retained pending actions, and successful
bookmark persistence after restoring healthy storage. The second uses the real
store and remote merge, holds only the read delivery, reopens without another
visible-location event, and checks the new bookmark remains visible. It also
proves an intentional deletion after returning persists.

The two focused files pass all 11 tests after correction.

Commands, run through the pinned development shell:

    nix develop --command bash -c 'flutter test test/sync/persisted_journal_test.dart test/sync/owner_refresh_test.dart --reporter expanded'
    nix develop --command bash -c 'dart format lib/playback/store.dart lib/reader/session.dart test/sync/persisted_journal_test.dart test/sync/owner_refresh_test.dart'
    nix develop --command bash -c 'flutter test --concurrency=1 --reporter expanded'
    nix develop --command bash -c 'flutter analyze'

The iOS SDK discovery messages are existing native-hook output on a host without
the iOS SDK. No iOS acceptance is claimed.

No Android build, installation, device action, actual-plugin rerun, journal-growth
measurement, production deployment, coverage or mutation campaign is included.
The earlier b81b472 APK does not contain these corrections. Source review and
Android acceptance remain required; t6-t9po and t6-il6y stay open.

The first full suite passed 397 tests with one optional plugin skip and failed
two storage tests: database migration and bookmark durability. Both fixtures
contained only bookmark ID/title, omitting the position and other required
record fields. Their fixtures now contain valid complete audio bookmarks.
The original full-run failure is retained in full-incomplete-fixtures.txt.
No production validation was weakened to accommodate these fixtures.

Final verification: 399 Flutter tests pass, one optional actual-plugin test
skipped. Flutter analysis reports no issues. SDK link, SDK platform and native
tool checks pass. Formatting and git diff --check pass. All parent commands
completed; no parent server, device binding or build daemon was started.
