import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import '../reader/session_test.dart' as reading;
import 'fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture fixture;
  late RecordSync sync;
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
    sync = RecordSync(records: LocalResumeStore())..bind(fixture.session);
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
          home: Scaffold(
            body: SingleChildScrollView(child: RecordSyncView(sync: sync)),
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordSyncView(
                sync: sync,
                books: [audio.title, reading.book],
              ),
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
}
