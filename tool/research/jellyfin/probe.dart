import 'dart:convert';
import 'dart:io';
import 'dart:math';

class ProbeFailure implements Exception {
  ProbeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class JellyfinProbe {
  JellyfinProbe(this.server, {this.token = '', this.allowWrites = false}) {
    final loopback = ['127.0.0.1', '::1'].contains(server.host);
    if ((server.scheme != 'https' && !(loopback && server.scheme == 'http')) ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      throw ProbeFailure('Use HTTPS without embedded credentials or query.');
    }
  }

  final Uri server;
  String token;
  final bool allowWrites;
  final Set<HttpClient> _activeClients = {};
  final String _suffix = List.generate(
    8,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> login(File secret) async {
    Map<String, dynamic> credentials;
    try {
      credentials =
          jsonDecode(await secret.readAsString()) as Map<String, dynamic>;
      if (['Username', 'Pw'].any(
        (key) =>
            credentials[key] is! String ||
            (credentials[key] as String).trim().isEmpty,
      )) {
        throw const FormatException();
      }
    } catch (_) {
      throw ProbeFailure(
        'Login file must contain nonempty Username and Pw strings.',
      );
    }
    final result = await _request(
      'POST',
      '/Users/AuthenticateByName',
      body: {'Username': credentials['Username'], 'Pw': credentials['Pw']},
    );
    if (result['AccessToken'] is! String ||
        (result['AccessToken'] as String).isEmpty) {
      throw ProbeFailure('Login did not return a session token.');
    }
    token = result['AccessToken'] as String;
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/Sessions/Logout');
    } finally {
      token = '';
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> query = const {},
  }) async {
    return _request('GET', path, query: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
  }) async {
    final response = await _exchange(method, path, query: query, body: body);
    return response.bytes.isEmpty
        ? {}
        : jsonDecode(utf8.decode(response.bytes)) as Map<String, dynamic>;
  }

  Future<({List<int> bytes, int status, String? contentRange})> _exchange(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    String? range,
    int byteLimit = 4 * 1024 * 1024,
  }) async {
    final uri = server.replace(
      path: '${server.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query.isEmpty ? null : query,
    );
    final client = HttpClient();
    _activeClients.add(client);

    Future<({List<int> bytes, int status, String? contentRange})>
    readResponse() async {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      request.headers.set(
        'Authorization',
        'MediaBrowser Client="BookfinResearch", Device="BoundedResearch", DeviceId="bookfin-research-$_suffix", Version="1"${token.isEmpty ? '' : ', Token="$token"'}',
      );
      if (token.isNotEmpty) {
        request.headers.set('X-Emby-Token', token);
      }
      if (range != null) {
        request.headers.set('Range', range);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > byteLimit) {
          throw ProbeFailure(
            'Response exceeded the $byteLimit-byte probe limit.',
          );
        }
        bytes.addAll(chunk);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProbeFailure(
          'HTTP ${response.statusCode} for $method request; response suppressed.',
        );
      }
      return (
        bytes: bytes,
        status: response.statusCode,
        contentRange: response.headers.value('Content-Range'),
      );
    }

    try {
      return await readResponse().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw ProbeFailure(
          'Request exceeded the total 20-second deadline.',
        ),
      );
    } finally {
      // A timed-out future alone leaves its socket running. Each request owns
      // its client so cancellation does not prevent later cleanup requests.
      client.close(force: true);
      _activeClients.remove(client);
    }
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await _exchange('GET', path);
    return jsonDecode(utf8.decode(response.bytes)) as List<dynamic>;
  }

  Future<Map<String, dynamic>> inspectRange(
    String itemId,
    String endpoint,
    int start,
  ) async {
    try {
      final response = await _exchange(
        'GET',
        '/Items/$itemId/$endpoint',
        range: 'bytes=$start-${start + 63}',
        byteLimit: 64,
      );
      return {
        'endpoint': endpoint,
        'startByte': start,
        'status': response.status,
        'receivedBytes': response.bytes.length,
        'validPartialResponse':
            response.status == 206 &&
            response.bytes.length == 64 &&
            RegExp('^bytes $start-${start + 63}/[0-9]+\$')
                .hasMatch(response.contentRange ?? ''),
      };
    } on ProbeFailure {
      return {
        'endpoint': endpoint,
        'startByte': start,
        'outcome': 'bounded-read-refused',
      };
    }
  }

  Future<void> replaceResearchPreferences(Map<String, String> values) async {
    if (!allowWrites || token.isEmpty) {
      throw ProbeFailure(
        'Research writes require a token and --allow-disposable-write.',
      );
    }
    if (values.keys.any((key) => !key.startsWith('bookfin.'))) {
      throw ProbeFailure('Only bookfin. research keys can be written.');
    }
    if (values.values.any((value) => utf8.encode(value).length > 16384) ||
        utf8.encode(jsonEncode(values)).length > 32768) {
      throw ProbeFailure(
        'Research values exceed the 16 KiB value or 32 KiB set limit.',
      );
    }
    final user = await getJson('/Users/Me');
    final policy = user['Policy'];
    if (policy is! Map || policy['IsAdministrator'] != false) {
      throw ProbeFailure(
        'A verified ordinary-user token is required, not an admin API key.',
      );
    }
    final existing = await researchPreferences();
    final custom = Map<String, dynamic>.from(existing['CustomPrefs'] as Map);
    custom.removeWhere((key, value) => key.startsWith('bookfin.'));
    custom.addAll(values);
    final body = {...existing, 'CustomPrefs': custom};
    if (utf8.encode(jsonEncode(body)).length > 65536) {
      throw ProbeFailure('Research request exceeds the 64 KiB probe limit.');
    }
    await _request(
      'POST',
      '/DisplayPreferences/bookfin-research-$_suffix',
      query: {'client': 'BookfinResearch-$_suffix'},
      body: body,
    );
  }

  Future<Map<String, dynamic>> researchPreferences() => getJson(
    '/DisplayPreferences/bookfin-research-$_suffix',
    query: {'client': 'BookfinResearch-$_suffix'},
  );

  void close() {
    for (final client in _activeClients) {
      client.close(force: true);
    }
    _activeClients.clear();
  }
}

Map<String, dynamic> summarizeCatalog(Map<String, dynamic> catalog) {
  final items = (catalog['Items'] as List? ?? []).cast<Map<String, dynamic>>();
  final types = <String, int>{};
  const allowedTypes = {
    'AudioBook',
    'Audio',
    'Book',
    'Folder',
    'CollectionFolder',
    'UserView',
  };
  for (final item in items) {
    final type = allowedTypes.contains(item['Type'])
        ? item['Type'] as String
        : 'Other';
    types.update(type, (count) => count + 1, ifAbsent: () => 1);
  }
  return {
    'totalRecordCount': catalog['TotalRecordCount'],
    'sampledItems': items.length,
    'itemTypes': types,
    'itemsWithChapters': items
        .where((item) => (item['Chapters'] as List? ?? []).isNotEmpty)
        .length,
    'itemsWithProviderIds': items
        .where((item) => (item['ProviderIds'] as Map? ?? {}).isNotEmpty)
        .length,
  };
}

String safeContainer(dynamic value) {
  const known = {
    'mp4',
    'm4b',
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'epub',
    'mobi',
    'azw',
    'azw3',
    'pdf',
    'html',
    'htm',
    'md',
    'markdown',
    'cbz',
    'cbr',
  };
  final normalized = value is String ? value.toLowerCase() : '';
  return known.contains(normalized) ? normalized : 'Other';
}

String mediaContainer(Map<String, dynamic> item) {
  final sources = item['MediaSources'] as List? ?? [];
  return safeContainer(
    item['Container'] ??
        (sources.isEmpty ? null : (sources.first as Map)['Container']),
  );
}

Future<Map<String, dynamic>> inspectMedia(
  JellyfinProbe probe,
  List<Map<String, dynamic>> libraries,
) async {
  final report = <String, dynamic>{
    'typeSamples': <Map<String, dynamic>>[],
    'representativeFiles': <Map<String, dynamic>>[],
  };
  for (final library in libraries.take(3)) {
    for (final type in ['AudioBook', 'Audio', 'Book', 'Folder']) {
      final catalog = await probe.getJson(
        '/Items',
        query: {
          'ParentId': library['Id'] as String,
          'Recursive': 'true',
          'Limit': '30',
          'IncludeItemTypes': type,
          'Fields': 'Chapters,MediaSources,ProviderIds,ParentId',
          'EnableUserData': 'true',
        },
      );
      final items = (catalog['Items'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final containers = <String, int>{};
      for (final item in items) {
        final container = mediaContainer(item);
        containers.update(container, (count) => count + 1, ifAbsent: () => 1);
      }
      (report['typeSamples'] as List).add({
        'requestedType': type,
        ...summarizeCatalog(catalog),
        'containers': containers,
        'itemsWithMultipleMediaSources': items
            .where((item) => (item['MediaSources'] as List? ?? []).length > 1)
            .length,
        'itemsWithTrackOrder': items
            .where((item) => item['IndexNumber'] is num)
            .length,
        'distinctParentCount': items
            .map((item) => item['ParentId'])
            .whereType<String>()
            .toSet()
            .length,
      });
      if (items.isEmpty || type == 'Folder') continue;
      final byContainer = <String, Map<String, dynamic>>{};
      for (final item in items) {
        byContainer.putIfAbsent(mediaContainer(item), () => item);
      }
      for (final item in byContainer.values.take(2)) {
        final itemId = item['Id'] as String;
        final before = await probe.getJson(
          '/Items/$itemId',
          query: {
            'EnableUserData': 'true',
            'Fields': 'Chapters,MediaSources,ParentId',
          },
        );
        final playback = await probe.getJson('/Items/$itemId/PlaybackInfo');
        final sources = (before['MediaSources'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final parent = item['ParentId'];
        final siblings = parent is String
            ? await probe.getJson(
                '/Items',
                query: {
                  'ParentId': parent,
                  'Recursive': 'false',
                  'Limit': '30',
                  'Fields': 'Chapters,MediaSources,ParentId',
                  'EnableUserData': 'false',
                },
              )
            : <String, dynamic>{};
        final siblingItems = (siblings['Items'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final chapters =
            (before['Chapters'] as List? ?? item['Chapters'] as List? ?? [])
                .cast<Map<String, dynamic>>();
        final starts = chapters
            .map((chapter) => chapter['StartPositionTicks'])
            .whereType<num>()
            .toList();
        final ranges = <Map<String, dynamic>>[];
        for (final endpoint in ['File', 'Download']) {
          for (final start in [0, 64]) {
            ranges.add(await probe.inspectRange(itemId, endpoint, start));
          }
        }
        final after = await probe.getJson(
          '/Items/$itemId',
          query: {'EnableUserData': 'true'},
        );
        (report['representativeFiles'] as List).add({
          'requestedType': type,
          'container': mediaContainer(before),
          'sourceFileExtensions': [
            for (final source in sources)
              safeContainer((source['Path'] as String? ?? '').split('.').last),
          ],
          'chapterCount': chapters.length,
          'chapterStartTicksPresent': starts.length == chapters.length,
          'chapterStartsNonnegativeAndOrdered':
              starts.every((value) => value >= 0) &&
              List.generate(
                starts.isNotEmpty ? starts.length - 1 : 0,
                (index) => starts[index] <= starts[index + 1],
              ).every((value) => value),
          'mediaSourceCount': (before['MediaSources'] as List? ?? []).length,
          'playbackInfoMediaSourceCount':
              (playback['MediaSources'] as List? ?? []).length,
          'siblings': summarizeCatalog(siblings),
          'audioAndEbookShareParent':
              siblingItems.any(
                (sibling) =>
                    sibling['Type'] == 'AudioBook' ||
                    sibling['Type'] == 'Audio',
              ) &&
              siblingItems.any((sibling) => sibling['Type'] == 'Book'),
          'ranges': ranges,
          'userDataPresent':
              before['UserData'] is Map && after['UserData'] is Map,
          'userDataUnchanged':
              jsonEncode(before['UserData']) == jsonEncode(after['UserData']),
        });
      }
    }
  }
  return report;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'nix develop --command dart run tool/research/jellyfin/probe.dart '
      '<https-server> [--secret-file <private-path> | --login-file <private-path>] [--inspect-media] [--allow-disposable-write]',
    );
    return;
  }
  JellyfinProbe? probe;
  var createdSession = false;
  try {
    final secretIndex = arguments.indexOf('--secret-file');
    final loginIndex = arguments.indexOf('--login-file');
    if (secretIndex >= 0 && loginIndex >= 0) {
      throw ProbeFailure(
        'Choose one private token file or private login file.',
      );
    }
    final token = secretIndex < 0
        ? ''
        : (await File(arguments[secretIndex + 1]).readAsString()).trim();
    probe = JellyfinProbe(
      Uri.parse(arguments.first),
      token: token,
      allowWrites: arguments.contains('--allow-disposable-write'),
    );
    if (loginIndex >= 0) {
      await probe.login(File(arguments[loginIndex + 1]));
      createdSession = true;
    }
    final public = await probe.getJson('/System/Info/Public');
    final schema = await probe.getJson('/api-docs/openapi.json');
    final paths = schema['paths'] as Map;
    const relevant = [
      '/DisplayPreferences/{displayPreferencesId}',
      '/UserViews',
      '/Users/Me',
      '/Items',
      '/Items/{itemId}',
      '/Items/{itemId}/PlaybackInfo',
      '/Items/{itemId}/Download',
      '/Items/{itemId}/File',
      '/Sessions/Playing',
      '/Sessions/Playing/Progress',
      '/Sessions/Playing/Stopped',
    ];
    final report = <String, dynamic>{
      'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'evidenceClass': probe.token.isEmpty
          ? 'live-public-http'
          : 'live-authenticated-http',
      'serverOrigin': probe.server.origin,
      'version': public['Version'],
      'productName': public['ProductName'],
      'openApiVersion': schema['info']['version'],
      'routes': {
        for (final path in relevant) path: (paths[path] as Map?)?.keys.toList(),
      },
      'authenticatedChecks': probe.token.isEmpty
          ? 'blocked-no-credentials'
          : 'read-only',
    };
    if (probe.token.isNotEmpty) {
      final user = await probe.getJson('/Users/Me');
      final policy = user['Policy'] as Map;
      if (probe.allowWrites && policy['IsAdministrator'] != false) {
        throw ProbeFailure(
          'Use an ordinary-user session token, not an administrator token.',
        );
      }
      report['ordinaryUserIsolation'] = 'unproven';
      report['accountPolicy'] = {
        for (final key in [
          'IsAdministrator',
          'EnableContentDownloading',
          'EnableMediaPlayback',
          'EnableAudioPlaybackTranscoding',
        ])
          key: policy[key],
      };
      final views = await probe.getJson('/UserViews');
      final bookViews = (views['Items'] as List)
          .cast<Map<String, dynamic>>()
          .where((item) => item['CollectionType'] == 'books')
          .toList();
      report['bookLibraryCount'] = bookViews.length;
      report['librarySamples'] = <Map<String, dynamic>>[];
      for (final view in bookViews.take(3)) {
        final catalog = await probe.getJson(
          '/Items',
          query: {
            'ParentId': view['Id'] as String,
            'Recursive': 'true',
            'Limit': '30',
            'IncludeItemTypes': 'AudioBook,Book,Audio',
            'Fields': 'Chapters,MediaSources,ProviderIds,ParentId',
            'EnableUserData': 'true',
          },
        );
        (report['librarySamples'] as List).add(summarizeCatalog(catalog));
      }
      if (arguments.contains('--inspect-media')) {
        report['mediaInspection'] = await inspectMedia(probe, bookViews);
        if (policy['IsAdministrator'] == true) {
          final plugins = await probe.getList('/Plugins');
          report['enhancedPlugin'] = [
            for (final plugin in plugins.whereType<Map>())
              if ((plugin['Name'] as String? ?? '').toLowerCase().contains(
                'enhanced',
              ))
                {'version': plugin['Version'], 'status': plugin['Status']},
          ];
        }
      }
      if (probe.allowWrites) {
        stderr.writeln(
          'Disposable scope: bookfin-research-${probe._suffix}; '
          'client=BookfinResearch-${probe._suffix}',
        );
        final sizes = <int>[];
        try {
          for (final size in [1024, 4096, 16384]) {
            final value = 'x' * size;
            await probe.replaceResearchPreferences({
              'bookfin.synthetic': value,
            });
            await probe.replaceResearchPreferences({
              'bookfin.synthetic': value,
            });
            final result = await probe.researchPreferences();
            if (result['CustomPrefs']['bookfin.synthetic'] != value) {
              throw ProbeFailure('Synthetic preference round trip failed.');
            }
            sizes.add(size);
          }
        } finally {
          await probe.replaceResearchPreferences({});
        }
        final cleaned = await probe.researchPreferences();
        final deletion = !(cleaned['CustomPrefs'] as Map).keys.any(
          (key) => (key as String).startsWith('bookfin.'),
        );
        if (!deletion) {
          throw ProbeFailure('Synthetic preference cleanup failed.');
        }
        report['disposablePreferenceChecks'] = {
          'acceptedValueBytes': sizes,
          'identicalRetry': true,
          'customKeyDeletion': deletion,
          'namespace': 'bookfin-research-${probe._suffix}',
          'client': 'BookfinResearch-${probe._suffix}',
          'scopeRowsRemain': true,
        };
      }
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } catch (error) {
    stderr.writeln(
      error is ProbeFailure
          ? error.message
          : 'Probe failed; private response details suppressed.',
    );
    exitCode = 1;
  } finally {
    if (createdSession) {
      try {
        await probe?.logout();
      } catch (_) {
        stderr.writeln(
          'Research session logout failed; revoke its session in Jellyfin.',
        );
        exitCode = 1;
      }
    }
    probe?.close();
  }
}
