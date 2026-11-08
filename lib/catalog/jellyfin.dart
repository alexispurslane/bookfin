import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  invalidSelection,
}

class CatalogFailure implements Exception {
  const CatalogFailure(this.kind);
  final CatalogFailureKind kind;
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
    CatalogFailureKind.invalidSelection =>
      'Choose only book libraries available to this account.',
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

class JellyfinSession {
  const JellyfinSession({
    required this.scope,
    required this.token,
    required this.username,
    required this.canDownload,
  });
  final AccountScope scope;
  final String token;
  final String username;
  final bool canDownload;
  Map<String, dynamic> toJson() => {
    'scope': scope.toJson(),
    'token': token,
    'username': username,
    'canDownload': canDownload,
  };
  factory JellyfinSession.fromJson(Map<String, dynamic> json) =>
      JellyfinSession(
        scope: AccountScope.fromJson(json['scope'] as Map<String, dynamic>),
        token: json['token'] as String,
        username: json['username'] as String,
        canDownload: json['canDownload'] == true,
      );
  @override
  String toString() => 'JellyfinSession(<redacted>)';
}

class BookLibrary {
  const BookLibrary(this.id, this.name);
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// The number of catalog items in a full page from Jellyfin.
const catalogPageSize = 200;

/// The pages of one selected book library as Jellyfin sent them: the id of
/// the library, how many items Jellyfin counted in it, and the body of each
/// page, in order. Page `n` starts at item `n * catalogPageSize`.
typedef LibraryPages = ({String libraryId, int total, List<Uint8List> pages});

/// Jellyfin's answer to a catalog read, not yet decoded: the pages of each
/// selected book library, in order, and the names of the collections that
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

class JellyfinClient {
  JellyfinClient(Uri server, {required this.deviceId, JsonTransport? transport})
    : server = parseServer(server.toString()),
      _transport = transport ?? createTransport();
  final Uri server;
  final String deviceId;
  final JsonTransport _transport;
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
    return JellyfinSession(
      scope: session.scope,
      token: session.token,
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

  /// Reads the catalog of the [selected] book libraries from Jellyfin,
  /// with the collections of its items, and returns the pages undecoded.
  /// For each library, a request for one item gives Jellyfin's count, and
  /// the pages of that count follow. [catalogEntries] checks and builds them.
  Future<CatalogPages> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) async {
    final available = (await libraries(session))
        .map((library) => library.id)
        .toSet();
    if (!available.containsAll(selected)) {
      throw const CatalogFailure(CatalogFailureKind.invalidSelection);
    }
    final collections = _collections(session);
    final List<LibraryPages> pages;
    try {
      pages = [
        for (final library in selected.toList()..sort())
          await _libraryPages(session, library),
      ];
    } catch (_) {
      collections.ignore();
      rethrow;
    }
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
  /// Collections often name a book series. A collection that cannot
  /// be read only removes series names, so it never fails the catalog.
  Future<Map<String, List<String>>> _collections(
    JellyfinSession session,
  ) async {
    try {
      final sets =
          ((await _send(
                    ['Items'],
                    session: session,
                    query: {
                      'userId': session.scope.userId,
                      'includeItemTypes': 'BoxSet',
                      'recursive': 'true',
                      'limit': '1000',
                    },
                  ))['Items']
                  as List)
              .whereType<Map<String, dynamic>>()
              .where((set) => set['Id'] is String && set['Name'] is String)
              .toList();
      final result = <String, List<String>>{};
      for (var start = 0; start < sets.length; start += 8) {
        final batch = sets.skip(start).take(8).toList();
        final children = await Future.wait([
          for (final set in batch)
            _send(
              ['Items'],
              session: session,
              query: {
                'userId': session.scope.userId,
                'parentId': set['Id'] as String,
                'limit': '2000',
              },
            ),
        ]);
        for (final (index, page) in children.indexed) {
          for (final child in (page['Items'] as List? ?? []).whereType<Map>()) {
            final id = child['Id'];
            if (id is String) {
              result.putIfAbsent(id, () => []).add(batch[index]['Name']);
            }
          }
        }
      }
      return result;
    } on CatalogFailure catch (failure) {
      if (failure.kind == CatalogFailureKind.cancelled) rethrow;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  void _guard(JellyfinSession session) {
    if (session.scope.server != server || session.token.isEmpty) {
      throw const CatalogFailure(CatalogFailureKind.unauthorized);
    }
  }

  Future<Map<String, dynamic>> _send(
    List<String> segments, {
    String method = 'GET',
    JellyfinSession? session,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) {
    if (session != null) _guard(session);
    return _transport.send(
      _uri(segments, query),
      method: method,
      headers: _headers(session),
      body: body,
    );
  }

  /// Like [_send] for a GET request, but returns the response body undecoded.
  Future<Uint8List> _fetchBody(
    List<String> segments, {
    required JellyfinSession session,
    required Map<String, String> query,
  }) {
    _guard(session);
    return _transport.fetchBody(
      _uri(segments, query),
      method: 'GET',
      headers: _headers(session),
    );
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

  void close() => _transport.close();
}
