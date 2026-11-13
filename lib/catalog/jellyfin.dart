import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, compute;

import '../foundation/hop.dart';
import 'model.dart';
import 'transport.dart';

enum CatalogFailureKind {
  invalidCredentials,
  unauthorized,
  forbidden,
  unavailable,
  invalidResponse,
  incomplete,
  cancelled,
  invalidServer,
}

class CatalogFailure implements Exception {
  const CatalogFailure(this.kind, {this.status});
  final CatalogFailureKind kind;

  /// The HTTP status of an answer that Jellyfin refused, for example 404
  /// when it has no such route, or null when no answer came.
  final int? status;
  String get message => switch (kind) {
    CatalogFailureKind.invalidCredentials =>
      'Sign-in failed. Check your username and password.',
    CatalogFailureKind.unauthorized =>
      'Sign in again. Your Jellyfin session has expired.',
    CatalogFailureKind.forbidden => 'This account does not have access.',
    CatalogFailureKind.unavailable =>
      'Cannot reach Jellyfin. Check the server address and your connection.',
    CatalogFailureKind.invalidResponse =>
      'Jellyfin returned an unreadable catalog.',
    CatalogFailureKind.incomplete =>
      'The catalog changed or the refresh was incomplete. Try again.',
    CatalogFailureKind.cancelled => 'Refresh cancelled.',
    CatalogFailureKind.invalidServer =>
      'Use an HTTPS server address without a password, query, or fragment.',
  };
  @override
  String toString() => message;
}

Uri parseServer(String value) {
  try {
    if (RegExp(
          r'/(?:\.|%2e){1,2}(?:/|[?#]|$)',
          caseSensitive: false,
        ).hasMatch(value) ||
        RegExp(r'[\x00-\x20]').hasMatch(value.trim())) {
      throw const FormatException();
    }
    final uri = Uri.parse(value.trim());
    final local =
        uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1';
    if ((uri.scheme != 'https' && !(uri.scheme == 'http' && local)) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.contains('\\') ||
        uri.pathSegments.any(
          (segment) =>
              segment == '.' ||
              segment == '..' ||
              segment.contains('/') ||
              segment.contains('\\'),
        )) {
      throw const CatalogFailure(CatalogFailureKind.invalidServer);
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: path);
  } catch (_) {
    throw const CatalogFailure(CatalogFailureKind.invalidServer);
  }
}

class AccountScope {
  const AccountScope({
    required this.server,
    required this.serverId,
    required this.userId,
  });
  final Uri server;
  final String serverId;
  final String userId;
  String get key => jsonEncode([server.toString(), serverId, userId]);
  Map<String, dynamic> toJson() => {
    'server': server.toString(),
    'serverId': serverId,
    'userId': userId,
  };
  factory AccountScope.fromJson(Map<String, dynamic> json) => AccountScope(
    server: parseServer(json['server'] as String),
    serverId: json['serverId'] as String,
    userId: json['userId'] as String,
  );
}

/// A local account identity and its retained server credential. Validation
/// updates user policy while sharing the credential's rejection signal.
/// Replacing credentials requires successful authentication; rejecting them
/// never removes identity or changes which account owns local data.
class JellyfinSession {
  JellyfinSession({
    required this.scope,
    required String token,
    required this.username,
    required this.canDownload,
    bool needsSignIn = false,
  }) : _credential = _Credential(token, needsSignIn);

  JellyfinSession._(
    this._credential, {
    required this.scope,
    required this.username,
    required this.canDownload,
  });

  final AccountScope scope;
  final _Credential _credential;
  String get token => _credential.token;

  /// Whether this credential was rejected. Local identity and files remain
  /// valid. Only a successful sign-in supplies a new usable credential.
  bool get needsSignIn => _credential.value;

  /// The lifetime of this credential, independent of its token text.
  /// Policy validation preserves it; successful authentication replaces it.
  /// Consumers use this identity for subscriptions and unfinished requests.
  Object get credentialIdentity => _credential;

  /// True once a request rejects this credential, including after restore.
  ValueListenable<bool> get credentialChanges => _credential;

  /// Retires this credential after a 401. All requests holding it observe
  /// the same state, including requests started before a policy refresh.
  void rejectCredential() => _credential.value = true;
  final String username;
  final bool canDownload;
  Map<String, dynamic> toJson() => {
    'scope': scope.toJson(),
    'token': token,
    'username': username,
    'canDownload': canDownload,
    'needsSignIn': needsSignIn,
  };
  factory JellyfinSession.fromJson(Map<String, dynamic> json) =>
      JellyfinSession(
        scope: AccountScope.fromJson(json['scope'] as Map<String, dynamic>),
        token: json['token'] as String,
        username: json['username'] as String,
        canDownload: json['canDownload'] == true,
        needsSignIn: json['needsSignIn'] == true,
      );
  @override
  String toString() => 'JellyfinSession(<redacted>)';
}

/// One credential's lifetime, shared by the sessions that validate its user
/// policy. Rejection is monotonic; replacement creates another credential.
class _Credential extends ValueNotifier<bool> {
  _Credential(this.token, super.value);
  final String token;
}

class BookLibrary {
  const BookLibrary(this.id, this.name);
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// The number of catalog items in a full page from Jellyfin.
const catalogPageSize = 200;

/// The pages of one shown book library as Jellyfin sent them: the id of
/// the library, how many items Jellyfin counted in it, and the body of each
/// page, in order. Page `n` starts at item `n * catalogPageSize`.
typedef LibraryPages = ({String libraryId, int total, List<Uint8List> pages});

/// Jellyfin's answer to a catalog read, not yet decoded: the pages of each
/// shown book library, in order, and the names of the collections that
/// hold each item. [catalogEntries] decodes and checks it. Page bodies cross
/// to another isolate as block copies, so that isolate can decode them and
/// build the entries, and the UI isolate never holds them as maps.
class CatalogPages {
  const CatalogPages({this.libraries = const [], this.collections = const {}});
  final List<LibraryPages> libraries;

  /// The names of the Jellyfin collections that hold each item, by item id.
  /// It can name items that are not in the catalog.
  final Map<String, List<String>> collections;

  /// How many items the pages hold, when they are complete.
  int get items => libraries.fold(0, (sum, library) => sum + library.total);
}

/// How many catalog pages the client requests at once. Pages are
/// independent once Jellyfin counted the library, and a few at once keep the
/// server busy without flooding it.
const _pageRequests = 4;

/// The fields of a catalog item that the catalog keeps. Jellyfin sends more,
/// and the rest is dropped.
const _itemFields = [
  'Id',
  'Name',
  'Type',
  'ParentId',
  'Album',
  'AlbumArtist',
  'Artists',
  'IndexNumber',
  'ParentIndexNumber',
  'RunTimeTicks',
  'DateModified',
  'Etag',
  'ProviderIds',
  'People',
  'Chapters',
  'Container',
  'SeriesName',
  'Overview',
  'Genres',
  'Studios',
  'ProductionYear',
  'ImageTags',
  'AlbumId',
  'AlbumPrimaryImageTag',
];
const _sourceFields = ['Id', 'Container', 'Size', 'RunTimeTicks', 'ETag'];

/// Decodes the pages of [catalog], checks that they are one complete and
/// consistent catalog, and builds its entries, in page order. It keeps the
/// [_itemFields] of each item and adds its collection names. A top-level
/// function, so the catalog worker can run it.
///
/// Throws [CatalogFailureKind.incomplete] when a page disagrees with the
/// count of its library, misses items or repeats an item, and
/// [CatalogFailureKind.invalidResponse] when a page cannot be read or holds
/// an item that is not a book.
List<CatalogEntry> catalogEntries(CatalogPages catalog) {
  final entries = <CatalogEntry>[];
  final seen = <String>{};
  for (final library in catalog.libraries) {
    final total = library.total;
    if (library.pages.length !=
        (total + catalogPageSize - 1) ~/ catalogPageSize) {
      throw const CatalogFailure(CatalogFailureKind.incomplete);
    }
    for (final (index, body) in library.pages.indexed) {
      final start = index * catalogPageSize;
      try {
        final response = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        final page = response['Items'] as List;
        if (response['TotalRecordCount'] as int != total ||
            (response['StartIndex'] != null &&
                response['StartIndex'] != start) ||
            page.length != min(catalogPageSize, total - start)) {
          throw const CatalogFailure(CatalogFailureKind.incomplete);
        }
        for (final value in page) {
          final item = value as Map<String, dynamic>;
          final id = item['Id'] as String;
          if (id.isEmpty || !seen.add(id)) {
            throw const CatalogFailure(CatalogFailureKind.incomplete);
          }
          if (item['Type'] != 'AudioBook' &&
              item['Type'] != 'Audio' &&
              item['Type'] != 'Book') {
            throw const CatalogFailure(CatalogFailureKind.invalidResponse);
          }
          entries.add(
            CatalogEntry.fromJson({
              for (final field in _itemFields)
                if (item.containsKey(field)) field: item[field],
              'MediaSources': [
                for (final source
                    in (item['MediaSources'] as List? ?? [])
                        .cast<Map<String, dynamic>>())
                  {
                    for (final field in _sourceFields)
                      if (source.containsKey(field)) field: source[field],
                  },
              ],
              'BookfinCollections': ?catalog.collections[id],
            }, libraryId: library.libraryId),
          );
        }
      } on CatalogFailure {
        rethrow;
      } catch (_) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
    }
  }
  return entries;
}

// Collection pages retain only the fields needed for discovery and membership.
// The client owns their request-local lifetime; only workers traverse the items.
typedef _CollectionPage = ({int total, Map<String, String?> items});
typedef _CollectionMembers = ({String name, List<_CollectionPage> pages});

_CollectionPage _parseCollectionPage(
  ({Uint8List bytes, int start, int? total}) input,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(input.bytes));
  } on FormatException {
    throw const CatalogFailure(CatalogFailureKind.invalidResponse);
  }
  if (decoded is! Map<String, dynamic>) {
    throw const CatalogFailure(CatalogFailureKind.invalidResponse);
  }
  final count = decoded['TotalRecordCount'];
  final page = decoded['Items'];
  if (count is! int || page is! List) {
    throw const CatalogFailure(CatalogFailureKind.invalidResponse);
  }
  if (count < 0 ||
      count > 1000000 ||
      (input.total != null && count != input.total) ||
      (decoded['StartIndex'] != null && decoded['StartIndex'] != input.start) ||
      page.length > min(catalogPageSize, count - input.start)) {
    throw const CatalogFailure(CatalogFailureKind.incomplete);
  }
  final items = <String, String?>{};
  for (final value in page) {
    if (value is! Map<String, dynamic>) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    }
    final id = value['Id'];
    if (id is! String || id.isEmpty) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    }
    if (items.containsKey(id)) {
      throw const CatalogFailure(CatalogFailureKind.incomplete);
    }
    final name = value['Name'];
    items[id] = name is String ? name : null;
  }
  return (total: count, items: items);
}

// Both reductions check uniqueness across a complete listing, without making
// another list of its items. A duplicate on a later page invalidates all series.
Iterable<MapEntry<String, String?>> _collectionEntries(
  List<_CollectionPage> pages,
) sync* {
  final seen = <String>{};
  for (final page in pages) {
    for (final item in page.items.entries) {
      if (!seen.add(item.key)) {
        throw const CatalogFailure(CatalogFailureKind.incomplete);
      }
      yield item;
    }
  }
}

List<({String id, String name})> _discoverCollections(
  List<List<_CollectionPage>> listings,
) {
  final byId = <String, String>{};
  for (final pages in listings) {
    var count = 0;
    for (final item in _collectionEntries(pages)) {
      final name = item.value;
      if (name == null || name.isEmpty) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      if (byId.containsKey(item.key) && byId[item.key] != name) {
        throw const CatalogFailure(CatalogFailureKind.incomplete);
      }
      // 12.4 scopes discovery by linked-child ancestors. 10.11 ignores the
      // parent, so either can discover the same set in several libraries.
      byId[item.key] = name;
      count++;
    }
    // Discovery has no post-page filter, unlike 10.11 direct children.
    if (count != pages.first.total) {
      throw const CatalogFailure(CatalogFailureKind.incomplete);
    }
  }
  return [for (final item in byId.entries) (id: item.key, name: item.value)];
}

Map<String, List<String>> _collectionMembership(
  List<_CollectionMembers> listings,
) {
  final result = <String, List<String>>{};
  for (final listing in listings) {
    for (final item in _collectionEntries(listing.pages)) {
      result.putIfAbsent(item.key, () => []).add(listing.name);
    }
  }
  return result;
}

class JellyfinClient {
  /// Uses [transport] for requests and [hop] for collection processing.
  /// By default, collection work runs through Flutter's compute: in a native
  /// isolate on native platforms, or on the browser event loop on the web.
  JellyfinClient(
    Uri server, {
    required this.deviceId,
    JsonTransport? transport,
    IsolateHop? hop,
  }) : server = parseServer(server.toString()),
       _transport = transport ?? createTransport(),
       _hop = hop ?? compute;
  final Uri server;
  final String deviceId;
  final JsonTransport _transport;
  final IsolateHop _hop;
  bool _closed = false;
  Future<void> reportPlayback(
    JellyfinSession session,
    String event,
    Map<String, dynamic> body,
  ) async {
    if (!const {'start', 'progress', 'stop'}.contains(event)) {
      throw ArgumentError('Unknown playback event.');
    }
    await _send(
      [
        'Sessions',
        'Playing',
        if (event == 'progress') 'Progress' else if (event == 'stop') 'Stopped',
      ],
      method: 'POST',
      session: session,
      body: body,
    );
  }

  Future<JellyfinSession> signIn(String username, String password) async {
    final Map<String, dynamic> response;
    try {
      response = await _send(
        ['Users', 'AuthenticateByName'],
        method: 'POST',
        body: {'Username': username, 'Pw': password},
      );
    } on CatalogFailure catch (failure) {
      if (failure.kind == CatalogFailureKind.unauthorized) {
        throw const CatalogFailure(CatalogFailureKind.invalidCredentials);
      }
      rethrow;
    }
    try {
      final user = response['User'] as Map<String, dynamic>;
      final token = response['AccessToken'] as String;
      final serverId = response['ServerId'] as String;
      final userId = user['Id'] as String;
      if (token.isEmpty ||
          serverId.isEmpty ||
          userId.isEmpty ||
          token.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException();
      }
      return JellyfinSession(
        scope: AccountScope(server: server, serverId: serverId, userId: userId),
        token: token,
        username: user['Name'] as String? ?? username,
        canDownload:
            (user['Policy'] as Map?)?['EnableContentDownloading'] == true,
      );
    } catch (_) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    }
  }

  Future<JellyfinSession> validate(JellyfinSession session) async {
    _guard(session);
    final info = await _send(['System', 'Info', 'Public']);
    if (info['Id'] != session.scope.serverId) {
      throw const CatalogFailure(CatalogFailureKind.unauthorized);
    }
    final user = await _send(['Users', 'Me'], session: session);
    if (user['Id'] != session.scope.userId) {
      throw const CatalogFailure(CatalogFailureKind.unauthorized);
    }
    return JellyfinSession._(
      session._credential,
      scope: session.scope,
      username: user['Name'] as String? ?? session.username,
      canDownload:
          (user['Policy'] as Map?)?['EnableContentDownloading'] == true,
    );
  }

  Future<Map<String, dynamic>> personalRecordChanges(
    JellyfinSession session,
    int after,
  ) => _send(
    ['BookfinStorage', 'v1', 'objects'],
    session: session,
    query: {'after': '$after', 'limit': '4'},
  );

  /// Discovery for the authenticated v2 plugin contract. Transport selects
  /// this only after a valid v1 discovery reply advertises a compatible version.
  Future<Map<String, dynamic>> personalRecordBatchChanges(
    JellyfinSession session,
    int after,
  ) => _send(
    ['BookfinStorage', 'v2', 'objects'],
    session: session,
    query: {'after': '$after', 'limit': '256'},
  );

  /// Sends a bounded v2 group of immutable objects. Transport owns grouping
  /// and confirmation checks; the authenticated server validates every item.
  Future<Map<String, dynamic>> uploadPersonalRecords(
    JellyfinSession session,
    List<Map<String, String>> objects,
  ) => _send(
    ['BookfinStorage', 'v2', 'objects'],
    session: session,
    method: 'PUT',
    body: {'Objects': objects},
  );

  /// The server's copy of the personal-record object [identity].
  Future<Map<String, dynamic>> personalRecord(
    JellyfinSession session,
    String identity,
  ) {
    if (!RegExp(r'^[a-zA-Z0-9._:-]{1,128}$').hasMatch(identity)) {
      throw const FormatException('Invalid personal-record identity.');
    }
    return _send([
      'BookfinStorage',
      'v1',
      'objects',
      identity,
    ], session: session);
  }

  Future<Map<String, dynamic>> uploadPersonalRecord(
    JellyfinSession session,
    String identity,
    String payload,
  ) {
    if (!RegExp(r'^[a-zA-Z0-9._:-]{1,128}$').hasMatch(identity) ||
        payload.isEmpty ||
        utf8.encode(payload).length > 65536) {
      throw const FormatException(
        'A personal-record upload exceeds the storage contract.',
      );
    }
    return _send(
      ['BookfinStorage', 'v1', 'objects', identity],
      session: session,
      method: 'PUT',
      body: {'Payload': payload},
    );
  }

  Future<List<BookLibrary>> libraries(JellyfinSession session) async {
    final response = await _send(
      ['UserViews'],
      session: session,
      query: {'userId': session.scope.userId},
    );
    try {
      return List.unmodifiable(
        (response['Items'] as List)
            .whereType<Map<String, dynamic>>()
            .where((item) => item['CollectionType'] == 'books')
            .map(
              (item) =>
                  BookLibrary(item['Id'] as String, item['Name'] as String),
            ),
      );
    } catch (_) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    }
  }

  /// Reads the catalog of the [shown] book libraries from Jellyfin, with
  /// the collections of its items, and returns the pages undecoded. For
  /// each library, a request for one item gives Jellyfin's count, and the
  /// pages of that count follow. [catalogEntries] checks and builds them.
  /// Throws an incomplete failure when a library of [shown] is not a book
  /// library of the account, for example because Jellyfin removed it since
  /// the caller read the libraries.
  Future<CatalogPages> catalog(
    JellyfinSession session,
    Set<String> shown,
  ) async {
    final available = (await libraries(session))
        .map((library) => library.id)
        .toSet();
    if (!available.containsAll(shown)) {
      throw const CatalogFailure(CatalogFailureKind.incomplete);
    }
    // Cancellation can finish the collection read before the library read.
    // Observe its error now; the await below still propagates it to the caller.
    final collections = _collections(session, shown)..ignore();
    final pages = [
      for (final library in shown.toList()..sort())
        await _libraryPages(session, library),
    ];
    return CatalogPages(libraries: pages, collections: await collections);
  }

  /// The pages of [library]: a request for one item gives Jellyfin's count,
  /// then the pages of that count follow, [_pageRequests] at a time.
  Future<LibraryPages> _libraryPages(
    JellyfinSession session,
    String library,
  ) async {
    Map<String, String> query(int start, int limit) => {
      'userId': session.scope.userId,
      'parentId': library,
      'recursive': 'true',
      'includeItemTypes': 'AudioBook,Book,Audio',
      'fields': 'MediaSources,Chapters,People,ProviderIds,Etag,ParentId,Overview,Genres,Studios',
      'startIndex': '$start',
      'limit': '$limit',
      'enableTotalRecordCount': 'true',
      'sortBy': 'SortName',
      'sortOrder': 'Ascending',
    };
    final counted = await _send(
      ['Items'],
      session: session,
      query: query(0, 1),
    );
    final total = counted['TotalRecordCount'];
    if (total is! int) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
    }
    if (total < 0 || total > 1000000) {
      throw const CatalogFailure(CatalogFailureKind.incomplete);
    }
    final starts = [
      for (var start = 0; start < total; start += catalogPageSize) start,
    ];
    final pages = <Uint8List>[];
    for (var batch = 0; batch < starts.length; batch += _pageRequests) {
      pages.addAll(
        await Future.wait([
          for (final start in starts.skip(batch).take(_pageRequests))
            _fetchBody(
              ['Items'],
              session: session,
              query: query(start, catalogPageSize),
            ),
        ]),
      );
    }
    return (libraryId: library, total: total, pages: pages);
  }

  /// The names of the Jellyfin collections that hold each item, by item id.
  /// Collections often name a book series. Unreadable optional metadata only
  /// removes series names; cancellation and programming Errors propagate.
  Future<Map<String, List<String>>> _collections(
    JellyfinSession session,
    Set<String> shown,
  ) async {
    if (shown.isEmpty) return const {};
    try {
      final discovery = <List<_CollectionPage>>[];
      final libraries = shown.toList();
      for (var start = 0; start < libraries.length; start += _pageRequests) {
        discovery.addAll(
          await Future.wait([
            for (final library in libraries.skip(start).take(_pageRequests))
              _collectionItems(session, {
                'parentId': library,
                'includeItemTypes': 'BoxSet',
                'recursive': 'true',
              }),
          ]),
        );
      }
      final sets = await _collectionWork(
        session,
        _discoverCollections,
        discovery,
      );
      discovery.clear();
      if (sets.isEmpty) return const {};
      final children = <_CollectionMembers>[];
      for (var start = 0; start < sets.length; start += 8) {
        final batch = sets.skip(start).take(8).toList();
        final pages = await Future.wait([
          for (final set in batch)
            _collectionItems(session, {
              'parentId': set.id,
              'includeItemTypes': 'AudioBook,Book,Audio',
              // Keep direct membership: recursive lookup also admits books
              // inside a linked folder, which is a different series rule.
            }),
        ]);
        for (final (index, listing) in pages.indexed) {
          children.add((name: batch[index].name, pages: listing));
        }
      }
      return await _collectionWork(session, _collectionMembership, children);
    } on Exception catch (failure) {
      // Optional metadata can be unreadable. Programming/contract Errors
      // must propagate instead of pretending that the server has no series.
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      if (failure is CatalogFailure &&
          failure.kind == CatalogFailureKind.cancelled) {
        rethrow;
      }
      return const {};
    }
  }

  /// Reads one collection listing in bounded pages, keeping its source count.
  /// 10.11 filters direct children AFTER paging and counts unfiltered children;
  /// even an empty page must advance by the requested size, not its item count.
  /// 12.4 filters before paging. The same count-based walk handles both.
  /// Only each new page crosses to the parser; reductions receive the compact
  /// pages once, never a repeatedly copied growing accumulation of items.
  Future<List<_CollectionPage>> _collectionItems(
    JellyfinSession session,
    Map<String, String> query,
  ) async {
    final pages = <_CollectionPage>[];
    int? total;
    for (
      var start = 0;
      total == null || start < total;
      start += catalogPageSize
    ) {
      final bytes = await _fetchBody(
        ['Items'],
        session: session,
        query: {
          ...query,
          'userId': session.scope.userId,
          'startIndex': '$start',
          'limit': '$catalogPageSize',
          'enableTotalRecordCount': 'true',
          'enableImages': 'false',
          'enableUserData': 'false',
        },
      );
      final page = await _collectionWork(session, _parseCollectionPage, (
        bytes: bytes,
        start: start,
        total: total,
      ));
      total = page.total;
      pages.add(page);
    }
    return pages;
  }

  // Network and credential ownership stay here. Workers receive only response
  // data. Native compute runs off-isolate; browser compute runs on the browser's
  // event loop and gives no native isolation. A closed client cannot adopt a
  // worker result or start the next request; an already running hop may finish.
  Future<R> _collectionWork<M, R>(
    JellyfinSession session,
    R Function(M) work,
    M input,
  ) async {
    _guard(session);
    final result = await _hop(work, input);
    _guard(session);
    return result;
  }

  void _guard(JellyfinSession session) {
    if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
    if (session.needsSignIn ||
        session.scope.server != server ||
        session.token.isEmpty) {
      throw const CatalogFailure(CatalogFailureKind.unauthorized);
    }
  }

  Future<Map<String, dynamic>> _send(
    List<String> segments, {
    String method = 'GET',
    JellyfinSession? session,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    if (session != null) _guard(session);
    try {
      final result = await _transport.send(
        _uri(segments, query),
        method: method,
        headers: _headers(session),
        body: body,
      );
      if (session != null) _guard(session);
      return result;
    } on CatalogFailure catch (error) {
      if (error.kind == CatalogFailureKind.unauthorized) {
        session?.rejectCredential();
      }
      rethrow;
    }
  }

  /// Like [_send] for a GET request, but returns the response body undecoded.
  Future<Uint8List> _fetchBody(
    List<String> segments, {
    required JellyfinSession session,
    required Map<String, String> query,
  }) async {
    _guard(session);
    try {
      final result = await _transport.fetchBody(
        _uri(segments, query),
        method: 'GET',
        headers: _headers(session),
      );
      _guard(session);
      return result;
    } on CatalogFailure catch (error) {
      if (error.kind == CatalogFailureKind.unauthorized) {
        session.rejectCredential();
      }
      rethrow;
    }
  }

  Uri _uri(List<String> segments, Map<String, String>? query) => server.replace(
    pathSegments: [
      ...server.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments,
    ],
    queryParameters: query,
  );

  Map<String, String> _headers(JellyfinSession? session) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization':
        'MediaBrowser Client="Bookfin", Device="Bookfin", DeviceId="${deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')}", Version="0.1.0"${session == null ? '' : ', Token="${session.token}"'}',
    if (session != null) 'X-Emby-Token': session.token,
  };

  void close() {
    _closed = true;
    _transport.close();
  }
}
