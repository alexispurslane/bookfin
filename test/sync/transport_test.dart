import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  Map<String, dynamic> bookmark(String id) => {
    'id': id,
    'title': 'Offline $id',
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
  late HttpServer server;
  late JellyfinSession session;
  late JellyfinClient client;
  final objects = <String, Map<String, dynamic>>{};
  var acknowledge = true;
  var wrongAccount = false;
  var uploads = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    objects.clear();
    acknowledge = true;
    wrongAccount = false;
    uploads = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    session = JellyfinSession(
      scope: AccountScope(server: origin, serverId: 'server', userId: 'alice'),
      token: 'private-test-token',
      username: 'Alice',
      canDownload: true,
    );
    client = JellyfinClient(origin, deviceId: 'test');
    server.listen((request) async {
      final path = request.uri.path;
      expect(request.uri.queryParameters, isNot(contains('api_key')));
      if (path != '/System/Info/Public') {
        expect(
          request.headers.value('Authorization'),
          contains('Token="private-test-token"'),
        );
      }
      Object value;
      if (path == '/System/Info/Public') {
        value = {'Id': 'server'};
      } else if (path == '/Users/Me') {
        value = {
          'Id': wrongAccount ? 'bob' : 'alice',
          'Name': 'Alice',
          'Policy': {'EnableContentDownloading': true},
        };
      } else if (request.method == 'PUT') {
        uploads++;
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final identity = request.uri.pathSegments.last;
        final previous = objects[identity];
        if (previous != null && previous['Payload'] != body['Payload']) {
          request.response.statusCode = 409;
          await request.response.close();
          return;
        }
        final stored = objects.putIfAbsent(
          identity,
          () => {
            'Id': identity,
            'Sequence': objects.length + 1,
            'Payload': body['Payload'],
            'Deleted': false,
          },
        );
        value = acknowledge ? stored : {...stored, 'Payload': 'unverified'};
      } else {
        final after = int.parse(request.uri.queryParameters['after']!);
        final available =
            objects.values
                .where((value) => (value['Sequence'] as int) > after)
                .toList()
              ..sort(
                (first, second) => (first['Sequence'] as int).compareTo(
                  second['Sequence'] as int,
                ),
              );
        final page = available.take(4).toList();
        value = {
          'Objects': page,
          'Cursor': page.isEmpty ? after : page.last['Sequence'],
          'HasMore': available.length > 4,
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(value));
      await request.response.close();
    });
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  Map<String, dynamic> snapshot(String id) => {
    'version': 3,
    'history': [],
    'resumes': <String, dynamic>{},
    'bookmarks': [bookmark(id)],
  };

  test('unverified upload acknowledgment survives restart and retries the same object', () async {
    await LocalResumeStore().write(session.scope.key, snapshot('one'));
    acknowledge = false;
    await expectLater(
      RecordTransport(LocalResumeStore()).synchronize(session, client),
      throwsFormatException,
    );
    expect(objects, hasLength(1));
    acknowledge = true;
    await RecordTransport(LocalResumeStore()).synchronize(session, client);
    expect(objects, hasLength(1));
    expect(uploads, 2);
    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(
      preferences.getString('bookfin.playback.v1.${session.scope.key}')!,
    ) as Map;
    expect(saved['sync']['pending'], isEmpty);
    expect(
      (await LocalResumeStore().read(session.scope.key))!['bookmarks'],
      hasLength(1),
    );
  });

  test(
    'another authenticated account receives no pending personal records',
    () async {
      await LocalResumeStore().write(session.scope.key, snapshot('one'));
      wrongAccount = true;
      await expectLater(
        RecordTransport(LocalResumeStore()).synchronize(session, client),
        throwsA(isA<CatalogFailure>()),
      );
      expect(uploads, 0);
      expect(objects, isEmpty);
    },
  );

  test('a stale local writer cannot delete a bookmark discovered from another installation', () async {
    final store = LocalResumeStore();
    await store.write(session.scope.key, snapshot('one'));
    await store.read(session.scope.key);
    final remote = RecordJournal(session.scope.key, 'remote');
    remote.change(jsonEncode(['audio', 'bookmarks', 'two']), bookmark('two'));
    final action = remote.uploads.single;
    objects[RecordJournal.identity(action)] = {
      'Id': RecordJournal.identity(action),
      'Sequence': 1,
      'Payload': jsonEncode(action),
      'Deleted': false,
    };
    await RecordTransport(store).synchronize(session, client);
    await store.write(session.scope.key, snapshot('one'));
    expect((await store.read(session.scope.key))!['bookmarks'], hasLength(2));
    expect(await store.conflicts(session.scope.key), isEmpty);
  });

  test('interleaved discovery pages retain each object before advancing the cursor', () async {
    final remote = RecordJournal(session.scope.key, 'remote');
    for (var index = 1; index <= 9; index++) {
      remote.change(jsonEncode(['audio', 'history', '$index']), {
        'id': '$index',
        'at': '1970-01-01T00:00:00Z',
        'kind': 'pause',
        'bookTitle': 'Book',
        'editionLabel': 'Audio',
        'before': bookmark('unused')['position'],
        'after': bookmark('unused')['position'],
      });
      final action = remote.uploads.last;
      final identity = RecordJournal.identity(action);
      objects[identity] = {
        'Id': identity,
        'Sequence': index,
        'Payload': jsonEncode(action),
        'Deleted': false,
      };
    }
    await RecordTransport(LocalResumeStore()).synchronize(session, client);
    expect(
      (await LocalResumeStore().read(session.scope.key))!['history'],
      hasLength(9),
    );
    await RecordTransport(LocalResumeStore()).synchronize(session, client);
    expect(
      (await LocalResumeStore().read(session.scope.key))!['history'],
      hasLength(9),
    );
  });

  test('a malformed remote record cannot advance discovery or replace local records', () async {
    final store = LocalResumeStore();
    await store.write(session.scope.key, snapshot('one'));
    final remote = RecordJournal(session.scope.key, 'remote');
    remote.change(jsonEncode(['audio', 'bookmarks', 'bad']), {'id': 'bad'});
    final action = remote.uploads.single;
    objects[RecordJournal.identity(action)] = {
      'Id': RecordJournal.identity(action),
      'Sequence': 1,
      'Payload': jsonEncode(action),
      'Deleted': false,
    };
    await expectLater(
      RecordTransport(store).synchronize(session, client),
      throwsFormatException,
    );
    final saved = (await store.read(session.scope.key))!;
    expect((saved['bookmarks'] as List).map((value) => value['id']), ['one']);
  });
}
