import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/choice.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/labels.dart';
import 'package:bookfin/sync/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import '../reader/session_test.dart' as reading;
import '../playback/playback_test.dart' show account;
import '../real_time.dart';
import 'conflicts.dart';
import 'fixture.dart';
import 'status_test.dart' show ControlledRecords;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture fixture;
  late RefusingSync sync;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await SyncFixture.open();
    for (final replica in ['first', 'second']) {
      final journal = RecordJournal(fixture.session.scope.key, replica);
      final audioPosition = {
        'edition': audio.recording.id,
        'source': audio.first.key,
        'revision': audio.first.revision,
        'milliseconds': replica == 'first' ? 900 : 100,
      };
      final readingPosition = {
        'edition': reading.edition.id,
        'source': reading.source.key,
        'revision': reading.source.revision,
        'anchor': jsonEncode({
          'version': 1,
          'quote': replica == 'first'
              ? 'A river follows the old road'
              : 'The bridge crosses the river',
          'cfi': 'epubcfi(/6/2!/4/2/1:0)',
        }),
      };
      journal.change(
        jsonEncode([
          'audio',
          'resumes',
          jsonEncode([
            audio.recording.id,
            audio.first.key,
            audio.first.revision,
          ]),
        ]),
        audioPosition,
        device: replica == 'first' ? 'Pixel 8' : 'Pixel Tablet',
      );
      journal.change(
        jsonEncode([
          'reading',
          'resumes',
          jsonEncode([
            reading.edition.id,
            reading.source.key,
            reading.source.revision,
          ]),
        ]),
        readingPosition,
      );
      journal.change(jsonEncode(['audio', 'bookmarks', 'mark-audio']), {
        'id': 'mark-audio',
        'position': audioPosition,
        'createdAt': '2026-01-01T00:00:00Z',
        'bookTitle': audio.title.title,
        'editionLabel': audio.recording.label,
        'title': '$replica audio note',
      });
      journal.change(jsonEncode(['reading', 'bookmarks', 'mark-reading']), {
        'id': 'mark-reading',
        'position': readingPosition,
        'createdAt': '2026-01-01T00:00:00Z',
        'title': '$replica reading note',
      });
      fixture.publish(journal);
    }
    sync = RefusingSync(records: LocalResumeStore())..bind(fixture.session);
    await sync.synchronize();
    expect(sync.conflicts, hasLength(4));
  });
  tearDown(() async {
    sync.dispose();
    await fixture.close();
  });

  Future<void> showFixturePage(
    WidgetTester tester,
    ValueNotifier<CatalogLibrary> library,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: RecordSyncPage(sync: sync, library: library),
      ),
    );
  }

  String shownText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');

  /// Opens the collapsed conflict whose row shows [title].
  Future<void> open(WidgetTester tester, String title) async {
    final row = find.widgetWithText(InkWell, title).first;
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'conflict choices identify saved books and readable positions instead of raw record addresses',
    (tester) async {
      await showFixturePage(tester, ValueNotifier(CatalogLibrary.empty));
      for (final title in ['Book not in the current library', 'River']) {
        if (find.widgetWithText(InkWell, title).evaluate().isNotEmpty) {
          await open(tester, title);
        }
      }
      final text = shownText(tester);
      expect(text, contains(audio.title.title));
      expect(text, contains('Pixel 8'));
      expect(text, contains('Pixel Tablet'));
      expect(text, contains('0:00'));
      expect(text, contains('not in the current library'));
      expect(text, isNot(contains('epubcfi(')));
      expect(text, isNot(contains('"version"')));
      expect(text, isNot(contains(audio.first.key)));
      expect(text, isNot(contains(reading.edition.id)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflict choices use the current catalog book and kind of record',
    (tester) async {
      await showFixturePage(
        tester,
        ValueNotifier(CatalogLibrary.build([audio.title, reading.book])),
      );
      final text = shownText(tester);
      expect(text, contains('River'));
      expect(text, contains('Reading bookmark'));
      expect(text, contains(audio.title.title));
      expect(text, contains('Listening saved place'));
      expect(text, isNot(contains('not in the current library')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'after a library refresh, the conflict list names the book from the new library',
    (tester) async {
      final library = ValueNotifier(CatalogLibrary.empty);
      await showFixturePage(tester, library);
      expect(find.text('River'), findsNothing);
      library.value = CatalogLibrary.build([audio.title, reading.book]);
      await tester.pump();
      expect(find.text('River'), findsWidgets);
    },
  );

  testWidgets(
    'Keep resolves the choice through record sync and the page no longer offers it',
    (tester) async {
      await showFixturePage(
        tester,
        ValueNotifier(CatalogLibrary.build([audio.title, reading.book])),
      );
      expect(find.text('4 choices wait'), findsOneWidget);
      final keep = find.text('Keep A').first;
      await tester.ensureVisible(keep);
      await tester.tap(keep);
      await settle(tester, sync);
      expect(sync.conflicts, hasLength(3));
      expect(find.text('3 choices wait'), findsOneWidget);
      // The choice synced over HTTP in fake time, so the idle connection
      // closes in fake time too.
      await tester.pump(const Duration(seconds: 16));
    },
  );

  testWidgets(
    'the sync view reports Sync now and a choice and calls no record sync method',
    (tester) async {
      sync.refuse = true;
      var syncs = 0;
      final choices = <(String, String, Map<String, String>)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordSyncView(
              status: sync.statusNotifier,
              lastSync: sync.lastSyncNotifier,
              conflicts: sync.conflictsNotifier,
              kept: ValueNotifier((recovered: 0, kept: false)),
              library: ValueNotifier(CatalogLibrary.empty),
              onSync: () => syncs++,
              onResolve: (record, identity, bookmarkTitles) =>
                  choices.add((record, identity, bookmarkTitles)),
              onDiscard: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Sync now'));
      final keep = find.text('Keep A').first;
      await tester.ensureVisible(keep);
      await tester.tap(keep);
      expect(syncs, 1);
      final (record, identity, _) = choices.single;
      expect(
        sync.conflicts[record]!.map(RecordJournal.identity),
        contains(identity),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'choosing a saved place reports the bookmark titles that name each place\'s device',
    (tester) async {
      sync.refuse = true;
      final choices = <(String, String, Map<String, String>)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictChoice(
              record: sync.conflicts.keys.firstWhere(
                (record) => record.contains('"audio","resumes"'),
              ),
              labels: labelConflict(
                sync.conflicts.keys.firstWhere(
                  (record) => record.contains('"audio","resumes"'),
                ),
                sync.conflicts.entries
                    .firstWhere(
                      (entry) => entry.key.contains('"audio","resumes"'),
                    )
                    .value,
                books: [audio.title],
                now: DateTime.now(),
                clock: (at) => '$at',
              ),
              enabled: true,
              onResolve: (record, identity, bookmarkTitles) =>
                  choices.add((record, identity, bookmarkTitles)),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Keep B'));
      final (record, identity, bookmarkTitles) = choices.single;
      final versions = sync.conflicts[record]!;
      expect(identity, RecordJournal.identity(versions.last));
      expect(bookmarkTitles, {
        RecordJournal.identity(versions.first): 'Pixel 8 · Opening',
        RecordJournal.identity(versions.last): 'Pixel Tablet · Opening',
      });
    },
  );

  group('with a controlled sync', () {
    late ControlledRecords records;
    late RecordSync controlled;
    late DateTime clock;
    setUp(() async {
      records = ControlledRecords();
      clock = DateTime.now();
      controlled = RecordSync(
        records: records,
        transport: records.transport,
        now: () => clock,
      )..bind(account());
      // Signing in syncs at once. These tests start after that sync.
      await pumpEventQueue();
    });
    tearDown(() => controlled.dispose());

    Future<void> showPage(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(brightness),
          home: RecordSyncPage(
            sync: controlled,
            library: ValueNotifier(CatalogLibrary.build(books)),
          ),
        ),
      );
    }

    /// Syncs in the background with what [records] now holds.
    Future<void> backgroundSync(WidgetTester tester) async {
      await tester.runAsync(controlled.synchronize);
      await tester.pumpAndSettle();
    }

    IconButton roundSync(WidgetTester tester) => tester.widget<IconButton>(
      find.descendant(
        of: find.byType(SyncStatusStrip),
        matching: find.byType(IconButton),
      ),
    );

    testWidgets(
      'a healthy page says Synced and that nothing waits to be chosen',
      (tester) async {
        await showPage(tester);
        expect(find.text('Synced'), findsOneWidget);
        expect(find.textContaining('Jellyfin'), findsWidgets);
        expect(find.text('Nothing to choose'), findsOneWidget);
        expect(find.byType(SyncBanner), findsNothing);
        expect(roundSync(tester).tooltip, 'Sync now');
      },
    );

    testWidgets('a background sync shows no busy state on the page', (
      tester,
    ) async {
      records.gate = Completer();
      await showPage(tester);
      unawaited(controlled.synchronize());
      await tester.pump();
      expect(find.text('Syncing…'), findsNothing);
      expect(roundSync(tester).onPressed, isNotNull);
      records.gate!.complete();
      await tester.pump();
    });

    testWidgets(
      'Sync now shows Syncing until it ends and turns off the Sync button and every Keep button',
      (tester) async {
        records.found = {...frostConflict};
        await backgroundSync(tester);
        records.gate = Completer();
        await showPage(tester);
        await tester.tap(find.byTooltip('Sync now'));
        await tester.pump();
        expect(find.text('Syncing…'), findsOneWidget);
        expect(roundSync(tester).onPressed, isNull);
        for (final keep in ['Keep A', 'Keep B']) {
          expect(
            tester
                .widget<ButtonStyleButton>(
                  find.ancestor(
                    of: find.text(keep),
                    matching: find.bySubtype<ButtonStyleButton>(),
                  ),
                )
                .onPressed,
            isNull,
          );
        }
        records.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Syncing…'), findsNothing);
        expect(roundSync(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'without a connection, the page says Not syncing and offers Retry in a banner',
      (tester) async {
        clock = DateTime.now().subtract(const Duration(minutes: 5));
        await backgroundSync(tester);
        clock = DateTime.now();
        records.failure = true;
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('Not syncing'), findsOneWidget);
        expect(find.textContaining('· tried '), findsOneWidget);
        expect(find.text('Jellyfin cannot be reached'), findsOneWidget);
        expect(find.text('Bookfin Storage plugin missing'), findsNothing);
        expect(roundSync(tester).tooltip, 'Retry');
        records.failure = false;
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await settle(tester, controlled);
        expect(find.text('Synced'), findsOneWidget);
        expect(find.text('Jellyfin cannot be reached'), findsNothing);
      },
    );

    testWidgets(
      'without the storage plugin, the page says Sync is off and offers Check again',
      (tester) async {
        records.error = const CatalogFailure(
          CatalogFailureKind.unavailable,
          status: 404,
        );
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('Sync is off'), findsOneWidget);
        expect(find.text('Records stay on this phone'), findsOneWidget);
        expect(find.text('Bookfin Storage plugin missing'), findsOneWidget);
        expect(find.text('Jellyfin cannot be reached'), findsNothing);
        expect(roundSync(tester).tooltip, 'Check again');
        expect(find.widgetWithText(TextButton, 'Check again'), findsOneWidget);
      },
    );

    testWidgets('records that cannot be read show their own banner', (
      tester,
    ) async {
      records
        ..failure = true
        ..unreadable = true;
      await showPage(tester);
      await backgroundSync(tester);
      expect(find.text('Personal records could not be read'), findsOneWidget);
    });

    testWidgets(
      'after a sync that took the server copy of damaged records the page quietly says so',
      (tester) async {
        records.replaced = 1;
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('1 record restored from Jellyfin'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        records.replaced = 0;
        await backgroundSync(tester);
        expect(find.textContaining('restored from Jellyfin'), findsNothing);
      },
    );

    testWidgets(
      'damaged records kept aside show a banner that says how many came back',
      (tester) async {
        records.kept.value = (recovered: 2, kept: true);
        await showPage(tester);
        expect(find.text('Damaged records kept aside'), findsOneWidget);
        expect(find.textContaining('2 records came back.'), findsOneWidget);
        expect(find.text('Discard the copy…'), findsOneWidget);
        records.kept.value = (recovered: 1, kept: false);
        await tester.pump();
        expect(find.text('Damaged records kept aside'), findsNothing);
        expect(find.text('1 damaged record was recovered'), findsOneWidget);
        expect(find.text('Discard the copy…'), findsNothing);
      },
    );

    testWidgets('Discard deletes the kept copies only after a confirmation', (
      tester,
    ) async {
      records.kept.value = (recovered: 0, kept: true);
      await showPage(tester);
      await tester.tap(find.text('Discard the copy…'));
      await tester.pumpAndSettle();
      expect(find.text('Discard damaged records?'), findsOneWidget);
      expect(records.discards, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(records.discards, 1);
      expect(find.text('Discard damaged records?'), findsNothing);
      expect(find.text('Discard the copy…'), findsNothing);
    });

    testWidgets('a Discard that the user cancels deletes nothing', (
      tester,
    ) async {
      records.kept.value = (recovered: 0, kept: true);
      await showPage(tester);
      await tester.tap(find.text('Discard the copy…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(records.discards, 0);
      expect(find.text('Discard the copy…'), findsOneWidget);
    });

    testWidgets('a Discard that fails says so and keeps offering Discard', (
      tester,
    ) async {
      records
        ..kept.value = (recovered: 0, kept: true)
        ..discardFails = true;
      await showPage(tester);
      await tester.tap(find.text('Discard the copy…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The damaged copies were not deleted. Retry after checking device storage.',
        ),
        findsOneWidget,
      );
      expect(find.text('Discard the copy…'), findsOneWidget);
    });

    testWidgets(
      'one place conflict draws both places as pins A and B on a track of the book, then two columns',
      (tester) async {
        records.found = {...frostConflict};
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('1 choice waits'), findsOneWidget);
        expect(find.text('Choose a saved place'), findsOneWidget);
        expect(find.text('First Frost'), findsOneWidget);
        final track = find.byType(BookTrack);
        expect(track, findsOneWidget);
        for (final pin in ['A', 'B']) {
          expect(
            find.descendant(of: track, matching: find.text(pin)),
            findsOneWidget,
          );
        }
        expect(find.text('10 h 0 m'), findsOneWidget);
        expect(find.text('4:12:47'), findsOneWidget);
        expect(find.text('2:33:16'), findsOneWidget);
        expect(find.text('Chapter 6 · Frostbite'), findsOneWidget);
        expect(find.text('Keep A'), findsOneWidget);
        expect(find.text('Keep B'), findsOneWidget);
        expect(
          find.text('Both places stay as bookmarks. Your audio does not jump.'),
          findsOneWidget,
        );
        expect(find.text('Nothing to choose'), findsNothing);
      },
    );

    testWidgets(
      'a bookmark changed on one device and deleted on another shows only the two columns',
      (tester) async {
        records.found = {...northConflict};
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('Choose a saved version'), findsOneWidget);
        expect(find.byType(BookTrack), findsNothing);
        expect(find.text('Keep deletion'), findsOneWidget);
        expect(find.text('Keep A'), findsOneWidget);
        expect(find.text('Keep B'), findsOneWidget);
        expect(find.textContaining('Both places stay'), findsNothing);
      },
    );

    testWidgets(
      'with several conflicts one is open and the rest are collapsed rows that open on a tap',
      (tester) async {
        records.found = {...frostConflict, ...northConflict};
        await showPage(tester);
        await backgroundSync(tester);
        expect(find.text('2 choices wait'), findsOneWidget);
        expect(find.text('Keep A'), findsOneWidget);
        expect(find.byType(BookTrack), findsOneWidget);
        expect(find.text('Keep deletion'), findsNothing);
        await open(tester, 'Northbound');
        expect(find.text('Keep A'), findsOneWidget);
        expect(find.text('Keep deletion'), findsOneWidget);
        expect(find.byType(BookTrack), findsNothing);
        expect(find.widgetWithText(InkWell, 'First Frost'), findsOneWidget);
      },
    );

    testWidgets(
      'Keep on the page resolves through record sync and clears the conflict',
      (tester) async {
        records.found = {...frostConflict};
        await showPage(tester);
        await backgroundSync(tester);
        await tester.tap(find.text('Keep B'));
        await settle(tester, controlled);
        expect(records.resolved, [
          RecordJournal.identity(frostConflict.values.single.last),
        ]);
        expect(find.text('Keep B'), findsNothing);
        expect(find.text('Nothing to choose'), findsOneWidget);
      },
    );

    testWidgets('a choice that changed meanwhile says so on the page', (
      tester,
    ) async {
      records
        ..found = {...frostConflict}
        ..refuseChoice = true;
      await showPage(tester);
      await backgroundSync(tester);
      await tester.tap(find.text('Keep A'));
      await settle(tester, controlled);
      expect(
        find.textContaining(
          'This saved choice changed before it was selected.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('every page state draws at night without overflow', (
      tester,
    ) async {
      records
        ..found = {...frostConflict, ...northConflict}
        ..kept.value = (recovered: 2, kept: true)
        ..replaced = 1;
      await showPage(tester, brightness: Brightness.dark);
      await backgroundSync(tester);
      expect(tester.takeException(), isNull);
      records.failure = true;
      await backgroundSync(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a Discard that the user cancels keeps the kept copies', (
    tester,
  ) async {
    const copy = 'bookfin.damaged-records.v1.alice.1';
    SharedPreferences.setMockInitialValues({copy: '{broken'});
    final records = LocalResumeStore();
    await finish(tester, records.recoverKept());
    final page = RecordSync(records: records);
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordSyncPage(
          sync: page,
          library: ValueNotifier(CatalogLibrary.empty),
        ),
      ),
    );

    await tester.tap(find.text('Discard the copy…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString(copy), '{broken');
    expect(find.text('Discard the copy…'), findsOneWidget);

    await tester.tap(find.text('Discard the copy…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString(copy), isNull);
    expect(find.text('Discard the copy…'), findsNothing);
  });
}

/// A record sync that throws on every action once [refuse] is set.
class RefusingSync extends RecordSync {
  RefusingSync({required super.records});
  bool refuse = false;

  @override
  Future<void> synchronize() =>
      refuse ? throw StateError('synchronize') : super.synchronize();

  @override
  Future<void> syncNow() =>
      refuse ? throw StateError('syncNow') : super.syncNow();

  @override
  Future<void> resolve(
    String record,
    String identity, {
    Map<String, String> bookmarkTitles = const {},
  }) => refuse
      ? throw StateError('resolve')
      : super.resolve(record, identity, bookmarkTitles: bookmarkTitles);
}

/// Waits until the sync or the choice that the user started on [sync]
/// ends, in real and fake time in turns, then lets the frames settle.
Future<void> settle(WidgetTester tester, RecordSync sync) async {
  await tester.pump();
  await runUntil(tester, () => !sync.busy);
  await tester.pumpAndSettle();
}
