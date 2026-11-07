import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A hop that runs each work item in a new isolate, as production does, and
/// counts the work items.
class CountingHop {
  int hops = 0;

  Future<R> call<M, R>(R Function(M) work, M input) {
    hops++;
    return Isolate.run(() => work(input));
  }
}

Map<String, dynamic> position(int milliseconds) => {
  'edition': 'book',
  'source': 'audio',
  'revision': 'v1',
  'milliseconds': milliseconds,
};

Map<String, dynamic> event(String id) => {
  'id': id,
  'at': '1970-01-01T00:00:00Z',
  'kind': 'pause',
  'bookTitle': 'Hop fixture',
  'editionLabel': 'Audio',
  'before': position(0),
  'after': position(0),
};

Map<String, dynamic> settings() => {
  'version': 3,
  'selected': 'book',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

ListeningChanges resume(int milliseconds) => ListeningChanges(
  settings(),
  resumes: {
    'book': [
      {
        'source': 'audio',
        'revision': 'v1',
        'sources': 'recording',
        'milliseconds': milliseconds,
        'pendingOffline': false,
      },
    ],
  },
);

Map<String, dynamic> page(int sourcePage) => {
  'edition': 'ebook',
  'source': 'pdf',
  'revision': 'r1',
  'anchor': jsonEncode({'page': sourcePage}),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late RecordDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-hop-');
    addTearDown(() => directory.delete(recursive: true));
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/records.sqlite',
    );
    addTearDown(database.close);
  });

  /// Saves a listening account of 20 history events and 30 resume moves,
  /// which is 50 journal actions in 21 records, and one reading place.
  Future<void> seedLargeAccount() async {
    final writer = LocalResumeStore(openDatabase: () async => database);
    await writer.save(
      'alice',
      ListeningChanges(
        settings(),
        history: {
          for (var index = 0; index < 20; index++) 'h$index': event('h$index'),
        },
      ),
    );
    for (var second = 1; second <= 30; second++) {
      await writer.save('alice', resume(second * 1000));
    }
    await writer.reading.write('alice', {
      'version': 1,
      'fontSize': 22,
      'resumes': [page(7)],
      'bookmarks': <dynamic>[],
    });
  }

  test(
    'opening a large account replays its journal in one hop for both domains',
    () async {
      await seedLargeAccount();
      final hop = CountingHop();
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: hop.call,
      );

      final listening = (await store.read('alice'))!;
      final reading = (await store.reading.read('alice'))!;

      expect(hop.hops, 1);
      expect(listening['history'], hasLength(20));
      expect(listening['resumes']['book'].single['milliseconds'], 30000);
      expect(reading['fontSize'], 22);
      expect(reading['resumes'].single['anchor'], jsonEncode({'page': 7}));
      await store.checkInvariants();
    },
  );

  test('a refresh after a change derives the snapshot in one hop', () async {
    await seedLargeAccount();
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );
    final opened = (await store.read('alice'))!;
    store.acceptSnapshot('alice', opened);
    await store.save('alice', resume(31000));
    final before = hop.hops;

    final refreshed = (await store.read('alice'))!;

    expect(hop.hops, before + 1);
    expect(refreshed['resumes']['book'].single['milliseconds'], 31000);
    expect(refreshed['history'], hasLength(20));
  });

  test(
    'a snapshot accepted from a hop read still guards against stale writes',
    () async {
      await seedLargeAccount();
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: CountingHop().call,
      );
      final opened = (await store.read('alice'))!;
      store.acceptSnapshot('alice', opened);
      final before = (await database.load('alice'))!['sync']['actions'] as List;

      // The writer resends the place that it read, which adds no sync action.
      await store.save('alice', resume(30000));

      final after = (await database.load('alice'))!['sync']['actions'] as List;
      expect(after, hasLength(before.length));
    },
  );

  test(
    'a large account in the format before the journal decodes in one hop',
    () async {
      SharedPreferences.setMockInitialValues({
        'bookfin.playback.v1.bob': jsonEncode({
          ...settings(),
          'history': [
            for (var index = 0; index < 40; index++) event('h$index'),
          ],
          'bookmarks': <dynamic>[],
          'resumes': <String, dynamic>{},
        }),
      });
      final hop = CountingHop();
      final store = LocalResumeStore(hop: hop.call);

      final listening = (await store.read('bob'))!;

      expect(hop.hops, 1);
      expect(listening['history'], hasLength(40));
    },
  );
}
