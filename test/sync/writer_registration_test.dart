import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' as audio;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' as reading;
import 'fixture.dart';
import 'phone.dart';
import '../playback/incremental_save_test.dart' show bookmark;
import 'stale_domains_test.dart' show readingBookmark;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();

  test('a writer stops participating after it unregisters', () async {
    SharedPreferences.setMockInitialValues({});
    final records = LocalResumeStore();
    var flushes = 0;
    var refreshes = 0;
    final unregister = records.registerWriter(
      account: () => 'alice',
      flush: () async => flushes++,
      refresh: () async => refreshes++,
    );
    await records.flushWriters();
    expect(flushes, 1);
    final remote = RecordJournal('alice', 'remote')
      ..change(jsonEncode(['audio', 'bookmarks', 'a']), bookmark('a'));
    await records.receivePage('alice', remote.uploads, 1);
    unregister();
    unregister();
    await records.flushWriters();
    await records.refreshWriters('alice');
    expect(flushes, 1);
    expect(refreshes, 0);
  });

  test(
    'a domain signal notifies only the account and domain that changed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final records = LocalResumeStore();
      final heard = <String>[];
      records
          .staleNotifier('alice')
          .addListener(() => heard.add('alice audio'));
      records.reading
          .staleNotifier('alice')
          .addListener(() => heard.add('alice reading'));
      records.staleNotifier('bob').addListener(() => heard.add('bob audio'));
      final remote = RecordJournal('alice', 'remote')
        ..change(
          jsonEncode(['reading', 'bookmarks', 'r']),
          readingBookmark('r'),
        );
      await records.receivePage('alice', remote.uploads, 1);
      expect(heard, ['alice reading']);
      await records.receivePage('alice', remote.uploads, 1);
      expect(heard, ['alice reading']);
      records.reading.acceptSnapshot(
        'alice',
        await records.reading.read('alice'),
      );
      expect(heard, ['alice reading', 'alice reading']);
      expect(records.reading.staleNotifier('alice').value, isFalse);
    },
  );

  test('refresh uses the current account of a registered writer', () async {
    SharedPreferences.setMockInitialValues({});
    final records = LocalResumeStore();
    var currentAccount = 'alice';
    var refreshes = 0;
    records.registerWriter(
      account: () => currentAccount,
      flush: () async {},
      refresh: () async => refreshes++,
    );
    final remote = RecordJournal('alice', 'remote')
      ..change(jsonEncode(['audio', 'bookmarks', 'a']), bookmark('a'));
    await records.receivePage('alice', remote.uploads, 1);
    currentAccount = 'bob';
    await records.refreshWriters('alice');
    expect(refreshes, 0);
    currentAccount = 'alice';
    await records.refreshWriters('alice');
    expect(refreshes, 1);
  });

  test('editing pending uploads cannot change a retained action', () async {
    SharedPreferences.setMockInitialValues({});
    final records = LocalResumeStore();
    await records.write('alice', {
      'bookmarks': [bookmark('kept', title: 'Original')],
    });
    final pending = await records.pendingUploads('alice');
    (pending.single['value'] as Map)['title'] = 'Edited';
    pending.clear();
    final retained = await records.pendingUploads('alice');
    expect(retained.single['value']['title'], 'Original');
    expect(
      (await records.read('alice'))!['bookmarks'].single['title'],
      'Original',
    );
  });

  test(
    'an invalid page cursor cannot replace saved records or their cursor',
    () async {
      SharedPreferences.setMockInitialValues({});
      final records = LocalResumeStore();
      final remote = RecordJournal('alice', 'remote')
        ..change(
          jsonEncode(['audio', 'bookmarks', 'kept']),
          bookmark('kept', title: 'Original'),
        );
      await records.receivePage('alice', remote.uploads, 1);
      remote.change(
        jsonEncode(['audio', 'bookmarks', 'kept']),
        bookmark('kept', title: 'Invalid page'),
      );
      for (final cursor in [-1, 0]) {
        await expectLater(
          records.receivePage('alice', remote.uploads, cursor),
          throwsArgumentError,
        );
        final restarted = LocalResumeStore();
        expect(await restarted.discoveryCursor('alice'), 1);
        expect(
          (await restarted.read('alice'))!['bookmarks'].single['title'],
          'Original',
        );
      }
    },
  );

  test(
    'a synchronous flush bug still lets the other writer finish saving',
    () async {
      SharedPreferences.setMockInitialValues({});
      final records = LocalResumeStore();
      final bug = StateError('broken writer');
      records.registerWriter(
        account: () => 'alice',
        flush: () => throw bug,
        refresh: () async {},
      );
      records.reading.registerWriter(
        account: () => 'alice',
        flush: () => records.reading.write('alice', {
          'bookmarks': [readingBookmark('saved')],
        }),
        refresh: () async {},
      );
      await expectLater(records.flushWriters(), throwsA(same(bug)));
      expect((await records.reading.read('alice'))?['bookmarks'], hasLength(1));
    },
  );

  for (final reads in [false, true]) {
    test(
      'sync flushes the ${reads ? 'reader' : 'player'} that registered with its store',
      () async {
        SharedPreferences.setMockInitialValues({});
        final phone = await Phone.open('registered-writer');
        final server = await SyncFixture.open();
        addTearDown(server.close);
        final downloads = audio.LocalFiles()
          ..files[reading.source.key] = Uri.file('/verified.epub');
        addTearDown(downloads.dispose);
        final player = Playback(
          downloads: downloads,
          engine: audio.TestEngine(),
          store: phone.store,
        );
        final reader = ReaderSession(
          downloads: downloads,
          store: phone.store.reading,
          load: (_) async => Publication.admit(epub()),
        );
        addTearDown(() async {
          await player.close();
          reader.dispose();
          await reader.flush();
        });
        await player.bind(server.session, [audio.title]);
        await reader.bind(server.session, [reading.book]);
        if (reads) {
          await reader.open(reading.book, reading.edition);
          reader.acceptVisible(reader.token, reading.visible);
          await reader.flush();
        } else {
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.flush();
        }
        final sql = await phone.separateConnection();
        await sql.execute(
          "CREATE TRIGGER refuse_save BEFORE INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'storage full'); END",
        );
        if (reads) {
          await reader.addBookmark(title: 'Kept until sync');
          expect(reader.saveFailed, isTrue);
        } else {
          await player.addBookmark(title: 'Kept until sync');
          expect(player.unsavedChanges, isTrue);
        }
        await sql.execute('DROP TRIGGER refuse_save');

        // No list of writers is supplied to the coordinator. Omitting either
        // writer's registration must leave its failed bookmark unsent here.
        final sync = RecordSync(records: phone.store)
          ..suspend()
          ..bind(server.session);
        addTearDown(sync.dispose);
        await sync.syncNow();
        final sentTitles = [
          for (final object in server.objects.values)
            (jsonDecode(object['Payload'] as String) as Map)['value']?['title'],
        ];
        expect(sentTitles, contains('Kept until sync'));
        expect(reads ? reader.saveFailed : player.unsavedChanges, isFalse);
      },
    );
  }
}
