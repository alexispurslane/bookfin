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

  setUp(() async {
    requests = [];
    preferences = {};
    administrator = false;
    redirect = false;
    failWrites = false;
    fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixture.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (redirect) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/credential-collector');
      } else if (request.uri.path == '/Users/Me') {
        request.response.write(
          jsonEncode({
            'Policy': {'IsAdministrator': administrator},
          }),
        );
      } else if (request.uri.path == '/api-docs/openapi.json') {
        request.response.write('{"info":{"version":"fixture"},"paths":{}}');
      } else if (request.uri.path == '/UserViews') {
        request.response.write('{"Items":[]}');
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

  Future<ProcessResult> runAuthenticatedCommand() async {
    final directory = await Directory.systemTemp.createTemp(
      'bookfin-probe-token-',
    );
    final secret = File('${directory.path}/token');
    await secret.writeAsString('fixture-token');
    try {
      return await Process.run('dart', [
        'run',
        'tool/research/jellyfin/probe.dart',
        probe.server.toString(),
        '--secret-file',
        secret.path,
        '--allow-disposable-write',
      ]);
    } finally {
      await directory.delete(recursive: true);
    }
  }

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
