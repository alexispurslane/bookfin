import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'batch_api_test.dart' show BatchApi, ConnectedTransport;
import 'phone.dart';
import '../support/record_reads.dart';
import '../playback/playback_test.dart' show recording;
import '../playback/playback_test.dart' as audio;
import '../reader/session_test.dart' as reading;
import '../reader/publication_test.dart' show epub;
import 'restore_current_test.dart' show Disk, damageActions, isolated;

Map<String, dynamic> bookmark(String id) => {
  'id': id,
  'position': {
    'edition': 'book',
    'source': 'file',
    'revision': 'one',
    'milliseconds': 100,
  },
  'createdAt': '2026-01-01T00:00:00Z',
  'bookTitle': 'Book',
  'editionLabel': 'Audio',
};

class UnsafePageApi extends BatchApi {
  UnsafePageApi(this.fault);
  final String fault;
  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    final page = await super.send(
      uri,
      method: method,
      headers: headers,
      body: body,
    );
    if (!uri.queryParameters.containsKey('after')) return page;
    return switch (fault) {
      'whole page' => {...page, 'Objects': null},
      'unsafe cursor' => {...page, 'Cursor': (page['Cursor'] as int) + 1},
      'no advance' => {
        ...page,
        'Objects': [],
        'HasMore': true,
        'Cursor': int.parse(uri.queryParameters['after']!),
      },
      _ => {
        ...page,
        'Objects': [
          for (final object in page['Objects'] as List)
            {...object as Map, 'Sequence': 0},
        ],
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final batch in [false, true]) {
    group(batch ? 'batch discovery' : 'legacy discovery', () {
      late BatchApi api;
      late JellyfinSession session;
      late JellyfinClient client;
      late Phone phone;
      late String account;
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        api = BatchApi()..version = batch ? '0.2.0.0' : null;
        session = JellyfinSession(
          scope: AccountScope(
            server: Uri.parse('http://localhost'),
            serverId: 'server',
            userId: 'alice',
          ),
          token: 'test',
          username: 'Alice',
          canDownload: true,
        );
        account = session.scope.key;
        client = JellyfinClient(
          session.scope.server,
          deviceId: 'test',
          transport: api,
        );
        addTearDown(client.close);
        phone = await Phone.open('unreadable-discovery');
      });
      Map<String, dynamic> publish(String author, String id) {
        final journal = RecordJournal(account, author);
        journal.change(jsonEncode(['audio', 'bookmarks', id]), bookmark(id));
        final action = journal.uploads.single;
        return api.put(RecordJournal.identity(action), jsonEncode(action));
      }

      test(
        'moving preference records to SQLite retains unreadable originals',
        () async {
          final object = publish('bad', 'bad')
            ..['Payload'] = ' original {broken';
          final preferences = LocalResumeStore();
          await preferences.receiveObjects(account, [object], 1);
          expect(await preferences.unreadableCount(account), 1);
          await phone.store.read(account);
          expect(await phone.store.unreadableCount(account), 1);
          await phone.restart();
          expect(
            jsonDecode(
              (await phone.database.retainedObjects(account)).single['body']
                  as String,
            ),
            object,
          );
        },
      );

      test('file damage during preference migration keeps every unreadable original', () async {
        final object = publish('bad', 'bad')..['Payload'] = ' original {broken';
        final preferences = LocalResumeStore();
        await preferences.receiveObjects(account, [object], 1);
        final saved = (await SharedPreferences.getInstance()).getString(
          'bookfin.playback.v1.$account',
        )!;
        final original = ((jsonDecode(saved) as Map)['retainedObjects'] as List)
            .single['body'];
        var damaged = false;
        Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
          final result = await isolated(work, input);
          if (!damaged &&
              input is ({String account, String text, bool database}) &&
              input.database) {
            damaged = true;
            await damageActions(
              Disk(phone.path, phone.database),
              index: 'record_objects',
            );
          }
          return result;
        }

        phone.store = LocalResumeStore(
          openDatabase: () async => phone.database,
          hop: hop,
        );
        await phone.store.read(account);
        expect(damaged, isTrue);
        expect(phone.database.keptFile, isNotNull);
        expect(await phone.store.unreadableCount(account), 1);
        expect(await phone.store.discoveryCursor(account), 1);
        await phone.restart();
        expect(await phone.store.unreadableCount(account), 1);
        expect(await phone.store.discoveryCursor(account), 1);
        expect(
          (await phone.database.retainedObjects(account)).single['body'],
          original,
        );
        await phone.store.checkInvariants();
      });

      test('a readable replacement cannot overwrite a retained unreadable identity', () async {
        final object = publish('bad', 'bad');
        final originalPayload = object['Payload'];
        object['Payload'] = 'original broken';
        await phone.store.receiveObjects(account, [object], 1);
        await phone.restart();
        await expectLater(
          phone.store.receiveObjects(account, [
            {...object, 'Payload': originalPayload},
          ], 1),
          throwsFormatException,
        );
        expect((await phone.store.read(account))!['bookmarks'], isEmpty);
        expect(await phone.store.unreadableCount(account), 1);
      });

      test(
        'unreadable originals survive authoritative-file reconstruction',
        () async {
          final object = publish('bad', 'bad')..['Payload'] = 'original broken';
          final good = publish('good', 'good');
          await phone.store.receiveObjects(account, [object, good], 2);
          await phone.restart();
          await phone.store.read(account);
          final disk = Disk(phone.path, phone.database)..store = phone.store;
          await damageActions(disk, index: 'record_action_own');
          await expectLater(
            phone.store.origin(account, recording),
            throwsA(anything),
          );
          expect(phone.database.keptFile, isNotNull);
          await phone.store.read(account);
          await phone.restart();
          expect(await phone.store.unreadableCount(account), 1);
          expect(
            jsonDecode(
              (await phone.database.retainedObjects(account)).single['body']
                  as String,
            ),
            object,
          );
        },
      );

      test('unavailable retained originals block reconstruction instead of losing the count', () async {
        final object = publish('bad', 'bad')..['Payload'] = 'original broken';
        final good = publish('good', 'good');
        await phone.store.receiveObjects(account, [object, good], 2);
        await phone.restart();
        await phone.store.read(account);
        final disk = Disk(phone.path, phone.database)..store = phone.store;
        final original = await damageActions(disk, index: 'record_objects');
        await expectLater(
          phone.store.retryUnreadable(account),
          throwsA(anything),
        );
        expect(phone.database.keptFile, isNotNull);
        await expectLater(phone.store.read(account), throwsFormatException);
        await File(phone.database.keptFile!)
            .writeAsBytes(original, flush: true);
        expect((await phone.store.read(account))!['bookmarks'], hasLength(1));
        expect(await phone.store.unreadableCount(account), 1);
        await phone.restart();
        expect(await phone.store.unreadableCount(account), 1);
      });

      test(
        'kept-file recovery restores the unreadable originals and count',
        () async {
          final object = publish('bad', 'bad')..['Payload'] = 'original broken';
          await phone.store.receiveObjects(account, [object], 1);
          await expectLater(
            phone.database.setAsideDamaged(),
            throwsA(anything),
          );
          await phone.restart();
          await phone.store.recoverKept();
          expect(await phone.store.unreadableCount(account), 1);
          expect(
            jsonDecode(
              (await phone.database.retainedObjects(account)).single['body']
                  as String,
            ),
            object,
          );
        },
      );

      test('a transaction failure retains pending local writes and none of the page', () async {
        await phone.store.write(account, {
          'version': 3,
          'bookmarks': [bookmark('local')],
        });
        final pending = await phone.store.pendingUploads(account);
        final objects = [
          publish('good', 'good'),
          publish('bad', 'bad')..['Payload'] = '{broken',
        ];
        await phone.killDuring('record_objects', () async {
          await phone.store.receiveObjects(account, objects, 2);
        });
        await phone.restart();
        expect(await phone.store.discoveryCursor(account), 0);
        expect(await phone.store.unreadableCount(account), 0);
        expect(await phone.store.pendingUploads(account), pending);
        expect((await phone.store.read(account))!['bookmarks'], [
          bookmark('local'),
        ]);
        await phone.store.receiveObjects(account, objects, 2);
        await phone.store.receiveObjects(account, objects, 2);
        await phone.restart();
        expect(await phone.store.unreadableCount(account), 1);
        expect(await phone.store.pendingUploads(account), pending);
        expect((await phone.store.read(account))!['bookmarks'], hasLength(2));
        expect(await phone.store.unreadableCount('other-account'), 0);
        expect(await phone.database.retainedObjects('other-account'), isEmpty);
      });

      test(
        'a tombstone retains local history and its immutable original',
        () async {
          final first = publish('author', 'mark');
          await phone.store.receiveObjects(account, [first], 1);
          final tombstone = {
            ...first,
            'Sequence': 2,
            'Deleted': true,
            'Payload': null,
          };
          await phone.store.receiveObjects(account, [tombstone], 2);
          await phone.restart();
          expect((await phone.store.read(account))!['bookmarks'], [
            bookmark('mark'),
          ]);
          expect(
            (await phone.database.load(account))!['sync']['actions'],
            hasLength(1),
          );
          expect(
            jsonDecode(
              (await phone.database.retainedObjects(account)).single['body']
                  as String,
            ),
            tombstone,
          );
        },
      );

      test('a future envelope leaves dependent records waiting without hiding independent conflicts', () async {
        final first = publish('future', 'first');
        final action =
            jsonDecode(first['Payload'] as String) as Map<String, dynamic>;
        first['Payload'] = jsonEncode({...action, 'version': 99});
        final dependent = {
          ...action,
          'sequence': 2,
          'context': {'future': 1},
          'record': jsonEncode(['audio', 'bookmarks', 'dependent']),
          'value': bookmark('dependent'),
        };
        final later = api.put('action.future.2', jsonEncode(dependent));
        final a = publish('a', 'conflict');
        final b = publish('b', 'conflict');
        await phone.store.receiveObjects(account, [first, later, a, b], 4);
        await phone.restart();
        expect((await phone.store.read(account))!['bookmarks'], [
          bookmark('conflict'),
        ]);
        expect(await phone.store.conflicts(account), hasLength(1));
        final state = (await phone.database.load(account))!;
        expect(state['coverage'], {'a': 1, 'b': 1});
        expect(state['sync']['actions'], hasLength(3));
        await phone.store.checkInvariants();
      });

      test('a known envelope with an unknown kind still supplies real causal coverage', () async {
        final remote = RecordJournal(account, 'future');
        remote.change(jsonEncode(['reading', 'highlights', 'one']), {
          'quote': 'kept',
        });
        remote.change(
          jsonEncode(['audio', 'bookmarks', 'later']),
          bookmark('later'),
        );
        final objects = [
          for (final action in remote.uploads)
            api.put(RecordJournal.identity(action), jsonEncode(action)),
        ];
        await phone.store.receiveObjects(account, objects, 2);
        await phone.restart();
        expect(await phone.store.unreadableCount(account), 1);
        expect((await phone.store.read(account))!['bookmarks'], [
          bookmark('later'),
        ]);
        expect((await phone.database.load(account))!['coverage'], {
          'future': 2,
        });
        await phone.store.retryUnreadable(account);
        expect(await phone.store.unreadableCount(account), 1);
        await phone.store.checkInvariants();
      });

      test(
        'a later interpreter admits a kept original without deleting its bytes',
        () async {
          final object = publish('newer', 'mark');
          await phone.store.receivePage(account, [], 1);
          final sql = await phone.separateConnection();
          await sql.insert('record_objects', {
            'account': account,
            'identity': object['Id'],
            'sequence': 1,
            'body': jsonEncode(object),
            'unreadable': 1,
          });
          await phone.restart();
          expect(await phone.store.unreadableCount(account), 1);
          await phone.store.retryUnreadable(account);
          await phone.restart();
          expect(await phone.store.unreadableCount(account), 0);
          expect((await phone.store.read(account))!['bookmarks'], [
            bookmark('mark'),
          ]);
          expect(
            (await phone.database.retainedObjects(account)).single['body'],
            jsonEncode(object),
          );
        },
      );

      test(
        'a malformed preserved-version reference cannot strand the next page',
        () async {
          final first = publish('first', 'first');
          final object = publish('bad', 'bad');
          object['Payload'] = jsonEncode({
            ...jsonDecode(object['Payload'] as String) as Map,
            'context': {'first': 1},
            'preserve': ['action.first.1'],
          });
          final later = publish('later', 'later');
          await RecordTransport(phone.store).synchronize(session, client);
          expect(await phone.store.discoveryCursor(account), 3);
          expect((await phone.store.read(account))!['bookmarks'], [
            bookmark('first'),
            bookmark('later'),
          ]);
          expect(await phone.store.unreadableCount(account), 1);
          await phone.restart();
          await RecordTransport(phone.store).synchronize(session, client);
          expect(await phone.store.unreadableCount(account), 1);
          expect(await phone.store.discoveryCursor(account), later['Sequence']);
          expect((await phone.database.load(account))!['coverage'], {
            'first': 1,
            'later': 1,
          });
          expect(first['Id'], 'action.first.1');
        },
      );

      test('a page that repairs an audio original also refreshes newly received reading records', () async {
        final original = publish('remote', 'audio');
        await phone.store.receiveObjects(account, [original], 1);
        final sql = await phone.separateConnection();
        final action =
            jsonDecode(original['Payload'] as String) as Map<String, dynamic>;
        await sql.update(
          'record_actions',
          {
            'payload': jsonEncode({
              ...action,
              'value': {...bookmark('audio'), 'title': 'damaged'},
            }),
          },
          where: 'account = ?',
          whereArgs: [account],
        );
        await phone.restart();
        phone.store.reading.acceptSnapshot(
          account,
          await phone.store.reading.read(account),
        );
        expect(phone.store.reading.staleNotifier(account).value, isFalse);
        final reading = RecordJournal(account, 'reader');
        reading.change(jsonEncode(['reading', 'bookmarks', 'text']), {
          'id': 'text',
          'position': {
            'edition': 'text',
            'source': 'file',
            'revision': 'one',
            'anchor': 'page',
          },
          'createdAt': '2026-01-01T00:00:00Z',
        });
        final page = [
          original,
          api.put('action.reader.1', jsonEncode(reading.uploads.single)),
          publish('bad', 'bad')..['Payload'] = '{broken',
        ];
        await phone.killDuring('record_versions', () async {
          await phone.store.receiveObjects(account, page, 3);
        });
        expect(await phone.store.discoveryCursor(account), 1);
        expect(await phone.store.unreadableCount(account), 0);
        phone.store.reading.acceptSnapshot(
          account,
          await phone.store.reading.read(account),
        );
        expect(await phone.store.receiveObjects(account, page, 3), 1);
        expect(phone.store.reading.staleNotifier(account).value, isTrue);
        await phone.restart();
        expect(
          (await phone.store.reading.read(account))!['bookmarks'],
          hasLength(1),
        );
        expect(await phone.store.unreadableCount(account), 1);
        expect((await phone.store.read(account))!['bookmarks'], [
          bookmark('audio'),
        ]);
      });

      test('a preserved version received later releases its waiting action on retry', () async {
        final first = publish('first', 'mark');
        final next = publish('next', 'mark');
        next['Payload'] = jsonEncode({
          ...jsonDecode(next['Payload'] as String) as Map,
          'context': {'first': 1},
          'preserve': ['action.first.1'],
        });
        await phone.store.receiveObjects(account, [next], 2);
        expect((await phone.store.read(account))!['bookmarks'], isEmpty);
        expect(await phone.store.unreadableCount(account), 0);
        await phone.restart();
        await phone.store.receiveObjects(account, [first], 3);
        await phone.store.retryUnreadable(account);
        expect(await phone.store.conflicts(account), hasLength(1));
        await phone.restart();
        expect(await phone.store.conflicts(account), hasLength(1));
        expect(
          (await phone.database.retainedObjects(account)).single['unreadable'],
          0,
        );
      });

      test(
        'a pending local action retired by the server cannot strand discovery',
        () async {
          await phone.store.write(account, {
            'version': 3,
            'bookmarks': [bookmark('local')],
          });
          final pending = (await phone.store.pendingUploads(account)).single;
          final id = RecordJournal.identity(pending);
          api.put(id, jsonEncode(pending))['Deleted'] = true;
          api.reject = id;
          api.rejectedStatus = 410;
          for (var i = 0; i < 9; i++) {
            publish('later$i', 'later$i');
          }
          final sync = RecordSync(
            records: phone.store,
            transport: ConnectedTransport(phone.store, client),
          );
          addTearDown(sync.dispose);
          sync.bind(session);
          await sync.synchronize();
          expect(await phone.store.discoveryCursor(account), 10);
          expect(
            (await phone.store.read(account))!['bookmarks'],
            hasLength(10),
          );
          expect(sync.lastSyncNotifier.value?.failure?.name, 'uploadRejected');
          expect(sync.lastSyncNotifier.value?.synced, isNull);
          expect(await phone.store.pendingUploads(account), [pending]);
          await phone.restart();
          await expectLater(
            RecordTransport(phone.store).synchronize(session, client),
            throwsA(isA<CatalogFailure>()),
          );
          expect(await phone.store.unreadableCount(account), 1);
          expect(await phone.store.pendingUploads(account), [pending]);
        },
      );

      test('a rejected upload still delivers later records to live Playback and reader sessions', () async {
        final downloads = audio.LocalFiles()
          ..files[reading.source.key] = Uri.file('/verified.epub');
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
          downloads.dispose();
        });
        await player.bind(session, [audio.title]);
        await reader.bind(session, [reading.book]);
        await reader.open(reading.book, reading.edition);
        final sync = RecordSync(
          records: phone.store,
          transport: ConnectedTransport(phone.store, client),
        )..suspend();
        addTearDown(sync.dispose);
        sync.bind(session);
        await sync.synchronize();
        await sync.recoverKept();
        final completed = sync.lastSyncNotifier.value!.synced;
        expect(completed, isNotNull);
        await phone.store.write(account, {
          'version': 3,
          'bookmarks': [bookmark('local')],
        });
        final pending = (await phone.store.pendingUploads(account)).single;
        final id = RecordJournal.identity(pending);
        api.put(id, jsonEncode(pending))['Deleted'] = true;
        api.reject = id;
        api.rejectedStatus = 410;
        final text = RecordJournal(account, 'reader');
        for (var pass = 1; pass <= 2; pass++) {
          publish('later$pass', 'later$pass');
          text.change(jsonEncode(['reading', 'bookmarks', 'text$pass']), {
            'id': 'text$pass',
            'position': {
              'edition': reading.edition.id,
              'source': reading.source.key,
              'revision': reading.source.revision,
              'anchor': jsonEncode({
                'version': 1,
                'quote': 'A river',
                'cfi': 'epubcfi(/6/2!/4/2/1:0)',
              }),
            },
            'createdAt': '2026-01-01T00:00:00Z',
          });
          final action = text.uploads.last;
          api.put(RecordJournal.identity(action), jsonEncode(action));
          await sync.synchronize();
          expect(
            player.bookmarks.map((mark) => mark.id),
            contains('later$pass'),
          );
          expect(
            reader.bookmarks.map((mark) => mark.id),
            contains('text$pass'),
          );
          expect(sync.lastSyncNotifier.value?.synced, completed);
          expect(sync.lastSyncNotifier.value?.failure?.name, 'uploadRejected');
          expect(await phone.store.pendingUploads(account), [pending]);
        }
      });

      for (final fault in [
        'whole page',
        'unsafe cursor',
        'no advance',
        'unsafe sequence',
      ]) {
        test('$fault fails without admitting part of the page', () async {
          final api = UnsafePageApi(fault)..version = batch ? '0.2.0.0' : null;
          api.put('opaque', '{broken');
          final faultyClient = JellyfinClient(
            session.scope.server,
            deviceId: 'test',
            transport: api,
          );
          addTearDown(faultyClient.close);
          await expectLater(
            RecordTransport(phone.store).synchronize(session, faultyClient),
            throwsA(isA<RecordProtocolFailure>()),
          );
          expect(await phone.store.discoveryCursor(account), 0);
          expect(await phone.store.unreadableCount(account), 0);
          expect(await phone.database.retainedObjects(account), isEmpty);
        });
      }

      test('reopening exposes the account count before any exchange without loading original bodies', () async {
        final good = publish('good', 'good');
        await phone.store.receiveObjects(account, [
          good,
          for (var i = 0; i < 80; i++)
            {
              'Id': 'opaque$i',
              'Sequence': i + 2,
              'Deleted': false,
              'Payload': 'opaque-original-$i {broken',
            },
        ], 81);
        await phone.database.close();
        final port = ReceivePort();
        final replies = <RecordQuery>[];
        final subscription = port.listen(
          (value) => replies.addAll((value as List).cast<RecordQuery>()),
        );
        addTearDown(() async {
          await subscription.cancel();
          port.close();
        });
        phone.database = await RecordDatabase.open(
          factory: ObservedFiles(databaseFactoryFfi, port.sendPort),
          path: phone.path,
        );
        phone.store = LocalResumeStore(
          openDatabase: () async => phone.database,
        );
        final sync = RecordSync(records: phone.store)
          ..suspend()
          ..bind(session);
        addTearDown(sync.dispose);
        await phone.store.unreadableCount(account);
        expect(sync.unreadableNotifier.value, 80);
        expect(sync.lastSyncNotifier.value, isNull);
        await pumpEventQueue();
        expect(replies, isNotEmpty);
        expect(
          [
                for (final reply in replies)
                  for (final row in reply.rows) ...row.values,
              ]
              .whereType<String>()
              .any((value) => value.contains('opaque-original-')),
          isFalse,
        );
      });

      test('redelivery counts one unreadable identity while keeping both wire events', () async {
        final first = {
          'Id': 'same-object',
          'Sequence': 1,
          'Deleted': false,
          'Payload': ' original broken',
        };
        final next = {...first, 'Sequence': 2};
        await phone.store.receiveObjects(account, [first, next], 2);
        await phone.store.receiveObjects(account, [first, next], 2);
        await phone.restart();
        expect(await phone.store.unreadableCount(account), 1);
        expect(await phone.database.retainedObjects(account), hasLength(2));
      });

      test('successful later delivery has its own quiet outcome', () async {
        publish('bad', 'bad')['Payload'] = '{broken';
        publish('good', 'good');
        final sync = RecordSync(
          records: phone.store,
          transport: ConnectedTransport(phone.store, client),
        );
        addTearDown(sync.dispose);
        sync.bind(session);
        await sync.synchronize();
        expect(sync.lastSyncNotifier.value?.failure?.name, 'remoteUnreadable');
        expect(sync.lastSyncNotifier.value?.synced, isNotNull);
        expect(sync.message, isNull);
        expect((await phone.store.read(account))!['bookmarks'], hasLength(1));
      });
      for (final bad in [
        'invalid JSON',
        'unknown version',
        'unknown kind',
        'malformed payload type',
        'malformed value',
        'tombstone',
      ]) {
        test(
          'keeps $bad between valid records and receives later pages and the next sync',
          () async {
            publish('first', 'first');
            final object = publish('bad', 'bad');
            if (bad == 'invalid JSON') {
              object['Payload'] = ' {broken\n original';
            }
            if (bad == 'unknown version') {
              object['Payload'] = jsonEncode({
                ...jsonDecode(object['Payload'] as String) as Map,
                'version': 99,
              });
            }
            if (bad == 'malformed value') {
              object['Payload'] = jsonEncode({
                ...jsonDecode(object['Payload'] as String) as Map,
                'value': {'id': 'bad'},
              });
            }
            if (bad == 'tombstone') object['Deleted'] = true;
            if (bad == 'malformed payload type') {
              object['Payload'] = ['original'];
            }
            if (bad == 'unknown kind') {
              object['Payload'] = jsonEncode({
                ...jsonDecode(object['Payload'] as String) as Map,
                'record': jsonEncode(['audio', 'history', 'bad']),
                'value': {'id': 'bad', 'kind': 'futureMove'},
              });
            }
            for (var i = 0; i < 260; i++) {
              publish('later$i', 'later$i');
            }
            await RecordTransport(phone.store).synchronize(session, client);
            expect(await phone.store.discoveryCursor(account), 262);
            expect(
              (await phone.store.read(account))!['bookmarks'],
              hasLength(261),
            );
            await phone.restart();
            expect(await phone.store.unreadableCount(account), 1);
            final retained = await phone.database.retainedObjects(account);
            expect(jsonDecode(retained.single['body'] as String), object);
            await phone.store.retryUnreadable(account);
            expect(await phone.store.unreadableCount(account), 1);
            publish('next', 'next');
            await RecordTransport(phone.store).synchronize(session, client);
            expect(await phone.store.discoveryCursor(account), 263);
            expect(
              (await phone.store.read(account))!['bookmarks'],
              hasLength(262),
            );
            await phone.store.checkInvariants();
          },
        );
      }
    });
  }
}
