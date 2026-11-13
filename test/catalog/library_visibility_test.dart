import 'dart:convert';
import 'dart:typed_data';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials, account;
import 'model_test.dart' show entry;

const _audiobooks = BookLibrary('audio', 'Audiobooks');
const _ebooks = BookLibrary('ebooks', 'Ebooks');

/// An item of the Ebooks library: a PDF book that no audiobook matches.
CatalogEntry _ebook(String id, {String title = 'The Atlas'}) =>
    CatalogEntry.fromJson(
      entry(id, title: title, type: 'Book', container: 'pdf', source: id).json,
      libraryId: _ebooks.id,
    );

/// An item of the Audiobooks library.
CatalogEntry _audiobook(String id, {String title = 'The Orchard'}) =>
    CatalogEntry.fromJson(
      entry(id, title: title, source: id).json,
      libraryId: _audiobooks.id,
    );

/// A Jellyfin server with one user view of each kind: two book libraries,
/// a movie library and a music library, each holding one item. A request
/// for the items of a library answers with that library's items.
class _ServerTransport implements JsonTransport {
  final views = [
    {'Id': 'audio', 'Name': 'Audiobooks', 'CollectionType': 'books'},
    {'Id': 'ebooks', 'Name': 'Ebooks', 'CollectionType': 'books'},
    {'Id': 'movies', 'Name': 'Movies', 'CollectionType': 'movies'},
    {'Id': 'music', 'Name': 'Music', 'CollectionType': 'music'},
  ];
  final items = {
    'audio': [_audiobook('heard', title: 'Heard').json],
    'ebooks': [_ebook('read', title: 'Read').json],
    'movies': [_ebook('watched', title: 'Watched').json],
    'music': [_audiobook('played', title: 'Played').json],
  };

  /// The library ids whose items a request asked for.
  final asked = <String>{};

  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    if (uri.pathSegments.last == 'UserViews') return {'Items': views};
    if (uri.queryParameters['includeItemTypes'] == 'BoxSet') {
      return {'Items': <Object>[], 'TotalRecordCount': 0};
    }
    final parent = uri.queryParameters['parentId'];
    if (parent == null) return {'Items': <Object>[]};
    asked.add(parent);
    final all = items[parent]!;
    final start = int.parse(uri.queryParameters['startIndex']!);
    return {
      'Items': all
          .skip(start)
          .take(int.parse(uri.queryParameters['limit']!))
          .toList(),
      'TotalRecordCount': all.length,
      'StartIndex': start,
    };
  }

  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async => utf8.encode(
    jsonEncode(await send(uri, method: method, headers: headers, body: body)),
  );

  @override
  void close() {}
}

/// A client whose libraries and catalog come from [transport] through the
/// real Jellyfin client, so the client's own reading of the user views
/// decides which libraries are book libraries.
class _ServerClient extends FixtureClient {
  _ServerClient(super.server, this.transport)
    : _real = JellyfinClient(server, deviceId: 'test', transport: transport);
  final _ServerTransport transport;
  final JellyfinClient _real;
  @override
  Future<List<BookLibrary>> libraries(JellyfinSession session) =>
      _real.libraries(session);
  @override
  Future<CatalogPages> catalog(JellyfinSession session, Set<String> shown) =>
      _real.catalog(session, shown);
}

void main() {
  late MemoryCredentials credentials;
  late MemoryCatalogStore store;
  late FixtureClient client;
  late CatalogController controller;

  CatalogController newController() => CatalogController(
    credentials: credentials,
    store: store,
    clientFactory: (server, device) => client,
  );

  setUp(() {
    credentials = MemoryCredentials();
    store = MemoryCatalogStore();
    client = FixtureClient(Uri.parse('https://books.example'))
      ..views = [_audiobooks, _ebooks]
      ..entries = [_audiobook('heard'), _ebook('read')];
    controller = newController();
  });
  tearDown(() {
    controller.dispose();
    client.close();
  });

  Set<String> titles(CatalogController catalog) => {
    for (final book in catalog.libraryNotifier.value.books) book.title,
  };

  Future<void> signIn() =>
      controller.connect('https://books.example', 'alice', 'password');

  test('a new account shows every book library after sign-in', () async {
    await signIn();
    expect(titles(controller), {'The Orchard', 'The Atlas'});
    expect(controller.accountNotifier.value.hidden, isEmpty);
    expect(controller.statusNotifier.value.verified, isTrue);
    controller.checkInvariants();
  });

  test('a book library added on the server later appears after a refresh, '
      'with no action from the user', () async {
    client.views = [_audiobooks];
    await signIn();
    expect(titles(controller), {'The Orchard'});
    client.views = [_audiobooks, _ebooks];
    await controller.refresh();
    expect(titles(controller), {'The Orchard', 'The Atlas'});
    controller.checkInvariants();
  });

  test('a hidden library stays hidden across refreshes and restarts', () async {
    await signIn();
    await controller.refresh(hidden: {_ebooks.id}, byUser: true);
    expect(titles(controller), {'The Orchard'});
    await controller.refresh();
    expect(titles(controller), {'The Orchard'});
    expect(controller.accountNotifier.value.hidden, {_ebooks.id});

    final restarted = newController();
    addTearDown(restarted.dispose);
    await restarted.restore();
    expect(restarted.accountNotifier.value.hidden, {_ebooks.id});
    expect(titles(restarted), {'The Orchard'});
    await restarted.refresh();
    expect(titles(restarted), {'The Orchard'});
    restarted.checkInvariants();
  });

  test('showing a hidden library again brings its books back', () async {
    await signIn();
    await controller.refresh(hidden: {_ebooks.id}, byUser: true);
    await controller.refresh(hidden: {}, byUser: true);
    expect(titles(controller), {'The Orchard', 'The Atlas'});
    expect(controller.accountNotifier.value.hidden, isEmpty);
  });

  test('a saved catalog from before hidden libraries, with only Audiobooks '
      'selected, shows Ebooks after the next refresh and keeps its '
      'corrections', () async {
    final alice = account('alice');
    credentials.value = alice;
    store.values[alice.scope.key] = jsonEncode({
      'version': 1,
      'accessBlocked': false,
      'scope': alice.scope.toJson(),
      'libraries': [_audiobooks.toJson(), _ebooks.toJson()],
      'selected': [_audiobooks.id],
      'entries': [_audiobook('heard').toJson()],
      'edits': CatalogEdits(
        details: {
          'book:heard': const BookDetails(
            title: 'The Corrected Orchard',
            author: 'A. Writer',
          ),
        },
      ).toJson(),
      'completedAt': '2026-11-01T00:00:00.000Z',
      'content': null,
    });

    await controller.restore();
    expect(titles(controller), {'The Corrected Orchard'});
    expect(controller.accountNotifier.value.hidden, isEmpty);

    await controller.refresh();
    expect(titles(controller), {'The Corrected Orchard', 'The Atlas'});
    final saved = await store.readChoices(alice.scope);
    expect(saved.hidden, isEmpty);
    expect(saved.edits.details['book:heard']?.title, 'The Corrected Orchard');
    controller.checkInvariants();
  });

  test('a library removed from the server leaves the hidden set', () async {
    await signIn();
    await controller.refresh(hidden: {_ebooks.id}, byUser: true);
    client.views = [_audiobooks];
    await controller.refresh();
    expect(controller.accountNotifier.value.hidden, isEmpty);
    expect(controller.statusNotifier.value.verified, isTrue);
    expect(controller.accountNotifier.value.accessBlocked, isFalse);

    // The same library on the server again is a new library, so it shows.
    client.views = [_audiobooks, _ebooks];
    await controller.refresh();
    expect(titles(controller), {'The Orchard', 'The Atlas'});
  });

  test('libraries that are not book libraries never show', () async {
    final server = _ServerTransport();
    client = _ServerClient(Uri.parse('https://books.example'), server);
    await signIn();
    expect(controller.accountNotifier.value.libraries.map((l) => l.name), [
      'Audiobooks',
      'Ebooks',
    ]);
    expect(titles(controller), {'Heard', 'Read'});
    expect(server.asked, {'audio', 'ebooks'});
  });
}
