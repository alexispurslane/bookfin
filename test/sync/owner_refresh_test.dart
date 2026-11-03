import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' as reading;
import '../reader/persistence_test.dart' show FailingRecords;
import 'fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture fixture;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await SyncFixture.open();
  });
  tearDown(() => fixture.close());

  test('a failed listening bookmark remains pending across account changes until storage recovers', () async {
    final records = LocalResumeStore();
    final storage = FailingRecords(records)..writable = true;
    final downloads = audio.LocalFiles();
    final player = Playback(
      downloads: downloads,
      engine: audio.TestEngine(),
      store: storage,
    );
    addTearDown(() async {
      await player.close();
      downloads.dispose();
    });
    await player.bind(audio.account(), [audio.title]);
    await player.open(audio.title, audio.recording, autoplay: false);
    storage.writable = false;
    await player.addBookmark(title: 'Unsynced Alice');
    await player.bind(audio.account(user: 'bob'), [audio.title]);
    await player.bind(audio.account(), [audio.title]);
    expect(player.bookmarks.single.title, 'Unsynced Alice');
    storage.writable = true;
    await player.flush();
    final saved = (await records.read(audio.account().scope.key))!;
    expect((saved['bookmarks'] as List).single['title'], 'Unsynced Alice');
  });

  test('a rejected listening refresh cannot make a local save delete an unseen remote bookmark', () async {
    final records = LocalResumeStore();
    final held = HeldRecords(records);
    final downloads = audio.LocalFiles();
    final engine = audio.TestEngine();
    final player = Playback(downloads: downloads, engine: engine, store: held);
    addTearDown(() async {
      await player.close();
      downloads.dispose();
    });
    await player.bind(fixture.session, [audio.title]);
    await player.open(audio.title, audio.recording, autoplay: false);
    await player.addBookmark(title: 'Local A');
    final remote = RecordJournal(fixture.session.scope.key, 'remote');
    remote.change(jsonEncode(['audio', 'bookmarks', 'remote-b']), {
      ...player.bookmarks.single.toJson(),
      'id': 'remote-b',
      'title': 'Remote B',
    });
    fixture.publish(remote);
    await records.synchronize(fixture.session, fixture.client);
    held.holdRead();
    final refreshing = player.refreshPersonalRecords();
    await held.readReady!.future;
    held.holdWrite();
    engine.emit(0, 1900);
    await held.writeReady!.future;
    held.readRelease!.complete();
    await refreshing;
    expect(player.bookmarks.map((mark) => mark.title), ['Local A']);
    held.writeRelease!.complete();
    await player.flush();
    final saved = (await records.read(fixture.session.scope.key))!;
    expect(
      (saved['bookmarks'] as List).map((mark) => mark['title']),
      unorderedEquals(['Local A', 'Remote B']),
    );
    await player.refreshPersonalRecords();
    await player.deleteBookmark('remote-b');
    expect(
      ((await records.read(fixture.session.scope.key))!['bookmarks'] as List)
          .map((mark) => mark['title']),
      ['Local A'],
    );
  });

  test('a reading refresh from an ended account session cannot replace records after returning', () async {
    final records = LocalResumeStore();
    final held = HeldRecords(records.reading);
    final downloads = audio.LocalFiles()
      ..files[reading.source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: held,
      load: (_) async => Publication.admit(epub()),
    );
    addTearDown(() async {
      reader.dispose();
      await reader.flush();
      downloads.dispose();
    });
    await reader.bind(fixture.session, [reading.book]);
    await reader.open(reading.book, reading.edition);
    reader.acceptVisible(reader.token, reading.visible);
    await reader.addBookmark(title: 'Local X');
    held.holdRead();
    final refreshing = reader.refreshPersonalRecords();
    await held.readReady!.future;
    final remote = RecordJournal(fixture.session.scope.key, 'remote');
    remote.change(jsonEncode(['reading', 'bookmarks', 'remote-y']), {
      ...reader.bookmarks.single.toJson(),
      'id': 'remote-y',
      'title': 'Remote Y',
    });
    fixture.publish(remote);
    await records.synchronize(fixture.session, fixture.client);
    await reader.bind(audio.account(user: 'bob'), [reading.book]);
    await reader.bind(fixture.session, [reading.book]);
    await reader.open(reading.book, reading.edition);
    expect(
      reader.bookmarks.map((mark) => mark.title),
      unorderedEquals(['Local X', 'Remote Y']),
    );
    held.readRelease!.complete();
    await refreshing;
    expect(
      reader.bookmarks.map((mark) => mark.title),
      unorderedEquals(['Local X', 'Remote Y']),
    );
    await reader.deleteBookmark('remote-y');
    expect(
      ((await records.reading.read(fixture.session.scope.key))!['bookmarks']
              as List)
          .map((mark) => mark['title']),
      ['Local X'],
    );
  });

  test('a rejected reading refresh cannot make a local save delete an unseen remote bookmark', () async {
    final records = LocalResumeStore();
    final held = HeldRecords(records.reading);
    final downloads = audio.LocalFiles()
      ..files[reading.source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: held,
      load: (_) async => Publication.admit(epub()),
    );
    addTearDown(() async {
      reader.dispose();
      await reader.flush();
      downloads.dispose();
    });
    await reader.bind(fixture.session, [reading.book]);
    await reader.open(reading.book, reading.edition);
    reader.acceptVisible(reader.token, reading.visible);
    await reader.addBookmark(title: 'Local A');
    final remote = RecordJournal(fixture.session.scope.key, 'remote');
    remote.change(jsonEncode(['reading', 'bookmarks', 'remote-b']), {
      ...reader.bookmarks.single.toJson(),
      'id': 'remote-b',
      'title': 'Remote B',
    });
    fixture.publish(remote);
    await records.synchronize(fixture.session, fixture.client);
    held.holdRead();
    final refreshing = reader.refreshPersonalRecords();
    await held.readReady!.future;
    held.holdWrite();
    reader.acceptVisible(
      reader.token,
      const VisibleLocation(
        'epubcfi(/6/2!/4/2/1:8)',
        'OPS/one.xhtml',
        'Changed local page',
      ),
    );
    await held.writeReady!.future;
    held.readRelease!.complete();
    await refreshing;
    expect(reader.bookmarks.map((mark) => mark.title), ['Local A']);
    held.writeRelease!.complete();
    await reader.flush();
    final saved = (await records.reading.read(fixture.session.scope.key))!;
    expect(
      (saved['bookmarks'] as List).map((mark) => mark['title']),
      unorderedEquals(['Local A', 'Remote B']),
    );
    await reader.refreshPersonalRecords();
    await reader.deleteBookmark('remote-b');
    expect(
      ((await records.reading.read(fixture.session.scope.key))!['bookmarks']
              as List)
          .map((mark) => mark['title']),
      ['Local A'],
    );
  });
}
