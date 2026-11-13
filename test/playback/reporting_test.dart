import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/playback/reporting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart' show first, second;

void main() {
  late HttpServer server;
  late MediaPolicy policy;
  late LiveReports reports;
  late JellyfinSession session;
  var rejectReports = false;
  Completer<void>? responseGate;
  Completer<void>? started;
  final requests = <Map<String, dynamic>>[];
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    requests.clear();
    rejectReports = false;
    responseGate = null;
    started = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      requests.add({
        'path': request.uri.path,
        'body': payload,
        'token': request.headers.value('X-Emby-Token'),
      });
      if (started?.isCompleted == false) started!.complete();
      await responseGate?.future;
      request.response.statusCode = rejectReports ? 503 : 204;
      await request.response.close();
    });
    session = JellyfinSession(
      scope: AccountScope(
        server: Uri.parse('http://127.0.0.1:${server.port}/jellyfin'),
        serverId: 'fixture',
        userId: 'alice',
      ),
      token: 'disposable',
      username: 'alice',
      canDownload: true,
    );
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    reports = LiveReports(policy);
  });
  tearDown(() async {
    reports.close();
    policy.dispose();
    await server.close(force: true);
    HttpOverrides.global = null;
  });

  test(
    'credential rejection stops live reports while local playback can continue',
    () async {
      reports.observe(session, first, 1000, playing: true, speed: 1);
      await reports.idle;
      session.rejectCredential();
      reports.observe(session, first, 12000, playing: true, speed: 1);
      reports.stop();
      policy.network = MediaNetwork.mobile;
      reports.observe(session, first, 23000, playing: true, speed: 1);
      await reports.idle;
      expect(requests, hasLength(1));
      final replacement = JellyfinSession.fromJson({
        ...session.toJson(),
        'needsSignIn': false,
      });
      reports.observe(replacement, first, 23000, playing: true, speed: 1);
      await reports.idle;
      expect(requests, hasLength(2));
      expect(requests.last['body']['PositionTicks'], 230000000);
    },
  );

  for (final retire in [false, true]) {
    test(
      'queued reports are discarded after ${retire ? 'retirement' : 'failure'}',
      () async {
        responseGate = Completer<void>();
        started = Completer<void>();
        reports.observe(session, first, 0, playing: true, speed: 1);
        await started!.future;
        reports.observe(session, first, 10000, playing: true, speed: 1);
        reports.observe(session, first, 20000, playing: true, speed: 1);
        if (retire) {
          reports.stop();
        } else {
          rejectReports = true;
        }
        responseGate!.complete();
        await reports.idle;
        expect(
          requests.where((r) => (r['path'] as String).endsWith('/Progress')),
          isEmpty,
        );
        expect(requests.length, retire ? 2 : 1);
      },
    );
  }

  test(
    'account change retires queued progress but keeps final stop and new start',
    () async {
      responseGate = Completer<void>();
      started = Completer<void>();
      reports.observe(session, first, 0, playing: true, speed: 1);
      await started!.future;
      reports.observe(session, first, 10000, playing: true, speed: 1);
      final other = JellyfinSession(
        scope: AccountScope(
          server: session.scope.server,
          serverId: 'fixture',
          userId: 'bob',
        ),
        token: 'bob-token',
        username: 'bob',
        canDownload: true,
      );
      reports.observe(other, second, 2000, playing: true, speed: 1);
      responseGate!.complete();
      await reports.idle;
      expect(requests.map((r) => r['path']), [
        '/jellyfin/Sessions/Playing',
        '/jellyfin/Sessions/Playing/Stopped',
        '/jellyfin/Sessions/Playing',
      ]);
      expect(requests.map((r) => r['token']), [
        'disposable',
        'disposable',
        'bob-token',
      ]);
    },
  );

  test(
    'reports actual file and media source with source-relative Jellyfin ticks',
    () async {
      reports.observe(session, first, 41000, playing: true, speed: 1.5);
      await reports.idle;
      reports.observe(session, first, 52000, playing: true, speed: 1.5);
      await reports.idle;
      reports.observe(session, second, 3000, playing: true, speed: 1.5);
      await reports.idle;
      reports.stop();
      await reports.idle;
      expect(requests.map((request) => request['path']), [
        '/jellyfin/Sessions/Playing',
        '/jellyfin/Sessions/Playing/Progress',
        '/jellyfin/Sessions/Playing/Stopped',
        '/jellyfin/Sessions/Playing',
        '/jellyfin/Sessions/Playing/Stopped',
      ]);
      final start = requests.first['body'] as Map;
      expect(start['ItemId'], 'one');
      expect(start['MediaSourceId'], 'm1');
      expect(start['PositionTicks'], 410000000);
      expect(requests[2]['body']['PositionTicks'], 520000000);
      expect(requests[3]['body']['ItemId'], 'two');
      expect(requests[3]['body']['MediaSourceId'], 'm2');
      expect(requests[3]['body']['PositionTicks'], 30000000);
      expect(
        requests.every((request) => request['token'] == 'disposable'),
        isTrue,
      );
    },
  );
  test(
    'offline progress is never replayed when the live reporter restarts',
    () async {
      policy.network = MediaNetwork.disconnected;
      reports.observe(session, first, 5000, playing: true, speed: 1);
      reports.stop();
      await reports.idle;
      reports.close();
      reports = LiveReports(policy);
      policy.network = MediaNetwork.wifi;
      reports.observe(session, first, 12000, playing: false, speed: 1);
      await reports.idle;
      expect(requests, isEmpty);
      reports.observe(session, second, 7000, playing: true, speed: 1);
      await reports.idle;
      expect(requests, hasLength(1));
      expect(requests.single['body']['ItemId'], 'two');
      expect(requests.single['body']['PositionTicks'], 70000000);
    },
  );
  test(
    'network loss discards the old live session rather than backfilling it',
    () async {
      reports.observe(session, first, 5000, playing: true, speed: 1);
      await reports.idle;
      final oldId = requests.single['body']['PlaySessionId'];
      policy.network = MediaNetwork.disconnected;
      reports.observe(session, first, 25000, playing: true, speed: 1);
      policy.network = MediaNetwork.wifi;
      reports.observe(session, first, 35000, playing: true, speed: 1);
      await reports.idle;
      expect(requests.map((request) => request['path']), [
        '/jellyfin/Sessions/Playing',
        '/jellyfin/Sessions/Playing',
      ]);
      expect(requests.last['body']['PlaySessionId'], isNot(oldId));
      expect(requests.last['body']['PositionTicks'], 350000000);
    },
  );
  test('pause and completion report the last position without inventing listening time', () async {
    reports.observe(session, second, 4000, playing: true, speed: 2);
    await reports.idle;
    reports.observe(session, second, 6000, playing: false, speed: 2);
    await reports.idle;
    reports.observe(
      session,
      second,
      90000,
      playing: false,
      speed: 2,
      completed: true,
    );
    await reports.idle;
    expect(requests.map((request) => request['path']), [
      '/jellyfin/Sessions/Playing',
      '/jellyfin/Sessions/Playing/Progress',
      '/jellyfin/Sessions/Playing/Stopped',
    ]);
    expect(requests[1]['body']['IsPaused'], isTrue);
    expect(requests.last['body']['PositionTicks'], 900000000);
  });
  test('small live progress reports use mobile data without authorizing remote media', () async {
    policy.network = MediaNetwork.mobile;
    reports.observe(session, first, 7000, playing: true, speed: 1);
    await reports.idle;
    expect(requests, hasLength(1));
    expect(policy.choose(verifiedLocal: false), MediaLocation.blocked);
  });
  test('an unavailable server cannot turn audio position samples into a request flood', () async {
    rejectReports = true;
    reports.observe(session, first, 5000, playing: true, speed: 1);
    await reports.idle;
    reports.observe(session, first, 5200, playing: true, speed: 1);
    await reports.idle;
    reports.observe(session, first, 5400, playing: true, speed: 1);
    await reports.idle;
    expect(requests, hasLength(1));
    rejectReports = false;
    responseGate = null;
    started = null;
    policy.network = MediaNetwork.disconnected;
    policy.network = MediaNetwork.wifi;
    reports.observe(session, second, 9000, playing: true, speed: 1);
    await reports.idle;
    expect(requests, hasLength(2));
    expect(requests.last['body']['ItemId'], 'two');
  });
}

class _RealHttp extends HttpOverrides {}
