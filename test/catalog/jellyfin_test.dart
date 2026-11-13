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

  /// Most tests are about one catalog request. They see no collections, and
  /// collection requests are not recorded, unless a test answers them itself.
  late bool answerCollections;
  setUp(() async {
    requests = [];
    answerCollections = true;
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
      if (answerCollections &&
          request.uri.queryParameters['includeItemTypes'] == 'BoxSet') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'Items': [], 'TotalRecordCount': 0}),
        );
        await request.response.close();
        return;
      }
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

  /// The entries of the catalog of [selected], built from its pages as the
  /// catalog worker builds them.
  Future<List<CatalogEntry>> entries(Set<String> selected) async =>
      catalogEntries(await client.catalog(session, selected));

  /// The body of each catalog page that [serveCatalog] sent, in order.
  late List<String> servedPages;

  /// Answers the book library list, and answers each catalog request with
  /// [page] for its start index. A page request asks for a full page.
  void serveCatalog(Map<String, dynamic> Function(int start) page) {
    servedPages = [];
    respond = (request) {
      final start =
          int.tryParse(request.uri.queryParameters['startIndex'] ?? '') ?? 0;
      final text = jsonEncode(
        request.uri.path.endsWith('UserViews')
            ? {
                'Items': [
                  {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
                ],
              }
            : page(start),
      );
      if (request.uri.queryParameters['limit'] == '$catalogPageSize') {
        servedPages.add(text);
      }
      request.response.write(text);
      return request.response.close();
    };
  }

  bool isPage(
    ({String method, Uri uri, String? token, Map<String, dynamic>? body})
    request,
  ) =>
      request.uri.path.endsWith('/Items') &&
      request.uri.queryParameters['limit'] == '$catalogPageSize';

  Matcher failsWith(CatalogFailureKind kind) => throwsA(
    isA<CatalogFailure>().having((failure) => failure.kind, 'kind', kind),
  );

  test(
    'a response received after credential rejection is not accepted',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      respond = (request) async {
        started.complete();
        await release.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'Items': []}));
        await request.response.close();
      };
      final pending = client.libraries(session);
      await started.future;
      session.rejectCredential();
      release.complete();
      await expectLater(pending, throwsA(isA<CatalogFailure>()));
    },
  );

  test(
    'a 401 retires the shared credential before another request can start',
    () async {
      respond = (request) async {
        request.response.statusCode = 401;
        await request.response.close();
      };
      await expectLater(
        client.libraries(session),
        throwsA(isA<CatalogFailure>()),
      );
      final anotherClient = JellyfinClient(
        session.scope.server,
        deviceId: 'other',
      );
      addTearDown(anotherClient.close);
      await expectLater(
        anotherClient.libraries(session),
        throwsA(isA<CatalogFailure>()),
      );
      expect(requests, hasLength(1));
      expect(session.token, 'test-token');
      expect(JellyfinSession.fromJson(session.toJson()).needsSignIn, isTrue);
    },
  );

  test('a 403 does not reject the server credential', () async {
    respond = (request) async {
      request.response.statusCode = 403;
      await request.response.close();
    };
    await expectLater(
      client.libraries(session),
      throwsA(isA<CatalogFailure>()),
    );
    expect(session.needsSignIn, isFalse);
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
    final items = await entries({'books'});
    expect(items, hasLength(205));
    final pages = requests.where(isPage).toList();
    expect(
      pages.map((request) => request.uri.queryParameters['startIndex']),
      unorderedEquals(['0', '200']),
    );
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

  test('a parent that is not a book library of the account is rejected before item fetching', () async {
    await expectLater(
      client.catalog(session, {'movies'}),
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.incomplete,
        ),
      ),
    );
    expect(
      requests.any((request) => request.uri.path.endsWith('/Items')),
      isFalse,
    );
  });

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
      entries({'books'}),
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
          entries({'books'}),
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
    final items = await entries({'books'});
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
      final items = await entries({'books'});
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

  test('a catalog read hands back each page as Jellyfin sent it', () async {
    serveCatalog(
      (start) => {
        'Items': [
          for (var index = start; index < start + 3; index++)
            entry('item$index').json,
        ],
        'TotalRecordCount': 3,
        'StartIndex': start,
      },
    );
    final catalog = await client.catalog(session, {'books'});
    final library = catalog.libraries.single;
    expect(library.libraryId, 'books');
    expect(library.total, 3);
    expect(library.pages.single, utf8.encode(servedPages.single));
    expect(catalog.items, 3);
  });

  test(
    'the pages of a library are requested together, not one after another',
    () async {
      serveCatalog(
        (start) => {
          'Items': [
            for (var index = start; index < start + 200; index++)
              entry('item$index').json,
          ],
          'TotalRecordCount': 600,
          'StartIndex': start,
        },
      );
      final answer = respond;
      final waiting = <Completer<void>>[];
      respond = (request) async {
        if (request.uri.queryParameters['limit'] == '$catalogPageSize') {
          // Each page waits until the server holds all three page requests.
          final arrived = Completer<void>();
          waiting.add(arrived);
          if (waiting.length == 3) {
            for (final each in waiting) {
              each.complete();
            }
          }
          await arrived.future;
        }
        await answer(request);
      };
      expect(await entries({'books'}), hasLength(600));
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test('a page shorter than its place in the count is incomplete', () async {
    serveCatalog(
      (start) => {
        'Items': [
          for (var index = start; index < (start == 0 ? 199 : 205); index++)
            entry('item$index').json,
        ],
        'TotalRecordCount': 205,
        'StartIndex': start,
      },
    );
    await expectLater(
      entries({'books'}),
      failsWith(CatalogFailureKind.incomplete),
    );
  });

  test('an item that is not a book is an unreadable catalog', () async {
    serveCatalog(
      (start) => {
        'Items': [entry('film', type: 'Movie').json],
        'TotalRecordCount': 1,
        'StartIndex': start,
      },
    );
    await expectLater(
      entries({'books'}),
      failsWith(CatalogFailureKind.invalidResponse),
    );
  });

  test('closing the client cancels a page request in flight', () async {
    final received = Completer<void>();
    final finish = Completer<void>();
    serveCatalog(
      (start) => {
        'Items': [entry('item0').json],
        'TotalRecordCount': 1,
        'StartIndex': start,
      },
    );
    final answer = respond;
    respond = (request) async {
      if (request.uri.queryParameters['limit'] == '$catalogPageSize') {
        received.complete();
        await finish.future;
      }
      await answer(request);
    };
    final reading = client.catalog(session, {'books'});
    await received.future;
    client.close();
    await expectLater(reading, failsWith(CatalogFailureKind.cancelled));
    finish.complete();
  });

  Future<void> Function(HttpRequest) collectionServer({
    bool failCollections = false,
  }) => (request) {
    final query = request.uri.queryParameters;
    if (request.uri.path.endsWith('UserViews')) {
      request.response.write(
        jsonEncode({
          'Items': [
            {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
          ],
        }),
      );
    } else if (query['includeItemTypes'] == 'BoxSet') {
      if (failCollections) {
        request.response.statusCode = 500;
      } else {
        request.response.write(
          jsonEncode({
            'Items': [
              {'Id': 'wot', 'Name': 'The Wheel of Time', 'Type': 'BoxSet'},
              {'Id': 'films', 'Name': 'Alien Collection', 'Type': 'BoxSet'},
            ],
            'TotalRecordCount': 2,
          }),
        );
      }
    } else if (query['parentId'] == 'wot' || query['parentId'] == 'films') {
      request.response.write(
        jsonEncode({
          'Items': [
            {'Id': query['parentId'] == 'wot' ? 'crown' : 'alien'},
          ],
          'TotalRecordCount': 1,
        }),
      );
    } else {
      request.response.write(
        jsonEncode({
          'Items': [
            entry('crown', title: 'A Crown of Swords').json,
            entry('salem', title: "'Salem's Lot").json,
          ],
          'TotalRecordCount': 2,
        }),
      );
    }
    return request.response.close();
  };

  test('books in a Jellyfin collection belong to its series', () async {
    answerCollections = false;
    respond = collectionServer();
    final books = buildBooks(await entries({'books'}));
    expect(
      books.singleWhere((book) => book.title == 'A Crown of Swords').series,
      'The Wheel of Time',
    );
    expect(
      books.singleWhere((book) => book.title == "'Salem's Lot").series,
      isNull,
    );
  });

  test(
    'unreadable collections leave books without a series but still load',
    () async {
      answerCollections = false;
      respond = collectionServer(failCollections: true);
      final books = buildBooks(await entries({'books'}));
      expect(books, hasLength(2));
      expect(books.every((book) => book.series == null), isTrue);
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
