import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixture.dart';
import 'phone.dart';

// A newer build can save a kind of personal record that this build does not
// know yet. These tests show that this build keeps such a record, syncs past
// it, and shows nothing of it.

/// Another installation, [replica], that uploads its actions to [server] as
/// a newer build writes them.
class _NewerBuild {
  _NewerBuild(this.server, this.replica);
  final SyncFixture server;
  final String replica;
  var _sequence = 0;

  /// Uploads an action that sets the record at [address] to [value].
  Map<String, dynamic> upload(
    List<String> address,
    Map<String, dynamic> value,
  ) {
    final sequence = ++_sequence;
    final action = <String, dynamic>{
      'version': 1,
      'account': server.session.scope.key,
      'replica': replica,
      'sequence': sequence,
      'context': {if (sequence > 1) replica: sequence - 1},
      'record': jsonEncode(address),
      'value': value,
      'preserve': <String>[],
    };
    final identity = RecordJournal.identity(action);
    server.objects[identity] = {
      'Id': identity,
      'Sequence': server.objects.length + 1,
      'Payload': jsonEncode(action),
      'Deleted': false,
    };
    return action;
  }
}

/// A place in the audio edition `edition` at [milliseconds], as JSON.
Map<String, dynamic> _audioPlace(int milliseconds) => {
  'edition': 'edition',
  'source': 'source',
  'revision': 'revision',
  'milliseconds': milliseconds,
};

/// A listening bookmark [id], as JSON.
Map<String, dynamic> _bookmark(String id) => {
  'id': id,
  'position': _audioPlace(15000),
  'createdAt': '2026-11-07T12:00:00.000Z',
  'title': 'Mark',
  'bookTitle': 'Book',
  'editionLabel': 'Recording',
  'note': null,
};

/// A listening event [id] of the move [kind], as JSON.
Map<String, dynamic> _event(String id, String kind) => {
  'id': id,
  'at': '2026-11-09T21:40:00.000Z',
  'kind': kind,
  'before': _audioPlace(1000),
  'after': _audioPlace(61000),
  'bookTitle': 'Book',
  'editionLabel': 'Recording',
};

/// The address of a kind of record that no build knows yet.
const _highlight = ['reading', 'highlights', 'highlight'];

/// A value of [_highlight], as a newer build would save it.
const _highlightValue = {'id': 'highlight', 'quote': 'It was a dark night.'};

List<String> _ids(Map<String, dynamic>? snapshot, String collection) => [
  for (final value in snapshot?[collection] as List? ?? const [])
    (value as Map)['id'] as String,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SyncFixture server;
  late String account;
  setUp(() async {
    server = await SyncFixture.open();
    addTearDown(server.close);
    account = server.session.scope.key;
  });

  group('a record of a kind that this build does not know', () {
    test('is kept by sync, and the records after it still arrive', () async {
      final phone = await Phone.open('unknown-kept');
      final newer = _NewerBuild(server, 'newer')
        ..upload(_highlight, _highlightValue)
        ..upload(['audio', 'bookmarks', 'mark'], _bookmark('mark'));

      await phone.store.synchronize(server.session, server.client);

      expect(_ids(await phone.store.read(account), 'bookmarks'), ['mark']);
      expect(
        await phone.savedRecords(account),
        contains(jsonEncode(_highlight)),
      );
      expect(newer.server.objects, hasLength(2));
      await phone.store.checkInvariants();
    });

    test(
      'shows no change in either view and leaves both writers current',
      () async {
        final phone = await Phone.open('unknown-hidden');
        _NewerBuild(
          server,
          'newer',
        ).upload(['audio', 'bookmarks', 'mark'], _bookmark('mark'));
        await phone.store.synchronize(server.session, server.client);
        final listening = await phone.store.read(account);
        final reading = await phone.store.reading.read(account);
        phone.store.acceptSnapshot(account, listening);
        phone.store.reading.acceptSnapshot(account, reading);
        _NewerBuild(server, 'later').upload(_highlight, _highlightValue);

        final report = await phone.store.synchronize(
          server.session,
          server.client,
        );

        expect(report.stale, (listening: false, reading: false));
        expect(_ids(listening, 'bookmarks'), ['mark']);
        expect(await phone.store.read(account), listening);
        expect(await phone.store.reading.read(account), reading);
      },
    );

    test(
      'stays through a restart and through whole saves of both domains',
      () async {
        final phone = await Phone.open('unknown-saved');
        _NewerBuild(server, 'newer').upload(_highlight, _highlightValue);
        await phone.store.synchronize(server.session, server.client);

        final listening = (await phone.store.read(account))!;
        phone.store.acceptSnapshot(account, listening);
        await phone.store.write(account, listening);
        final reading = (await phone.store.reading.read(account))!;
        phone.store.reading.acceptSnapshot(account, reading);
        await phone.store.reading.write(account, reading);
        await phone.restart();

        expect(
          await phone.savedRecords(account),
          contains(jsonEncode(_highlight)),
        );
        await phone.store.checkInvariants();
      },
    );

    test(
      'is not offered as a choice when two of its versions compete',
      () async {
        final phone = await Phone.open('unknown-choice');
        _NewerBuild(server, 'first').upload(_highlight, _highlightValue);
        _NewerBuild(server, 'second').upload(_highlight, {
          ..._highlightValue,
          'quote': 'It was a bright morning.',
        });

        await phone.store.synchronize(server.session, server.client);

        expect(await phone.store.conflicts(account), isEmpty);
      },
    );

    test(
      'a kill during its save keeps all of that save or none of it',
      () async {
        final phone = await Phone.open('unknown-kill');
        _NewerBuild(server, 'newer')
          ..upload(_highlight, _highlightValue)
          ..upload(['audio', 'bookmarks', 'mark'], _bookmark('mark'));
        await phone.killDuring(
          'record_versions',
          () => phone.store.synchronize(server.session, server.client),
        );

        await phone.restart();
        expect(await phone.database.load(account), isNull);
        await phone.store.synchronize(server.session, server.client);
        expect(
          await phone.savedRecords(account),
          contains(jsonEncode(_highlight)),
        );
        expect(_ids(await phone.store.read(account), 'bookmarks'), ['mark']);
      },
    );
  });

  group('a listening event', () {
    test('of a kind that this build does not know is kept and not shown, and the rest of the history shows', () async {
      final phone = await Phone.open('unknown-kind');
      _NewerBuild(server, 'newer')
        ..upload(['audio', 'history', 'later'], _event('later', 'rewind'))
        ..upload(['audio', 'history', 'known'], _event('known', 'seek'));

      await phone.store.synchronize(server.session, server.client);

      expect(_ids(await phone.store.read(account), 'history'), ['known']);
      expect(
        await phone.savedRecords(account),
        contains(jsonEncode(['audio', 'history', 'later'])),
      );
    });

    test(
      'of a known kind that does not decode still counts as damage',
      () async {
        final phone = await Phone.open('malformed-event');
        _NewerBuild(server, 'newer').upload([
          'audio',
          'history',
          'broken',
        ], {..._event('broken', 'seek')}..remove('before'));

        await expectLater(
          phone.store.synchronize(server.session, server.client),
          throwsFormatException,
        );
        expect(_ids(await phone.store.read(account), 'history'), isEmpty);
      },
    );
  });
}
