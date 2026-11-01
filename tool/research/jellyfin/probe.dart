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
  final String token;
  final bool allowWrites;
  final HttpClient _http = HttpClient();
  final String _suffix = List.generate(
    8,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

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
    final uri = server.replace(
      path: '${server.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query.isEmpty ? null : query,
    );
    final request = await _http
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    if (token.isNotEmpty) {
      request.headers.set('X-Emby-Token', token);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>().timeout(const Duration(seconds: 20));
      throw ProbeFailure('HTTP ${response.statusCode} for $method $path');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        throw ProbeFailure('Response exceeded the 4 MiB probe limit.');
      }
    }
    return bytes.isEmpty
        ? {}
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
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

  void close() => _http.close(force: true);
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

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'nix develop --command dart run tool/research/jellyfin/probe.dart '
      '<https-server> [--secret-file <private-path>] [--allow-disposable-write]',
    );
    return;
  }
  JellyfinProbe? probe;
  try {
    final secretIndex = arguments.indexOf('--secret-file');
    final token = secretIndex < 0
        ? ''
        : (await File(arguments[secretIndex + 1]).readAsString()).trim();
    probe = JellyfinProbe(
      Uri.parse(arguments.first),
      token: token,
      allowWrites: arguments.contains('--allow-disposable-write'),
    );
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
      'evidenceClass': 'live-public-http',
      'serverOrigin': probe.server.origin,
      'version': public['Version'],
      'productName': public['ProductName'],
      'openApiVersion': schema['info']['version'],
      'routes': {
        for (final path in relevant) path: (paths[path] as Map?)?.keys.toList(),
      },
      'authenticatedChecks': token.isEmpty
          ? 'blocked-no-credentials'
          : 'read-only',
    };
    if (token.isNotEmpty) {
      final user = await probe.getJson('/Users/Me');
      final policy = user['Policy'] as Map;
      if (policy['IsAdministrator'] != false) {
        throw ProbeFailure(
          'Use an ordinary-user session token, not an administrator token.',
        );
      }
      report['ordinaryUserPolicy'] = {
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
    probe?.close();
  }
}
