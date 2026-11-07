import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/covers_io.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<Uri> requests;
  late Map<String, Uint8List?> server;
  var online = true;
  final session = JellyfinSession(
    scope: AccountScope(
      server: Uri.parse('https://books.example/jellyfin'),
      serverId: 'server',
      userId: 'alice',
    ),
    token: 'token',
    username: 'alice',
    canDownload: true,
  );
  late DiskCovers covers;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-covers');
    requests = [];
    online = true;
    server = {
      'graft': Uint8List.fromList([1, 2, 3]),
    };
    covers = DiskCovers(
      root: root,
      fetch: (uri, headers) async {
        requests.add(uri);
        expect(headers['X-Emby-Token'], 'token');
        if (!online) throw const SocketException('offline');
        return server[uri.pathSegments[uri.pathSegments.length - 3]];
      },
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a cover loaded once still shows offline', () async {
    expect(await covers.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
    expect(
      requests.single.path,
      '/jellyfin/Items/graft/Images/Primary',
      reason: 'the server path prefix is kept',
    );
    expect(requests.single.queryParameters['tag'], 'v1');
    online = false;
    final restarted = DiskCovers(
      root: root,
      fetch: (_, _) async => throw const SocketException('offline'),
    );
    expect(await restarted.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
  });

  test('a changed cover replaces the kept copy', () async {
    await covers.load(session, const CoverRef('graft', 'v1'));
    server['graft'] = Uint8List.fromList([9]);
    expect(await covers.load(session, const CoverRef('graft', 'v2')), [9]);
    online = false;
    expect(
      await covers.load(session, const CoverRef('graft', 'v1')),
      isNull,
      reason: 'the old version is removed',
    );
  });

  test('an item without a cover image shows no cover', () async {
    expect(await covers.load(session, const CoverRef('missing', 'v1')), isNull);
  });

  test('an unreachable server shows no cover and tries again later', () async {
    online = false;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), isNull);
    online = true;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), [
      1,
      2,
      3,
    ]);
  });

  test('one cover shown in many places is fetched once', () async {
    await Future.wait([
      for (var index = 0; index < 5; index++)
        covers.load(session, const CoverRef('graft', 'v1')),
    ]);
    expect(requests, hasLength(1));
  });

  test('clearing removes every kept cover', () async {
    await covers.load(session, const CoverRef('graft', 'v1'));
    await covers.clear();
    online = false;
    expect(await covers.load(session, const CoverRef('graft', 'v1')), isNull);
  });
}
