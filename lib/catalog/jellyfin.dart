import 'dart:convert';

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
      'Cannot reach Jellyfin. Saved books are still available.',
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

  Future<List<CatalogEntry>> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) async {
    final available = (await libraries(session))
        .map((library) => library.id)
        .toSet();
    if (!available.containsAll(selected)) {
      throw const CatalogFailure(CatalogFailureKind.invalidSelection);
    }
    final entries = <CatalogEntry>[];
    final seen = <String>{};
    for (final library in selected.toList()..sort()) {
      var start = 0;
      int? total;
      while (true) {
        final response = await _send(
          ['Items'],
          session: session,
          query: {
            'userId': session.scope.userId,
            'parentId': library,
            'recursive': 'true',
            'includeItemTypes': 'AudioBook,Book,Audio',
            'fields': 'MediaSources,Chapters,People,ProviderIds,Etag,ParentId',
            'startIndex': '$start',
            'limit': '200',
            'enableTotalRecordCount': 'true',
            'sortBy': 'SortName',
            'sortOrder': 'Ascending',
          },
        );
        try {
          final page = response['Items'] as List;
          final count = response['TotalRecordCount'] as int;
          if (count < 0 ||
              count > 1000000 ||
              (total != null && total != count) ||
              (response['StartIndex'] != null &&
                  response['StartIndex'] != start) ||
              page.length > 200 ||
              start + page.length > count ||
              (page.isEmpty && start < count)) {
            throw const CatalogFailure(CatalogFailureKind.incomplete);
          }
          total = count;
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
            final safe = <String, dynamic>{
              for (final field in [
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
              ])
                if (item.containsKey(field)) field: item[field],
            };
            safe['MediaSources'] = [
              for (final source
                  in (item['MediaSources'] as List? ?? [])
                      .cast<Map<String, dynamic>>())
                {
                  for (final field in [
                    'Id',
                    'Container',
                    'Size',
                    'RunTimeTicks',
                    'ETag',
                  ])
                    if (source.containsKey(field)) field: source[field],
                },
            ];
            entries.add(CatalogEntry.fromJson(safe, libraryId: library));
          }
          start += page.length;
          if (start == total) break;
        } on CatalogFailure {
          rethrow;
        } catch (_) {
          throw const CatalogFailure(CatalogFailureKind.invalidResponse);
        }
      }
    }
    return List.unmodifiable(entries);
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
    final uri = server.replace(
      pathSegments: [
        ...server.pathSegments.where((segment) => segment.isNotEmpty),
        ...segments,
      ],
      queryParameters: query,
    );
    return _transport.send(
      uri,
      method: method,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization':
            'MediaBrowser Client="Bookfin", Device="Bookfin", DeviceId="${deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')}", Version="0.1.0"${session == null ? '' : ', Token="${session.token}"'}',
        if (session != null) 'X-Emby-Token': session.token,
      },
      body: body,
    );
  }

  void close() => _transport.close();
}
