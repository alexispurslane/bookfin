import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'probe.dart';

void main() {
  late HttpServer fixture;
  late JellyfinProbe probe;
  late List<String> requests;
  late Map<String, Map<String, dynamic>> preferences;
  var administrator = false;
  var redirect = false;
  var failWrites = false;
  var detailedCatalog = false;
  var ignoreRange = false;
  var multipleContainers = false;
  final requestedRanges = <String>[];
  Map<String, dynamic>? loginBody;
  String? authorization;
  String? receivedToken;

  setUp(() async {
    requests = [];
    preferences = {};
    administrator = false;
    redirect = false;
    failWrites = false;
    detailedCatalog = false;
    ignoreRange = false;
    multipleContainers = false;
    requestedRanges.clear();
    loginBody = null;
    authorization = null;
    receivedToken = null;
    fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixture.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (redirect) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/credential-collector');
      } else if (request.uri.path == '/Users/AuthenticateByName') {
        authorization = request.headers.value('Authorization');
        loginBody = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        request.response.write(
          '{"AccessToken":"fixture-login-token","User":{"Name":"PRIVATE USER"}}',
        );
      } else if (request.uri.path == '/Users/Me') {
        receivedToken = request.headers.value('X-Emby-Token');
        if (receivedToken == 'fixture-login-token' &&
            !(request.headers.value('Authorization') ?? '').contains(
              'Token="fixture-login-token"',
            )) {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        request.response.write(
          jsonEncode({
            'Policy': {'IsAdministrator': administrator},
          }),
        );
      } else if (request.uri.path == '/api-docs/openapi.json') {
        request.response.write('{"info":{"version":"fixture"},"paths":{}}');
      } else if (request.uri.path == '/UserViews') {
        request.response.write(
          detailedCatalog
              ? '{"Items":[{"Id":"PRIVATE-LIBRARY","CollectionType":"books"}]}'
              : '{"Items":[]}',
        );
      } else if (request.uri.path == '/Plugins') {
        request.response.write(
          '[{"Name":"Jellyfin Enhanced","Version":"12.14.0.0","Id":"PRIVATE"}]',
        );
      } else if (request.uri.path == '/JellyfinEnhanced/version') {
        request.response.write('12.14.0.0');
      } else if (request.uri.path == '/Items') {
        if ([
          'Audio',
          'Folder',
        ].contains(request.uri.queryParameters['IncludeItemTypes'])) {
          request.response.write('{"TotalRecordCount":0,"Items":[]}');
          await request.response.close();
          return;
        }
        final type = request.uri.queryParameters['IncludeItemTypes'] == 'Book'
            ? 'Book'
            : 'AudioBook';
        final items = <Map<String, dynamic>>[
          {
            'Id': 'PRIVATE-ITEM-$type',
            'Type': type,
            'Name': 'PRIVATE TITLE',
            'ParentId': 'PRIVATE-PARENT',
            'IndexNumber': 1,
            'Chapters': [
              {'Name': 'PRIVATE CHAPTER', 'StartPositionTicks': 0},
            ],
            'MediaSources': [
              {
                'Id': 'PRIVATE-SOURCE',
                'Path': 'PRIVATE PATH',
                'Container': type == 'Book' ? 'epub' : 'm4b',
              },
            ],
          },
        ];
        if (multipleContainers && type == 'AudioBook') {
          for (final container in ['mp3', 'm4b']) {
            items.add({
              ...items.first,
              'Id': 'PRIVATE-ITEM-$container',
              'MediaSources': [
                {'Container': container},
              ],
            });
          }
        }
        request.response.write(
          jsonEncode({'TotalRecordCount': items.length, 'Items': items}),
        );
      } else if (request.uri.path.endsWith('/File') ||
          request.uri.path.endsWith('/Download')) {
        final range = request.headers.value('range')!;
        requestedRanges.add(range);
        request.response.statusCode = ignoreRange ? 200 : 206;
        request.response.headers.set(
          'Content-Range',
          range == 'bytes=0-63' ? 'bytes 0-63/256' : 'bytes 64-127/256',
        );
        request.response.add(List.filled(ignoreRange ? 256 : 64, 0));
      } else if (request.uri.path.endsWith('/PlaybackInfo')) {
        request.response.write('{"MediaSources":[{"Id":"PRIVATE-SOURCE"}]}');
      } else if (request.uri.path.startsWith('/Items/')) {
        request.response.write(
          '{"UserData":{"PlaybackPositionTicks":123,"Played":false,"PlayCount":1},"MediaSources":[{"Id":"PRIVATE-SOURCE"}]}',
        );
      } else if (request.uri.path.startsWith('/DisplayPreferences/')) {
        final key = request.uri.toString();
        if (request.method == 'POST') {
          if (failWrites) {
            request.response.statusCode = 500;
            request.response.write('PRIVATE RESPONSE fixture-token');
            await request.response.close();
            return;
          }
          preferences[key] = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          request.response.statusCode = 204;
        } else {
          request.response.write(
            jsonEncode(
              preferences[key] ??
                  {
                    'Id': 'fixture-only',
                    'ShowSidebar': true,
                    'CustomPrefs': {'skipForwardLength': '15000'},
                  },
            ),
          );
        }
      } else {
        request.response.write('{"Version":"fixture"}');
      }
      await request.response.close();
    });
    probe = JellyfinProbe(
      Uri.parse('http://127.0.0.1:${fixture.port}'),
      token: 'fixture-token',
      allowWrites: true,
    );
  });

  tearDown(() async {
    probe.close();
    await fixture.close(force: true);
  });

  Future<ProcessResult> runAuthenticatedCommand({
    bool login = false,
    bool write = true,
    String? loginJson,
    bool inspect = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'bookfin-probe-token-',
    );
    final secret = File('${directory.path}/token');
    await secret.writeAsString(
      login
          ? loginJson ?? '{"Username":"PRIVATE USER","Pw":"PRIVATE PASSWORD"}'
          : 'fixture-token',
    );
    try {
      return await Process.run('dart', [
        'run',
        'tool/research/jellyfin/probe.dart',
        probe.server.toString(),
        login ? '--login-file' : '--secret-file',
        secret.path,
        if (write) '--allow-disposable-write',
        if (inspect) '--inspect-media',
      ]);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  test('media inspection reports bounded ranges without private catalog values or playback writes', () async {
    detailedCatalog = true;
    administrator = true;
    final result = await runAuthenticatedCommand(
      login: true,
      write: false,
      inspect: true,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String) as Map;
    final inspection = report['mediaInspection'] as Map?;
    expect(inspection, isNotNull);
    final files = inspection!['representativeFiles'] as List;
    expect(files.length, 2);
    expect(files.every((file) => file['userDataUnchanged'] == true), true);
    expect(requestedRanges, hasLength(8));
    expect(requestedRanges.toSet(), {'bytes=0-63', 'bytes=64-127'});
    expect('${result.stdout}${result.stderr}', isNot(contains('PRIVATE')));
    expect(requests.where((request) => request.startsWith('POST ')), [
      'POST /Users/AuthenticateByName',
      'POST /Sessions/Logout',
    ]);
  });

  test(
    'media inspection rejects a server that ignores a small byte range',
    () async {
      detailedCatalog = true;
      administrator = true;
      ignoreRange = true;
      final result = await runAuthenticatedCommand(
        login: true,
        write: false,
        inspect: true,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report = jsonDecode(result.stdout as String) as Map;
      final inspection = report['mediaInspection'] as Map?;
      expect(inspection, isNotNull);
      final files = inspection!['representativeFiles'] as List;
      expect(
        files.first['ranges'].every(
          (range) => range['outcome'] == 'bounded-read-refused',
        ),
        true,
      );
      expect('${result.stdout}${result.stderr}', isNot(contains('PRIVATE')));
    },
  );

  test('ordinary-user media inspection does not request the administrative plugin list', () async {
    final result = await runAuthenticatedCommand(
      login: true,
      write: false,
      inspect: true,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(requests, isNot(contains('GET /Plugins')));
  });

  test('catalog inspection counts loose audio and folders separately from ebooks and audiobooks', () async {
    detailedCatalog = true;
    final result = await runAuthenticatedCommand(
      login: true,
      write: false,
      inspect: true,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String) as Map;
    final samples = report['mediaInspection']['typeSamples'] as List;
    expect(samples.map((sample) => sample['requestedType']).toSet(), {
      'AudioBook',
      'Audio',
      'Book',
      'Folder',
    });
    final audio = samples.firstWhere(
      (sample) => sample['requestedType'] == 'AudioBook',
    ) as Map;
    expect(audio['containers'], {'m4b': 1});
  });

  test('media inspection samples two distinct containers rather than every audio file', () async {
    detailedCatalog = true;
    multipleContainers = true;
    final result = await runAuthenticatedCommand(
      login: true,
      write: false,
      inspect: true,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String) as Map;
    final files = report['mediaInspection']['representativeFiles'] as List;
    expect(
      files.where((file) => file['requestedType'] == 'AudioBook').length,
      2,
    );
    expect(requestedRanges.length, 12);
    expect('${result.stdout}${result.stderr}', isNot(contains('PRIVATE')));
  });

  test(
    'private login authenticates without disclosing credentials or token',
    () async {
      final result = await runAuthenticatedCommand(login: true, write: false);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(loginBody, {'Username': 'PRIVATE USER', 'Pw': 'PRIVATE PASSWORD'});
      expect(authorization, contains('Client="BookfinResearch"'));
      expect(receivedToken, 'fixture-login-token');
      expect('${result.stdout}${result.stderr}', isNot(contains('PRIVATE')));
      expect(
        '${result.stdout}${result.stderr}',
        isNot(contains('fixture-login-token')),
      );
    },
  );

  test('administrator login permits read-only catalog investigation', () async {
    administrator = true;
    final result = await runAuthenticatedCommand(login: true, write: false);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String) as Map;
    expect(report['accountPolicy']['IsAdministrator'], true);
    expect(report['ordinaryUserIsolation'], 'unproven');
    expect(requests.where((request) => request.startsWith('POST ')), [
      'POST /Users/AuthenticateByName',
      'POST /Sessions/Logout',
    ]);
  });

  test(
    'invalid private login files are refused without contacting the server',
    () async {
      final result = await runAuthenticatedCommand(
        login: true,
        write: false,
        loginJson: '{"Username":"PRIVATE USER","Pw":""}',
      );
      expect(result.exitCode, 1);
      expect(requests, isEmpty);
      expect(
        result.stderr,
        contains('Login file must contain nonempty Username and Pw strings.'),
      );
      expect(result.stderr, isNot(contains('PRIVATE')));
    },
  );

  test(
    'the full synthetic command verifies writes and cleans research keys',
    () async {
      final result = await runAuthenticatedCommand();
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report = jsonDecode(result.stdout as String) as Map;
      expect(report['disposablePreferenceChecks']['acceptedValueBytes'], [
        1024,
        4096,
        16384,
      ]);
      expect(report['disposablePreferenceChecks']['customKeyDeletion'], true);
      expect(preferences.values.single['CustomPrefs'], {
        'skipForwardLength': '15000',
      });
    },
  );

  test('a failed command identifies only its disposable scope without leaking responses', () async {
    failWrites = true;
    final result = await runAuthenticatedCommand();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('bookfin-research-'));
    expect(result.stderr, contains('BookfinResearch-'));
    expect(result.stderr, isNot(contains('PRIVATE RESPONSE')));
    expect(result.stderr, isNot(contains('fixture-token')));
    expect(result.stdout, isEmpty);
  });

  test(
    'the probe reads the public version without exposing response fields',
    () async {
      expect(await probe.getJson('/System/Info/Public'), {
        'Version': 'fixture',
      });
    },
  );

  test('the probe refuses plaintext credentials outside loopback', () {
    expect(
      () => JellyfinProbe(Uri.parse('http://example.com'), token: 'secret'),
      throwsA(isA<ProbeFailure>()),
    );
  });

  test(
    'a continuously trickling response is cancelled at the total deadline',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final disconnected = Completer<void>();
      final sockets = <Socket>[];
      Timer? trickle;
      server.listen((socket) {
        sockets.add(socket);
        unawaited(
          socket.done.then<void>(
            (_) {},
            onError: (Object error) {
              if (error is! SocketException) throw error;
            },
          ),
        );
        var headers = '';
        var started = false;
        socket.listen(
          (data) {
            if (started) return;
            headers += ascii.decode(data);
            if (!headers.contains('\r\n\r\n')) return;
            started = true;
            socket.write(
              'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n{\r\n',
            );
            trickle = Timer.periodic(const Duration(milliseconds: 100), (
              timer,
            ) {
              if (timer.tick == 220) {
                socket.write('1\r\n}\r\n0\r\n\r\n');
                timer.cancel();
              } else {
                socket.write('1\r\n \r\n');
              }
            });
          },
          onDone: () {
            trickle?.cancel();
            if (!disconnected.isCompleted) disconnected.complete();
            socket.destroy();
          },
          onError: (Object error) {
            trickle?.cancel();
            if (!disconnected.isCompleted) disconnected.complete();
            socket.destroy();
          },
        );
      });
      final slow = JellyfinProbe(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(() async {
        slow.close();
        trickle?.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      });
      await expectLater(slow.getJson('/slow'), throwsA(isA<ProbeFailure>()));
      await disconnected.future.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'a redirect does not receive an authenticated follow-up request',
    () async {
      redirect = true;
      await expectLater(
        probe.getJson('/Users/Me'),
        throwsA(isA<ProbeFailure>()),
      );
      expect(requests, ['GET /Users/Me']);
    },
  );

  test(
    'writes require an explicit flag before even reading preferences',
    () async {
      final readonly = JellyfinProbe(probe.server, token: 'fixture-token');
      addTearDown(readonly.close);
      await expectLater(
        readonly.replaceResearchPreferences({'bookfin.sample': 'a'}),
        throwsA(isA<ProbeFailure>()),
      );
      expect(requests, isEmpty);
    },
  );

  test('an administrator token cannot perform a research write', () async {
    administrator = true;
    await expectLater(
      probe.replaceResearchPreferences({'bookfin.sample': 'a'}),
      throwsA(isA<ProbeFailure>()),
    );
    expect(requests, ['GET /Users/Me']);
  });

  test('unknown user policy cannot authorize a research write', () async {
    final emptyPolicy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    emptyPolicy.listen((request) async {
      request.response.write('{}');
      await request.response.close();
    });
    final unknown = JellyfinProbe(
      Uri.parse('http://127.0.0.1:${emptyPolicy.port}'),
      token: 'fixture-token',
      allowWrites: true,
    );
    addTearDown(() async {
      unknown.close();
      await emptyPolicy.close(force: true);
    });
    await expectLater(
      unknown.replaceResearchPreferences({'bookfin.sample': 'a'}),
      throwsA(isA<ProbeFailure>()),
    );
  });

  test('only research keys can be supplied for a research write', () async {
    await expectLater(
      probe.replaceResearchPreferences({'skipForwardLength': '1'}),
      throwsA(isA<ProbeFailure>()),
    );
    expect(requests, isEmpty);
  });

  test('oversized values are refused without contacting the server', () async {
    await expectLater(
      probe.replaceResearchPreferences({'bookfin.sample': 'x' * 16385}),
      throwsA(isA<ProbeFailure>()),
    );
    expect(requests, isEmpty);
  });

  test(
    'a retry keeps the same research state and preserves server defaults',
    () async {
      await probe.replaceResearchPreferences({
        'bookfin.sample': '{"note":"synthetic"}',
      });
      await probe.replaceResearchPreferences({
        'bookfin.sample': '{"note":"synthetic"}',
      });
      final result = await probe.researchPreferences();
      expect(result['ShowSidebar'], true);
      expect(result['CustomPrefs'], {
        'skipForwardLength': '15000',
        'bookfin.sample': '{"note":"synthetic"}',
      });
      expect(preferences.length, 1);
      expect(preferences.keys.single, contains('client=BookfinResearch-'));
      expect(
        preferences.keys.single,
        startsWith('/DisplayPreferences/bookfin-research-'),
      );
    },
  );

  test('removing a research key does not remove server defaults', () async {
    await probe.replaceResearchPreferences({'bookfin.sample': 'synthetic'});
    await probe.replaceResearchPreferences({});
    final result = await probe.researchPreferences();
    expect(result['CustomPrefs'], {'skipForwardLength': '15000'});
  });

  test(
    'separate probe instances cannot overwrite each others namespace',
    () async {
      final other = JellyfinProbe(
        probe.server,
        token: 'fixture-token',
        allowWrites: true,
      );
      addTearDown(other.close);
      await probe.replaceResearchPreferences({'bookfin.sample': 'first'});
      await other.replaceResearchPreferences({'bookfin.sample': 'second'});
      expect(
        (await probe.researchPreferences())['CustomPrefs']['bookfin.sample'],
        'first',
      );
      expect(
        (await other.researchPreferences())['CustomPrefs']['bookfin.sample'],
        'second',
      );
    },
  );

  test('catalog output excludes private titles paths identifiers and arbitrary fields', () {
    expect(
      summarizeCatalog({
        'TotalRecordCount': 3,
        'Items': [
          {
            'Type': 'AudioBook',
            'Name': 'PRIVATE',
            'Id': 'PRIVATE',
            'Path': 'PRIVATE',
            'Chapters': [
              {'StartPositionTicks': 0},
            ],
            'ProviderIds': {'isbn': 'PRIVATE'},
          },
          {'Type': 'Book', 'Name': 'PRIVATE'},
          {'Type': 'AudioBook', 'Name': 'PRIVATE'},
        ],
      }),
      {
        'totalRecordCount': 3,
        'sampledItems': 3,
        'itemTypes': {'AudioBook': 2, 'Book': 1},
        'itemsWithChapters': 1,
        'itemsWithProviderIds': 1,
      },
    );
  });
}
