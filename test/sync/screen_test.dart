import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import '../reader/session_test.dart' as reading;
import '../playback/playback_test.dart' show account;
import '../real_time.dart';
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

  testWidgets(
    'conflict choices identify saved books and readable positions instead of raw record addresses',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecordSyncPage(
            sync: sync,
            library: ValueNotifier(CatalogLibrary.empty),
          ),
        ),
      );
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join('\n');
      expect(text, contains(audio.title.title));
      expect(text, contains('00:00.900'));
      expect(text, contains('00:00.100'));
      expect(text, contains('A river follows the old road'));
      expect(text, contains('not in the current library'));
      expect(text, isNot(contains('epubcfi(')));
      expect(text, isNot(contains('"version"')));
      expect(text, isNot(contains(audio.first.key)));
      expect(text, isNot(contains(reading.edition.id)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflict choices use the current catalog book, edition and source names',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecordSyncPage(
            sync: sync,
            library: ValueNotifier(
              CatalogLibrary.build([audio.title, reading.book]),
            ),
          ),
        ),
      );
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join('\n');
      expect(text, contains('River · Reading bookmark'));
      expect(text, contains('River · EPUB · Book.epub'));
      expect(text, contains('The journey · Narrator · Part one · 00:00.100'));
      expect(text, isNot(contains('not in the current library')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'after a library refresh, the conflict list names the book from the new library',
    (tester) async {
      final library = ValueNotifier(CatalogLibrary.empty);
      await tester.pumpWidget(
        MaterialApp(
          home: RecordSyncPage(sync: sync, library: library),
        ),
      );
      expect(find.textContaining('River · Reading bookmark'), findsNothing);
      library.value = CatalogLibrary.build([audio.title, reading.book]);
      await tester.pump();
      expect(find.textContaining('River · Reading bookmark'), findsOneWidget);
    },
  );

  testWidgets(
    'the sync view reports Sync now and a choice and calls no record sync method',
    (tester) async {
      sync.refuse = true;
      var syncs = 0;
      final choices = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordSyncView(
                status: sync.statusNotifier,
                lastSync: sync.lastSyncNotifier,
                conflicts: sync.conflictsNotifier,
                kept: ValueNotifier((recovered: 0, kept: false)),
                library: ValueNotifier(CatalogLibrary.empty),
                onSync: () => syncs++,
                onResolve: (record, identity) =>
                    choices.add((record, identity)),
                onDiscard: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sync now'));
      final choice = find.textContaining('first audio note');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      expect(syncs, 1);
      final (record, identity) = choices.single;
      final chosen = sync.conflicts[record]!.singleWhere(
        (action) => RecordJournal.identity(action) == identity,
      );
      expect((chosen['value'] as Map)['title'], 'first audio note');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'after a background sync the page quietly says when records last synced',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecordSyncPage(
            sync: sync,
            library: ValueNotifier(CatalogLibrary.empty),
          ),
        ),
      );
      expect(find.textContaining('Last synced · Today, '), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.textContaining('Choose between saved places'), findsNothing);
    },
  );

  group('with a controlled sync', () {
    late ControlledRecords records;
    late RecordSync controlled;
    setUp(() async {
      records = ControlledRecords();
      controlled = RecordSync(records: records)..bind(account());
      // Signing in syncs at once. These tests start after that sync.
      await pumpEventQueue();
    });
    tearDown(() => controlled.dispose());

    Future<void> showPage(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: RecordSyncPage(
          sync: controlled,
          library: ValueNotifier(CatalogLibrary.empty),
        ),
      ),
    );

    testWidgets('a background sync shows no busy state on the page', (
      tester,
    ) async {
      records.gate = Completer();
      await showPage(tester);
      unawaited(controlled.synchronize());
      await tester.pump();
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Syncing personal records…'), findsNothing);
      records.gate!.complete();
      await tester.pump();
      expect(find.text('Personal records are synced.'), findsNothing);
    });

    testWidgets(
      'after a failed background sync the page says to tap Sync now to retry',
      (tester) async {
        records.failure = true;
        await showPage(tester);
        await controlled.synchronize();
        await tester.pump();
        expect(
          find.text('Last sync failed. Tap Sync now to retry.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Personal records remain on this device'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'after a sync that took the server copy of damaged records the page quietly says so',
      (tester) async {
        records.replaced = 1;
        await showPage(tester);
        await controlled.synchronize();
        await tester.pump();
        expect(
          find.textContaining(
            '1 damaged record was restored from Jellyfin. Bookfin kept the damaged copy.',
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
        records.replaced = 0;
        await controlled.synchronize();
        await tester.pump();
        expect(find.textContaining('restored from Jellyfin'), findsNothing);
      },
    );

    testWidgets(
      'after damaged records came back the page quietly says how many',
      (tester) async {
        records.kept.value = (recovered: 3, kept: true);
        await showPage(tester);
        expect(
          find.textContaining('3 damaged records were recovered.'),
          findsOneWidget,
        );
        records.kept.value = (recovered: 1, kept: true);
        await tester.pump();
        expect(
          find.textContaining('1 damaged record was recovered.'),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('the quiet line offers Discard only while kept copies exist', (
      tester,
    ) async {
      await showPage(tester);
      expect(find.text('Discard'), findsNothing);
      records.kept.value = (recovered: 0, kept: true);
      await tester.pump();
      expect(find.text('Discard'), findsOneWidget);
      expect(find.textContaining('were recovered'), findsNothing);
    });

    testWidgets('Discard deletes the kept copies only after a confirmation', (
      tester,
    ) async {
      records.kept.value = (recovered: 2, kept: true);
      await showPage(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(records.discards, 0);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard'),
        ),
      );
      await tester.pumpAndSettle();
      expect(records.discards, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Discard'), findsNothing);
    });

    testWidgets('a Discard that fails says so and keeps offering Discard', (
      tester,
    ) async {
      records
        ..kept.value = (recovered: 0, kept: true)
        ..discardFails = true;
      await showPage(tester);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The damaged copies were not deleted. Retry after checking device storage.',
        ),
        findsOneWidget,
      );
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('tapping Sync now shows busy, then the result', (tester) async {
      records.gate = Completer();
      await showPage(tester);
      await tester.tap(find.text('Sync now'));
      await tester.pump();
      expect(find.text('Syncing personal records…'), findsOneWidget);
      records.gate!.complete();
      await tester.pump();
      expect(find.text('Personal records are synced.'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
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

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect((await SharedPreferences.getInstance()).getString(copy), '{broken');
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Discard'),
      ),
    );
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString(copy), isNull);
    expect(find.text('Discard'), findsNothing);
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
  Future<void> resolve(String record, String identity) =>
      refuse ? throw StateError('resolve') : super.resolve(record, identity);
}
