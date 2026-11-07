import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_test.dart' show entry;

void main() {
  late HttpServer server;
  late JellyfinClient client;
  late JellyfinSession session;
  late List<
    ({String method, Uri uri, String? token, Map<String, dynamic>? body})
  >
  requests;
  late FutureOr<void> Function(HttpRequest request) respond;
  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}/jellyfin');
    session = JellyfinSession(
      scope: AccountScope(server: base, serverId: 'server', userId: 'alice'),
      token: 'test-token',
      username: 'Alice',
      canDownload: false,
    );
    client = JellyfinClient(base, deviceId: 'test-device');
    respond = (request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'Items': [], 'TotalRecordCount': 0}));
      return request.response.close();
    };
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        token: request.headers.value('X-Emby-Token'),
        body: text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>,
      ));
      await respond(request);
    });
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('sign-in sends password only in the JSON body and preserves a server subpath', () async {
    respond = (request) {
      request.response.write(
        jsonEncode({
          'ServerId': 'server',
          'AccessToken': 'secret-token',
          'User': {
            'Id': 'alice',
            'Name': 'Alice',
            'Policy': {'EnableContentDownloading': false},
          },
        }),
      );
      return request.response.close();
    };
    final signedIn = await client.signIn('Alice', 'private-password');
    expect(signedIn.scope.userId, 'alice');
    expect(signedIn.canDownload, isFalse);
    expect(requests.single.uri.path, '/jellyfin/Users/AuthenticateByName');
    expect(requests.single.uri.query, isEmpty);
    expect(requests.single.body, {
      'Username': 'Alice',
      'Pw': 'private-password',
    });
    expect(signedIn.toString(), isNot(contains('secret-token')));
  });

  test('only book libraries are offered', () async {
    respond = (request) {
      request.response.write(
        jsonEncode({
          'Items': [
            {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
            {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies'},
            {'Id': 'mixed', 'Name': 'Other', 'CollectionType': null},
          ],
        }),
      );
      return request.response.close();
    };
    expect((await client.libraries(session)).map((library) => library.id), [
      'books',
    ]);
    expect(requests.single.token, 'test-token');
    expect(requests.single.uri.path, '/jellyfin/UserViews');
  });

  test(
    'authenticated catalog works when legacy token headers are rejected',
    () async {
      respond = (request) {
        if (request.headers
                .value('Authorization')
                ?.contains('Token="test-token"') !=
            true) {
          request.response.statusCode = 401;
        } else {
          request.response.write(
            jsonEncode({
              'Items': [
                {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
              ],
            }),
          );
        }
        return request.response.close();
      };
      expect((await client.libraries(session)).map((library) => library.id), [
        'books',
      ]);
    },
  );

  test('catalog pagination fetches only selected book parents', () async {
    respond = (request) {
      final isViews = request.uri.path.endsWith('UserViews');
      final start =
          int.tryParse(request.uri.queryParameters['startIndex'] ?? '') ?? 0;
      request.response.write(
        jsonEncode(
          isViews
              ? {
                  'Items': [
                    {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
                  ],
                }
              : {
                  'Items': [
                    for (
                      var index = start;
                      index < (start == 0 ? 200 : 205);
                      index++
                    )
                      entry('item$index').json,
                  ],
                  'TotalRecordCount': 205,
                  'StartIndex': start,
                },
        ),
      );
      return request.response.close();
    };
    final items = await client.catalog(session, {'books'});
    expect(items, hasLength(205));
    final pages = requests
        .where((request) => request.uri.path.endsWith('/Items'))
        .toList();
    expect(pages.map((request) => request.uri.queryParameters['startIndex']), [
      '0',
      '200',
    ]);
    expect(
      pages.every(
        (request) => request.uri.queryParameters['parentId'] == 'books',
      ),
      isTrue,
    );
    expect(
      pages.every(
        (request) =>
            request.uri.queryParameters['includeItemTypes'] ==
            'AudioBook,Book,Audio',
      ),
      isTrue,
    );
  });

  test(
    'an unselected or non-book parent is rejected before item fetching',
    () async {
      await expectLater(
        client.catalog(session, {'movies'}),
        throwsA(
          isA<CatalogFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogFailureKind.invalidSelection,
          ),
        ),
      );
      expect(
        requests.any((request) => request.uri.path.endsWith('/Items')),
        isFalse,
      );
    },
  );

  test('a truncated page sequence never becomes a complete catalog', () async {
    respond = (request) {
      request.response.write(
        jsonEncode(
          request.uri.path.endsWith('UserViews')
              ? {
                  'Items': [
                    {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
                  ],
                }
              : {'Items': [], 'TotalRecordCount': 500},
        ),
      );
      return request.response.close();
    };
    await expectLater(
      client.catalog(session, {'books'}),
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.incomplete,
        ),
      ),
    );
  });

  test(
    'denied access is not retried through a different media or file route',
    () async {
      respond = (request) {
        request.response.statusCode = 403;
        request.response.write('password=never-display');
        return request.response.close();
      };
      await expectLater(
        client.libraries(session),
        throwsA(
          isA<CatalogFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                CatalogFailureKind.forbidden,
              )
              .having(
                (failure) => failure.toString(),
                'safe message',
                isNot(contains('never-display')),
              ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );

  test(
    'a revoked token requires sign-in without leaking server error text',
    () async {
      respond = (request) {
        request.response.statusCode = 401;
        return request.response.close();
      };
      await expectLater(
        client.libraries(session),
        throwsA(
          isA<CatalogFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogFailureKind.unauthorized,
          ),
        ),
      );
    },
  );

  test(
    'credentials never follow a redirect, including same-origin redirects',
    () async {
      respond = (request) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/another-server');
        return request.response.close();
      };
      await expectLater(
        client.signIn('Alice', 'password'),
        throwsA(isA<CatalogFailure>()),
      );
      expect(requests, hasLength(1));
    },
  );

  test('a client cannot use another server session', () async {
    final other = JellyfinSession(
      scope: AccountScope(
        server: Uri.parse('https://elsewhere.example'),
        serverId: 'other',
        userId: 'alice',
      ),
      token: 'other-token',
      username: 'Alice',
      canDownload: true,
    );
    await expectLater(client.libraries(other), throwsA(isA<CatalogFailure>()));
    expect(requests, isEmpty);
  });

  test('only HTTPS and local HTTP fixture addresses accept sign-in', () {
    expect(
      parseServer('HTTPS://Example.COM/jellyfin/').toString(),
      'https://example.com/jellyfin',
    );
    for (final value in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com?api_key=secret',
      'https://example.com/#token',
      'https://example.com/a/../b',
      'file:///tmp/catalog',
    ]) {
      expect(
        () => parseServer(value),
        throwsA(isA<CatalogFailure>()),
        reason: value,
      );
    }
  });

  test(
    'changing totals and duplicate pages are not published as complete',
    () async {
      for (final duplicate in [false, true]) {
        requests.clear();
        respond = (request) {
          final start =
              int.tryParse(request.uri.queryParameters['startIndex'] ?? '') ??
              0;
          request.response.write(
            jsonEncode(
              request.uri.path.endsWith('UserViews')
                  ? {
                      'Items': [
                        {
                          'Id': 'books',
                          'Name': 'Books',
                          'CollectionType': 'books',
                        },
                      ],
                    }
                  : {
                      'Items': [
                        for (
                          var index = start;
                          index < (start == 0 ? 200 : 201);
                          index++
                        )
                          entry(duplicate && start > 0 ? 'item0' : 'item$index')
                              .json,
                      ],
                      'TotalRecordCount': start == 0 || duplicate ? 201 : 202,
                    },
            ),
          );
          return request.response.close();
        };
        await expectLater(
          client.catalog(session, {'books'}),
          throwsA(
            isA<CatalogFailure>().having(
              (failure) => failure.kind,
              'kind',
              CatalogFailureKind.incomplete,
            ),
          ),
        );
      }
    },
  );

  test(
    'cancelling a request aborts its response without waiting for the server',
    () async {
      final received = Completer<void>();
      final finish = Completer<void>();
      respond = (request) async {
        received.complete();
        await finish.future;
        await request.response.close();
      };
      final fetching = client.libraries(session);
      await received.future;
      client.close();
      await expectLater(
        fetching,
        throwsA(
          isA<CatalogFailure>().having(
            (failure) => failure.kind,
            'kind',
            CatalogFailureKind.cancelled,
          ),
        ),
      );
      finish.complete();
    },
  );

  test('a strict Jellyfin catalog returns general audio only from a selected book library', () async {
    const allowedFields = {
      'MediaSources',
      'Chapters',
      'People',
      'ProviderIds',
      'ParentId',
      'Etag',
      'CanDownload',
      'SortName',
      'Overview',
      'Genres',
      'Studios',
    };
    respond = (request) {
      if (request.uri.path.endsWith('UserViews')) {
        request.response.write(
          jsonEncode({
            'Items': [
              {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
            ],
          }),
        );
      } else {
        final fields = request.uri.queryParameters['fields']!
            .split(',')
            .toSet();
        if (!allowedFields.containsAll(fields)) {
          request.response.statusCode = 400;
        } else {
          request.response.write(
            jsonEncode({
              'Items': [
                entry(
                  'part',
                  type: 'Audio',
                  modified: null,
                  fields: {
                    if (fields.contains('Etag')) 'Etag': 'file-revision',
                  },
                ).json,
              ],
              'TotalRecordCount': 1,
            }),
          );
        }
      }
      return request.response.close();
    };
    final items = await client.catalog(session, {'books'});
    final edition = buildBooks(items).single.editions.single;
    expect(edition.kind, EditionKind.audio);
    expect(edition.files.single.revision, contains('file-revision'));
    expect(
      requests.last.uri.queryParameters['includeItemTypes']!.split(','),
      contains('Audio'),
    );
    expect(requests.last.uri.queryParameters['parentId'], 'books');
  });

  test(
    'the catalog keeps the cover, series, and details of each book',
    () async {
      respond = (request) {
        if (request.uri.path.endsWith('UserViews')) {
          request.response.write(
            jsonEncode({
              'Items': [
                {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
              ],
            }),
          );
        } else {
          final fields = request.uri.queryParameters['fields']!.split(',');
          request.response.write(
            jsonEncode({
              'Items': [
                entry(
                  'graft',
                  title: 'Graft',
                  type: 'Book',
                  container: 'epub',
                  fields: {
                    'SeriesName': 'The Orchard Cycle',
                    'IndexNumber': 2,
                    'ImageTags': {'Primary': 'cover-tag'},
                    'ProductionYear': 2021,
                    if (fields.contains('Overview')) 'Overview': 'A return.',
                    if (fields.contains('Genres')) 'Genres': ['Fantasy'],
                    if (fields.contains('Studios'))
                      'Studios': [
                        {'Name': 'Halyard Press', 'Id': 'studio'},
                      ],
                    'UnrelatedSecret': 'dropped',
                  },
                ).json,
              ],
              'TotalRecordCount': 1,
            }),
          );
        }
        return request.response.close();
      };
      final items = await client.catalog(session, {'books'});
      expect(items.single.json, isNot(contains('UnrelatedSecret')));
      final book = buildBooks(items).single;
      expect(book.series, 'The Orchard Cycle');
      expect(book.seriesOrder, 2);
      expect(book.cover, const CoverRef('graft', 'cover-tag'));
      expect(book.description, 'A return.');
      expect(book.genres, ['Fantasy']);
      expect(book.publisher, 'Halyard Press');
      expect(book.year, 2021);
    },
  );

  test('rejected sign-in explains credentials rather than claiming an expired session', () async {
    respond = (request) {
      request.response.statusCode = 401;
      return request.response.close();
    };
    await expectLater(
      client.signIn('Alice', 'wrong-password'),
      throwsA(
        isA<CatalogFailure>()
            .having(
              (failure) => failure.message,
              'sign-in message',
              contains('username and password'),
            )
            .having(
              (failure) => failure.message,
              'safe message',
              isNot(contains('wrong-password')),
            ),
      ),
    );
  });
}
