import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'phone.dart';

/// Counts real HTTP requests; all bytes still cross the production transport.
class MeasuredTransport implements JsonTransport {
  final delegate = createTransport();
  int uploads = 0;
  int discovery = 0;
  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    if (method == 'PUT') {
      expect(uri.path, '/BookfinStorage/v2/objects');
      uploads++;
    }
    if (uri.path.endsWith('/objects') && method == 'GET') discovery++;
    return delegate.send(uri, method: method, headers: headers, body: body);
  }

  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) => delegate.fetchBody(uri, method: method, headers: headers, body: body);
  @override
  void close() => delegate.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  final fixture = Platform.environment['BOOKFIN_PRODUCTION_SYNC_FIXTURE'];
  test(
    'the actual plugin transfers thousands of immutable actions between durable ordinary-account clients',
    () async {
      SharedPreferences.setMockInitialValues({});
      final config = jsonDecode(
        await File(fixture!).readAsString(),
      ) as Map<String, dynamic>;
      final session = JellyfinSession.fromJson(config);
      final account = session.scope.key;
      final http = MeasuredTransport();
      final client = JellyfinClient(
        session.scope.server,
        deviceId: 'batch-proof',
        transport: http,
      );
      addTearDown(client.close);
      final sender = await Phone.open('plugin-batch-sender');
      final receiver = await Phone.open('plugin-batch-receiver');
      final journal = RecordJournal(account, 'batch-proof');
      for (var i = 1; i <= 2400; i++) {
        journal.change(
          jsonEncode([
            'audio',
            'resumes',
            jsonEncode(['book', 'audio', 'v1']),
          ]),
          {
            'edition': 'book',
            'source': 'audio',
            'revision': 'v1',
            'milliseconds': i,
          },
        );
      }
      final original = journal.uploads;
      await sender.database.write(
        account,
        jsonEncode({'version': 3, 'sync': journal.encode()}),
      );
      await sender.store.read(account);
      final sql = await sender.separateConnection();
      await sql.execute('CREATE TABLE commits (cursor INTEGER)');
      await sql.execute(
        'CREATE TRIGGER count_commit AFTER UPDATE ON record_accounts BEGIN INSERT INTO commits VALUES (NEW.cursor); END',
      );
      final clock = Stopwatch()..start();
      await RecordTransport(sender.store).synchronize(session, client);
      final uploadMilliseconds = clock.elapsedMilliseconds;
      final commits = (await sql.query('commits', where: 'cursor = 0')).length;
      expect(http.uploads, 10);
      expect(commits, 10);
      expect(await sender.store.pendingUploads(account), isEmpty);
      final before = http.discovery;
      clock.reset();
      await RecordTransport(receiver.store).synchronize(session, client);
      final receiveMilliseconds = clock.elapsedMilliseconds;
      expect(http.discovery - before, 11);
      await sender.restart();
      await receiver.restart();
      for (final phone in [sender, receiver]) {
        final saved = (await phone.database.load(account))!['sync'] as Map;
        expect(saved['actions'], original);
        expect(saved['pending'], isEmpty);
        expect(saved['cursor'], 2400);
        expect(
          (await phone.store.read(
            account,
          ))!['resumes']['book'].single['milliseconds'],
          2400,
        );
        await phone.store.checkInvariants();
      }
      final evidence = {
        'actions': 2400,
        'uploadRequests': http.uploads,
        'acknowledgmentTransactions': commits,
        'receiverDiscoveryRequests': http.discovery - before,
        'uploadHostMilliseconds': uploadMilliseconds,
        'receiveHostMilliseconds': receiveMilliseconds,
        'retainedActionsAfterBothClientRestarts': 2400,
        'lostActions': 0,
        'scope':
            'Jellyfin 12.4.0 loopback on macOS ARM64; no Android timing claim',
      };
      await File('${File(fixture).parent.path}/batch-workload.json')
          .writeAsString(jsonEncode(evidence));
      // ignore: avoid_print
      print('ACTUAL_PLUGIN_BATCH ${jsonEncode(evidence)}');
    },
    skip: fixture == null
        ? 'Run with tool/plugin/prove.py in the pinned sync dev shell.'
        : false,
  );
}
