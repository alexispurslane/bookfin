import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart' show Edition;
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/session.dart'
    show PlaceOrigin, ReadingChanges, ReadingStore;
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';

class SyncFixture {
  SyncFixture._(this.server) {
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    session = JellyfinSession(
      scope: AccountScope(server: origin, serverId: 'server', userId: 'alice'),
      token: 'fixture-token',
      username: 'Alice',
      canDownload: true,
    );
    client = JellyfinClient(origin, deviceId: 'host-regression');
    server.listen(_respond);
  }
  final HttpServer server;
  late final JellyfinSession session;
  late final JellyfinClient client;
  final objects = <String, Map<String, dynamic>>{};

  /// When set, a discovery request after this sequence fails with a server
  /// error, as when the connection drops between pages.
  int? failDiscoveryAfter;

  /// When set, Jellyfin has no Bookfin Storage plugin: its routes are not
  /// found.
  bool pluginMissing = false;

  static Future<SyncFixture> open() async =>
      SyncFixture._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  void publish(RecordJournal journal) {
    for (final action in journal.uploads) {
      final identity = RecordJournal.identity(action);
      objects.putIfAbsent(
        identity,
        () => {
          'Id': identity,
          'Sequence': objects.length + 1,
          'Payload': jsonEncode(action),
          'Deleted': false,
        },
      );
    }
  }

  Future<void> _respond(HttpRequest request) async {
    Object value;
    if (request.uri.path == '/System/Info/Public') {
      value = {'Id': 'server'};
    } else {
      expect(
        request.headers.value('Authorization'),
        contains('Token="fixture-token"'),
      );
      if (pluginMissing &&
          request.uri.pathSegments.contains('BookfinStorage')) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/Users/Me') {
        value = {
          'Id': 'alice',
          'Name': 'Alice',
          'Policy': {'EnableContentDownloading': true},
        };
      } else if (request.method == 'PUT') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final identity = request.uri.pathSegments.last;
        final previous = objects[identity];
        if (previous != null && previous['Payload'] != body['Payload']) {
          request.response.statusCode = 409;
          await request.response.close();
          return;
        }
        value = objects.putIfAbsent(
          identity,
          () => {
            'Id': identity,
            'Sequence': objects.length + 1,
            'Payload': body['Payload'],
            'Deleted': false,
          },
        );
      } else if (request.uri.pathSegments.length == 4) {
        final stored = objects[request.uri.pathSegments.last];
        if (stored == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        value = stored;
      } else {
        final after = int.parse(request.uri.queryParameters['after']!);
        if (failDiscoveryAfter case final limit? when after >= limit) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
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
          'HasMore': available.length > page.length,
        };
      }
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> close() async {
    client.close();
    await server.close(force: true);
  }
}

class HeldRecords extends ResumeStore implements ListeningStore, ReadingStore {
  HeldRecords(this.delegate);
  final ResumeStore delegate;
  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      delegate.acceptSnapshot(accountKey, value);
  @override
  Future<PlaceOrigin> origin(String accountKey, Edition edition) async =>
      switch (delegate) {
        final ReadingStore reading => reading.origin(accountKey, edition),
        _ => (own: null, elsewhere: false, device: null),
      };
  Completer<void>? readReady;
  Completer<void>? readRelease;
  Completer<void>? writeReady;
  Completer<void>? writeRelease;

  void holdRead() {
    readReady = Completer<void>();
    readRelease = Completer<void>();
  }

  void holdWrite() {
    writeReady = Completer<void>();
    writeRelease = Completer<void>();
  }

  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    final saved = await delegate.read(accountKey);
    if (readReady != null && !readReady!.isCompleted) {
      readReady!.complete();
      await readRelease!.future;
    }
    return saved;
  }

  Future<void> _heldWrite() async {
    if (writeReady != null && !writeReady!.isCompleted) {
      writeReady!.complete();
      await writeRelease!.future;
    }
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    await _heldWrite();
    await delegate.write(accountKey, value);
  }

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    await _heldWrite();
    await (delegate as ListeningStore).save(accountKey, changes);
  }

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) async {
    await _heldWrite();
    await (delegate as ReadingStore).saveReading(accountKey, changes);
  }
}
