import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_test.dart' show entry;

typedef _Collection = ({
  String id,
  String name,
  Set<String> libraries,
  List<Map<String, dynamic>> children,
});

/// A loopback fixture for the two source-supported Items dispatch paths.
/// 12.4 scopes BoxSets by linked-child ancestors and filters before paging.
/// 10.11 ignores that parent and pages nonrecursive children before filtering.
/// This models those source paths; it does not run a Jellyfin server.
class _Server {
  late HttpServer server;
  late JellyfinClient client;
  late JellyfinSession session;
  bool legacy = false;
  final libraries = <String, List<Map<String, dynamic>>>{};
  final collections = <_Collection>[];
  final nestedChildren = <String, List<Map<String, dynamic>>>{};
  final requests = <({Map<String, String> query, String? token})>[];
  final childPages = <({String parent, int start, int items})>[];
  int collectionItems = 0;
  int nonBookChildren = 0;
  int optionalFields = 0;
  int membershipBytes = 0;
  int untrimmedMembershipBytes = 0;
  Future<void> Function(HttpRequest)? beforeReply;
  void Function(Map<String, String>, Map<String, dynamic>)? changePage;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    session = account('alice');
    client = JellyfinClient(base, deviceId: 'collections-test');
    server.listen((request) async {
      final query = request.uri.queryParameters;
      requests.add((
        query: query,
        token: request.headers.value('X-Emby-Token'),
      ));
      await beforeReply?.call(request);
      if (request.response.statusCode != 200) {
        await request.response.close();
        return;
      }
      Map<String, dynamic> response;
      if (request.uri.path.endsWith('UserViews')) {
        response = {
          'Items': [
            for (final id in libraries.keys)
              {'Id': id, 'Name': id, 'CollectionType': 'books'},
          ],
        };
      } else {
        final start = int.parse(query['startIndex'] ?? '0');
        final limit = int.parse(query['limit'] ?? '10000');
        final discovering = query['includeItemTypes'] == 'BoxSet';
        final parent = query['parentId'];
        final membership = !discovering && !libraries.containsKey(parent);
        Iterable<Map<String, dynamic>> items;
        if (discovering) {
          items = collections
              .where(
                (set) =>
                    legacy || parent == null || set.libraries.contains(parent),
              )
              .map((set) => {'Id': set.id, 'Name': set.name, 'Type': 'BoxSet'});
        } else if (membership) {
          items = [
            ...collections.singleWhere((set) => set.id == parent).children,
            if (query['recursive'] == 'true') ...?nestedChildren[parent],
          ];
        } else {
          items = libraries[parent]!;
        }
        final types = query['includeItemTypes']?.split(',');
        bool matches(Map<String, dynamic> item) =>
            types == null || types.contains(item['Type']);
        final List<Map<String, dynamic>> page;
        final int total;
        if (membership && legacy) {
          total = items.length;
          page = items.skip(start).take(limit).where(matches).toList();
        } else {
          items = items.where(matches);
          total = items.length;
          page = items.skip(start).take(limit).toList();
        }
        if (discovering) collectionItems += page.length;
        if (membership) {
          childPages.add((parent: parent!, start: start, items: page.length));
          nonBookChildren += page
              .where(
                (item) => !const [
                  'AudioBook',
                  'Book',
                  'Audio',
                ].contains(item['Type']),
              )
              .length;
        }
        final payload = [
          for (final item in page)
            {
              ...item,
              if (discovering || membership) ...{
                if (query['enableImages'] != 'false')
                  'ImageTags': {'Primary': 'cover-tag'},
                if (query['enableUserData'] != 'false')
                  'UserData': {'PlaybackPositionTicks': 123456789},
              },
            },
        ];
        response = {
          'Items': payload,
          'TotalRecordCount': total,
          'StartIndex': start,
        };
        if (discovering || membership) {
          optionalFields += payload.fold(
            0,
            (count, item) =>
                count +
                (item.containsKey('ImageTags') ? 1 : 0) +
                (item.containsKey('UserData') ? 1 : 0),
          );
        }
        if (membership) {
          membershipBytes += utf8.encode(jsonEncode(response)).length;
          untrimmedMembershipBytes += utf8
              .encode(
                jsonEncode({
                  ...response,
                  'Items': [
                    for (final item in page)
                      {
                        ...item,
                        'ImageTags': {'Primary': 'cover-tag'},
                        'UserData': {'PlaybackPositionTicks': 123456789},
                      },
                  ],
                }),
              )
              .length;
        }
        changePage?.call(query, response);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
  }

  JellyfinSession account(String user) => JellyfinSession(
    scope: AccountScope(
      server: Uri.parse('http://127.0.0.1:${server.port}'),
      serverId: 'fixture',
      userId: user,
    ),
    token: '$user-token',
    username: user,
    canDownload: false,
  );

  Future<List<Book>> books(Set<String> shown) async =>
      buildBooks(catalogEntries(await client.catalog(session, shown)));

  Future<void> close() async {
    client.close();
    await server.close(force: true);
  }
}

void main() {
  late _Server fixture;
  setUp(() async {
    fixture = _Server();
    fixture.libraries['audio'] = [entry('audio', title: 'Audio').json];
    fixture.collections.add((
      id: 'shared',
      name: 'Shared series',
      libraries: {'audio'},
      children: [
        {'Id': 'audio', 'Type': 'AudioBook'},
      ],
    ));
    await fixture.start();
  });
  tearDown(() => fixture.close());

  test('shown libraries keep mixed-series books without movie payloads or unrelated collections', () async {
    fixture.libraries['ebooks'] = [
      entry('ebook', title: 'Ebook', type: 'Book', container: 'epub').json,
      entry('track', title: 'Track', type: 'Audio').json,
      entry('nested', title: 'Nested').json,
    ];
    fixture.nestedChildren['shared'] = [
      {'Id': 'nested', 'Type': 'AudioBook'},
    ];
    fixture.libraries['hidden'] = [entry('hidden').json];
    fixture.collections[0] = (
      id: 'shared',
      name: 'Shared series',
      libraries: {'audio', 'ebooks'},
      children: [
        {'Id': 'audio', 'Type': 'AudioBook'},
        {'Id': 'ebook', 'Type': 'Book'},
        {'Id': 'track', 'Type': 'Audio'},
        {'Id': 'film', 'Type': 'Movie'},
        {'Id': 'folder', 'Type': 'Folder'},
      ],
    );
    fixture.collections.addAll([
      (
        id: 'films',
        name: 'Films',
        libraries: {'movies'},
        children: [
          {'Id': 'film', 'Type': 'Movie'},
        ],
      ),
      (
        id: 'hidden-series',
        name: 'Hidden',
        libraries: {'hidden'},
        children: [
          {'Id': 'hidden', 'Type': 'Book'},
        ],
      ),
    ]);
    final catalog = await fixture.client.catalog(fixture.session, {
      'audio',
      'ebooks',
    });
    final books = buildBooks(catalogEntries(catalog));
    expect(books, hasLength(4));
    expect(catalog.collections['track'], ['Shared series']);
    expect(books.singleWhere((book) => book.title == 'Track').series, isNull);
    expect(books.singleWhere((book) => book.title == 'Nested').series, isNull);
    expect(
      books
          .where((book) => book.title == 'Audio' || book.title == 'Ebook')
          .map((book) => book.series),
      everyElement('Shared series'),
    );
    expect(fixture.nonBookChildren, 0);
    expect(fixture.childPages.map((page) => page.parent), ['shared']);
    expect(fixture.collectionItems, 2); // One discovery in each shown library.
    expect(fixture.optionalFields, 0);
    expect(fixture.membershipBytes, lessThan(fixture.untrimmedMembershipBytes));
    // Measured bytes from this fixture only, not server latency or memory.
    // ignore: avoid_print
    print(
      'membership fixture: ${fixture.membershipBytes} response bytes; '
      '${fixture.untrimmedMembershipBytes} bytes with optional fields; '
      '${fixture.nonBookChildren} non-book child records; '
      '${fixture.childPages.length} child requests',
    );
    expect(
      fixture.requests.every(
        (request) =>
            !(request.query['fields']?.split(',').contains('Id') ?? false),
      ),
      isTrue,
    );
  });

  test('older global discovery reads a shared collection only once across libraries', () async {
    fixture.legacy = true;
    fixture.libraries['ebooks'] = [];
    final books = await fixture.books({'audio', 'ebooks'});
    expect(books.single.series, 'Shared series');
    expect(fixture.childPages.map((page) => page.parent), ['shared']);
  });

  test('an empty shown-library set performs no collection work', () async {
    expect(await fixture.books({}), isEmpty);
    expect(fixture.collectionItems, 0);
    expect(fixture.childPages, isEmpty);
    expect(
      fixture.requests.where(
        (request) => request.query['includeItemTypes'] == 'BoxSet',
      ),
      isEmpty,
    );
  });

  test(
    'collections beyond the old thousand-collection limit still name a series',
    () async {
      fixture.collections.clear();
      fixture.collections.addAll([
        for (var index = 0; index < 1001; index++)
          (
            id: 'set$index',
            name: 'Series $index',
            libraries: {'audio'},
            children: index == 1000
                ? [
                    {'Id': 'audio', 'Type': 'AudioBook'},
                  ]
                : <Map<String, dynamic>>[],
          ),
      ]);
      expect((await fixture.books({'audio'})).single.series, 'Series 1000');
      expect(fixture.collectionItems, 1001);
      expect(fixture.childPages, hasLength(1001));
    },
  );

  for (final legacy in [false, true]) {
    test(
      '${legacy ? 'older' : 'current'} child paging preserves membership beyond two thousand children',
      () async {
        fixture.legacy = legacy;
        fixture.collections[0] = (
          id: 'shared',
          name: 'Late series',
          libraries: {'audio'},
          children: [
            if (legacy) {'Id': 'early', 'Type': 'AudioBook'},
            for (var index = 0; index < 4000; index++)
              {'Id': 'other$index', 'Type': legacy ? 'Movie' : 'Book'},
            {'Id': 'audio', 'Type': 'AudioBook'},
          ],
        );
        expect((await fixture.books({'audio'})).single.series, 'Late series');
        expect(fixture.childPages.last.start, greaterThanOrEqualTo(4000));
        if (legacy) {
          expect(fixture.childPages.first.items, 1);
          expect(
            fixture.childPages
                .skip(1)
                .take(fixture.childPages.length - 2)
                .map((page) => page.items),
            everyElement(0),
          );
        }
        expect(fixture.nonBookChildren, 0);
      },
    );
  }

  test(
    'every catalog refresh observes changed collection membership',
    () async {
      expect((await fixture.books({'audio'})).single.series, 'Shared series');
      fixture.collections[0] = (
        id: 'shared',
        name: 'Renamed series',
        libraries: {'audio'},
        children: [
          {'Id': 'audio', 'Type': 'AudioBook'},
        ],
      );
      expect((await fixture.books({'audio'})).single.series, 'Renamed series');
      fixture.collections.clear();
      expect((await fixture.books({'audio'})).single.series, isNull);
    },
  );

  test(
    'unavailable collection metadata keeps the valid book catalog usable',
    () async {
      fixture.beforeReply = (request) async {
        if (request.uri.queryParameters['parentId'] == 'shared') {
          request.response.statusCode = 500;
        }
      };
      final books = await fixture.books({'audio'});
      expect(books.single.title, 'Audio');
      expect(books.single.series, isNull);
    },
  );

  test('closing the old account cancels collection work before a new account reads', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    fixture.beforeReply = (request) async {
      if (request.uri.queryParameters['parentId'] == 'shared' &&
          request.uri.queryParameters['userId'] == 'alice') {
        arrived.complete();
        await release.future;
      }
    };
    final pending = fixture.books({'audio'});
    final assertion = expectLater(
      pending,
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.cancelled,
        ),
      ),
    );
    await arrived.future;
    fixture.client.close();
    await assertion;
    fixture.client = JellyfinClient(
      fixture.session.scope.server,
      deviceId: 'new-account',
    );
    fixture.session = fixture.account('bob');
    fixture.collections[0] = (
      id: 'shared',
      name: 'Bob series',
      libraries: {'audio'},
      children: [
        {'Id': 'audio', 'Type': 'AudioBook'},
      ],
    );
    release.complete();
    expect((await fixture.books({'audio'})).single.series, 'Bob series');
    expect(
      fixture.requests
          .where((request) => request.query['userId'] == 'bob')
          .map((request) => request.token),
      everyElement('bob-token'),
    );
  });

  test(
    'a collection response after credential rejection cannot attach series',
    () async {
      fixture.beforeReply = (request) async {
        if (request.uri.queryParameters['parentId'] == 'shared') {
          fixture.session.rejectCredential();
        }
      };
      try {
        final books = await fixture.books({'audio'});
        expect(books.single.series, isNull);
      } on CatalogFailure catch (failure) {
        expect(failure.kind, CatalogFailureKind.unauthorized);
      }
      expect(fixture.session.needsSignIn, isTrue);
    },
  );

  final malformed = <String, void Function(Map<String, dynamic>)>{
    'missing count': (page) => page.remove('TotalRecordCount'),
    'noninteger count': (page) => page['TotalRecordCount'] = 1.5,
    'negative count': (page) => page['TotalRecordCount'] = -1,
    'excessive count': (page) => page['TotalRecordCount'] = 1000001,
    'wrong start': (page) => page['StartIndex'] = 1,
    'missing items': (page) => page.remove('Items'),
    'empty id': (page) => (page['Items'] as List).first['Id'] = '',
    'duplicate item': (page) =>
        (page['Items'] as List).add((page['Items'] as List).first),
  };
  for (final problem in malformed.entries) {
    test(
      '${problem.key} discards optional membership instead of publishing a partial series',
      () async {
        fixture.changePage = (query, page) {
          if (query['parentId'] == 'shared') problem.value(page);
        };
        final books = await fixture.books({'audio'});
        expect(books.single.title, 'Audio');
        expect(books.single.series, isNull);
      },
    );
  }

  for (final discovery in [false, true]) {
    for (final problem in ['changing count', 'repeated page']) {
      test(
        '$problem in ${discovery ? 'collection discovery' : 'children'} discards all optional series',
        () async {
          fixture.collections[0] = (
            id: 'shared',
            name: 'Shared series',
            libraries: {'audio'},
            children: [
              {'Id': 'audio', 'Type': 'AudioBook'},
              for (var index = 0; index < 200; index++)
                {'Id': 'other$index', 'Type': 'Book'},
            ],
          );
          if (discovery) {
            fixture.collections.addAll([
              for (var index = 0; index < 200; index++)
                (
                  id: 'set$index',
                  name: 'Other $index',
                  libraries: {'audio'},
                  children: <Map<String, dynamic>>[],
                ),
            ]);
          }
          fixture.changePage = (query, page) {
            final selected = discovery
                ? query['includeItemTypes'] == 'BoxSet'
                : query['parentId'] == 'shared';
            if (selected && int.parse(query['startIndex'] ?? '0') > 0) {
              if (problem == 'changing count') {
                page['TotalRecordCount'] =
                    (page['TotalRecordCount'] as int) + 1;
              } else {
                (page['Items'] as List).first['Id'] = discovery
                    ? 'shared'
                    : 'audio';
              }
            }
          };
          expect((await fixture.books({'audio'})).single.series, isNull);
        },
      );
    }
  }

  test(
    'a short collection-discovery page never publishes a partial series map',
    () async {
      fixture.changePage = (query, page) {
        if (query['includeItemTypes'] == 'BoxSet') page['TotalRecordCount'] = 2;
      };
      expect((await fixture.books({'audio'})).single.series, isNull);
      expect(fixture.childPages, isEmpty);
    },
  );
}
