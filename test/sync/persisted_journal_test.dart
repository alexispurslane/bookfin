import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show LocalFiles;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' show source, edition, book, visible;
import 'fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final damages = <String, void Function(Map<String, dynamic>)>{
    'saved listening resume has an invalid edition': (saved) {
      final journal = saved['sync'] as Map<String, dynamic>;
      final actions = journal['actions'] as List;
      actions.add({
        'version': 1,
        'account': actions.first['account'],
        'replica': 'damaged',
        'sequence': 1,
        'context': <String, dynamic>{},
        'preserve': <String>[],
        'record': jsonEncode([
          'audio',
          'resumes',
          jsonEncode(['audio', 'source', 'revision']),
        ]),
        'value': {
          'edition': 7,
          'source': 'source',
          'revision': 'revision',
          'milliseconds': 900,
        },
      });
    },
    'sync is a list': (saved) => saved['sync'] = [],
    'actions is null': (saved) => saved['sync']['actions'] = null,
    'pending contains a nonstring': (saved) => saved['sync']['pending'] = [7],
    'cursor is a string': (saved) => saved['sync']['cursor'] = '1',
    'pending references an absent action': (saved) =>
        saved['sync']['pending'] = ['action.unknown.1'],
  };

  for (final damage in damages.entries) {
    test(
      '${damage.key} reports a storage error without destroying records or poisoning later reader saves',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fixture = await SyncFixture.open();
        addTearDown(fixture.close);
        final records = LocalResumeStore();
        final downloads = LocalFiles()
          ..files[source.key] = Uri.file('/verified.epub');
        final reader = ReaderSession(
          downloads: downloads,
          store: records.reading,
          load: (_) async => Publication.admit(epub()),
        );
        await reader.bind(fixture.session, [book]);
        await reader.open(book, edition);
        reader.acceptVisible(reader.token, visible);
        await reader.addBookmark(title: 'Original unsynced bookmark');
        await reader.flush();
        final preferences = await SharedPreferences.getInstance();
        final key = 'bookfin.playback.v1.${fixture.session.scope.key}';
        final healthy = preferences.getString(key)!;
        final damaged = jsonDecode(healthy) as Map<String, dynamic>;
        damage.value(damaged);
        final raw = jsonEncode(damaged);
        await preferences.setString(key, raw);
        await expectLater(
          reader.addBookmark(title: 'New pending bookmark'),
          completes,
        );
        expect(reader.message, contains('not saved'));
        expect(preferences.getString(key), raw);
        final sync = RecordSync(records: records)..bind(fixture.session);
        await expectLater(sync.synchronize(), completes);
        expect(sync.message, contains('could not be read'));
        expect(preferences.getString(key), raw);
        sync.dispose();
        await preferences.setString(key, healthy);
        await expectLater(reader.flush(), completes);
        final saved = (await records.reading.read(fixture.session.scope.key))!;
        expect(
          (saved['bookmarks'] as List).map((mark) => mark['title']),
          unorderedEquals([
            'Original unsynced bookmark',
            'New pending bookmark',
          ]),
        );
        final journal =
            (jsonDecode(preferences.getString(key)!) as Map)['sync']
                as Map<String, dynamic>;
        final originalPending =
            (jsonDecode(healthy) as Map)['sync']['pending'] as List;
        expect(journal['pending'], containsAll(originalPending));
        RecordJournal(
          fixture.session.scope.key,
          journal['replica'] as String,
          journal,
        ).checkInvariants();
        reader.dispose();
        await reader.flush();
        downloads.dispose();
      },
    );
  }

  test('invalid persisted journal references are normal format errors, not failed internal invariants', () {
    for (final saved in [
      {
        'version': 1,
        'replica': 'local',
        'actions': null,
        'pending': [],
        'cursor': 0,
      },
      {
        'version': 1,
        'replica': 'local',
        'actions': [],
        'pending': [7],
        'cursor': 0,
      },
      {
        'version': 1,
        'replica': 'local',
        'actions': [],
        'pending': ['missing'],
        'cursor': 0,
      },
      {
        'version': 1,
        'replica': 'local',
        'actions': [],
        'pending': [],
        'cursor': '0',
      },
    ]) {
      expect(
        () => RecordJournal('alice', 'local', saved),
        throwsFormatException,
      );
    }
  });
}
