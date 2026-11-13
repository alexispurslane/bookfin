import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' show LocalFiles;
import 'fixture.dart';
import 'phone.dart';

// Reading history: each jump in a book is a move from one reading place to
// another. Engine rule 3 counts a lost move as data loss, so each test names
// one way that a move could be lost and shows that it is kept.

/// A reading place in the EPUB edition `ebook` at the passage [quote].
Map<String, dynamic> _place(String quote) => {
  'edition': 'ebook',
  'source': 'file',
  'revision': 'revision',
  'anchor': jsonEncode({'cfi': '/6/4', 'quote': quote}),
};

/// A reading move [id] at [at] from [from] to [to], as JSON.
Map<String, dynamic> _move(
  String id, {
  String at = '2026-11-09T20:00:00.000Z',
  String from = 'Miss Brooke',
  String to = 'Dorothea',
}) => {
  'id': id,
  'at': at,
  'kind': 'search',
  'before': _place(from),
  'after': _place(to),
  'bookTitle': 'Middlemarch',
  'editionLabel': 'EPUB',
};

/// The change set of one reading action: the place [resumes] and the moves
/// [history], with null for a deleted move.
ReadingChanges _changes({
  List<Map<String, dynamic>> resumes = const [],
  Map<String, Map<String, dynamic>?> history = const {},
}) => ReadingChanges(
  const {'version': 1, 'fontSize': 20.0},
  resumes: resumes,
  history: history,
);

/// The ids of the reading moves of [snapshot], in its order.
List<String> _moves(Map<String, dynamic>? snapshot) => [
  for (final move in snapshot?['history'] as List? ?? const [])
    (move as Map)['id'] as String,
];

/// The quote of the saved place of [snapshot].
String? _resumeQuote(Map<String, dynamic>? snapshot) {
  final resumes = snapshot?['resumes'] as List? ?? const [];
  if (resumes.isEmpty) return null;
  final anchor = (resumes.single as Map)['anchor'] as String;
  return (jsonDecode(anchor) as Map)['quote'] as String;
}

/// A listening event as earlier releases saved it.
const _listeningEvent =
    '{"id":"event","at":"2026-11-09T21:40:00.000Z","kind":"seek",'
    '"before":{"edition":"edition","source":"source","revision":"revision","milliseconds":1000},'
    '"after":{"edition":"edition","source":"source","revision":"revision","milliseconds":61000},'
    '"bookTitle":"Middlemarch","editionLabel":"Recording"}';

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

  /// A reader session over the reading records of [phone], bound to the
  /// account. No book is open.
  Future<ReaderSession> readerOn(Phone phone) async {
    final downloads = LocalFiles();
    addTearDown(downloads.dispose);
    final reader = ReaderSession(
      downloads: downloads,
      store: phone.store.reading,
      load: (_) async => throw StateError('No book opens in these tests.'),
    );
    addTearDown(reader.dispose);
    await reader.bind(server.session, const []);
    return reader;
  }

  test(
    'a move saved with its place in one change set survives a restart',
    () async {
      final phone = await Phone.open('move-restart');

      await phone.store.reading.saveReading(
        account,
        _changes(resumes: [_place('Dorothea')], history: {'one': _move('one')}),
      );
      await phone.restart();

      final shown = await phone.store.reading.read(account);
      expect(_moves(shown), ['one']);
      expect((shown!['history'] as List).single, _move('one'));
      expect(_resumeQuote(shown), 'Dorothea');
      await phone.store.checkInvariants();
    },
  );

  test('a kill during that save keeps the old place without the move, never the new place alone', () async {
    final phone = await Phone.open('move-kill');
    await phone.store.reading.saveReading(
      account,
      _changes(resumes: [_place('Miss Brooke')]),
    );

    // The kill stops the write at the row of the move, after the place.
    await phone.killDuring(
      'record_versions',
      when: '''NEW.record = '["reading","history","one"]' ''',
      () => phone.store.reading.saveReading(
        account,
        _changes(resumes: [_place('Dorothea')], history: {'one': _move('one')}),
      ),
    );
    await phone.restart();

    final shown = await phone.store.reading.read(account);
    expect(_resumeQuote(shown), 'Miss Brooke');
    expect(_moves(shown), isEmpty);
  });

  test('a failed sync keeps the move on the phone, and the next sync uploads it once', () async {
    final phone = await Phone.open('move-offline');
    final connection = Connection(server)..offline = true;
    addTearDown(connection.close);
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'one': _move('one')}),
    );

    await expectLater(
      RecordTransport(phone.store).synchronize(server.session, connection),
      throwsA(isA<SocketException>()),
    );
    await phone.restart();
    expect(_moves(await phone.store.reading.read(account)), ['one']);
    connection.offline = false;
    await RecordTransport(phone.store).synchronize(server.session, connection);
    await RecordTransport(phone.store).synchronize(server.session, connection);

    final uploaded = [
      for (final object in server.objects.values)
        (jsonDecode(object['Payload'] as String) as Map)['record'],
    ];
    expect(uploaded, [
      jsonEncode(['reading', 'history', 'one']),
    ]);
  });

  test('two devices that record moves offline each show the moves of both after they sync, newest first', () async {
    final phone = await Phone.open('move-phone');
    final tablet = await Phone.open('move-tablet');
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'early': _move('early')}),
    );
    await tablet.store.reading.saveReading(
      account,
      _changes(
        history: {'late': _move('late', at: '2026-11-09T20:05:00.000Z')},
      ),
    );

    for (final device in [phone, tablet, phone]) {
      await RecordTransport(device.store)
          .synchronize(server.session, server.client);
    }

    for (final device in [phone, tablet]) {
      final reader = await readerOn(device);
      expect([for (final move in reader.history) move.id], ['late', 'early']);
    }
  });

  test('a move deleted on one device goes away on the other after sync, and other moves stay', () async {
    final phone = await Phone.open('delete-phone');
    final tablet = await Phone.open('delete-tablet');
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'one': _move('one'), 'two': _move('two')}),
    );
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);
    await RecordTransport(tablet.store)
        .synchronize(server.session, server.client);

    await tablet.store.reading.saveReading(
      account,
      _changes(history: {'one': null}),
    );
    await RecordTransport(tablet.store)
        .synchronize(server.session, server.client);
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);

    expect(_moves(await phone.store.reading.read(account)), ['two']);
    expect(await phone.store.conflicts(account), isEmpty);
  });

  test('a damaged record file keeps every move that still decodes', () async {
    final phone = await Phone.open('move-salvage');
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'one': _move('one')}),
    );
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'two': _move('two')}),
    );
    final sql = await phone.separateConnection();
    await sql.rawUpdate(
      "UPDATE record_actions SET payload = '{broken' WHERE rowid = (SELECT MAX(rowid) FROM record_actions)",
    );

    await phone.restart();

    expect(_moves(await phone.store.reading.read(account)), ['one']);
    expect(phone.store.setAside(account), isTrue);
    await phone.store.checkInvariants();
  });

  test('moves that an earlier version kept aside come back at the next launch', () async {
    final phone = await Phone.open('move-kept');
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'one': _move('one'), 'two': _move('two')}),
    );
    // An earlier version that could not read reading history kept the rows
    // of the account aside and started the account again.
    final sql = await phone.separateConnection();
    for (final MapEntry(key: table, value: columns) in const {
      'record_accounts': 'account, replica, cursor, metadata',
      'record_actions': 'account, identity, payload, pending',
      'record_versions': 'account, record, identities',
      'record_coverage': 'account, replica, sequence',
    }.entries) {
      await sql.rawInsert(
        'INSERT INTO set_aside_$table SELECT 1, $columns FROM $table WHERE account = ?',
        [account],
      );
      await sql.delete(table, where: 'account = ?', whereArgs: [account]);
    }
    await phone.restart();
    await phone.store.reading.saveReading(
      account,
      _changes(resumes: [_place('Dorothea')]),
    );
    await phone.restart();

    await phone.store.recoverKept();

    final shown = await phone.store.reading.read(account);
    expect(_moves(shown), unorderedEquals(['one', 'two']));
    expect(_resumeQuote(shown), 'Dorothea');
  });

  test('a move that a newer build synced shows after a restart, without a new sync', () async {
    final phone = await Phone.open('move-known');
    final tablet = await Phone.open('move-sender');
    await tablet.store.reading.saveReading(
      account,
      _changes(history: {'one': _move('one')}),
    );
    await RecordTransport(tablet.store)
        .synchronize(server.session, server.client);
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);

    await phone.restart();

    expect(_moves(await phone.store.reading.read(account)), ['one']);
  });

  test(
    'listening records keep their bytes through a save of reading history',
    () async {
      final phone = await Phone.open('audio-bytes');
      await phone.store.save(
        account,
        ListeningChanges(
          const {'version': 3},
          history: {
            'event': jsonDecode(_listeningEvent) as Map<String, dynamic>,
          },
        ),
      );
      Future<List<String>> listeningActions() async => [
        for (final action
            in (await phone.database.load(account))!['sync']['actions'] as List)
          if ((jsonDecode(action['record'] as String) as List)[0] == 'audio')
            jsonEncode(action),
      ];
      final before = await listeningActions();

      await phone.store.reading.saveReading(
        account,
        _changes(history: {'one': _move('one')}),
      );
      await phone.restart();

      expect(await listeningActions(), before);
      final event = jsonDecode(before.single)['value'];
      expect(jsonEncode(event), _listeningEvent);
    },
  );

  test('the reader reads the moves of the account at bind and after a sync brings new ones', () async {
    final phone = await Phone.open('reader-phone');
    final tablet = await Phone.open('reader-tablet');
    await phone.store.reading.saveReading(
      account,
      _changes(history: {'early': _move('early')}),
    );
    final reader = await readerOn(phone);
    expect([for (final move in reader.history) move.id], ['early']);
    expect(reader.history.single.after.anchor, _place('Dorothea')['anchor']);

    await tablet.store.reading.saveReading(
      account,
      _changes(
        history: {'late': _move('late', at: '2026-11-09T20:05:00.000Z')},
      ),
    );
    await RecordTransport(tablet.store)
        .synchronize(server.session, server.client);
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);
    var notified = 0;
    reader.historyChanges.addListener(() => notified++);
    await reader.refreshPersonalRecords();

    expect([for (final move in reader.history) move.id], ['late', 'early']);
    expect(notified, 1);
  });

  test('a choice between two versions of a move names it a reading history entry with the quote of its place', () {
    final record = jsonEncode(['reading', 'history', 'one']);
    Map<String, dynamic> version(String replica, String device, String to) => {
      'replica': replica,
      'sequence': 1,
      'record': record,
      'device': device,
      'value': _move('one', to: to),
    };

    final labels = labelConflict(
      record,
      [
        version('phone', 'Pixel 8', 'Dorothea'),
        version('tablet', 'Pixel Tablet', 'Casaubon'),
      ],
      books: const <Book>[],
      now: DateTime.utc(2026, 11, 9, 22),
      clock: (at) => '${at.hour}:${at.minute}',
    );

    expect(labels.kind, 'Reading history entry');
    expect(labels.choices.map((choice) => choice.text), [
      'Pixel 8 · “Dorothea”',
      'Pixel Tablet · “Casaubon”',
    ]);
  });

  group('a reading change set', () {
    test(
      'keeps the moves of an earlier set that a later set does not name',
      () {
        final merged = _changes(
          history: {'one': _move('one'), 'two': _move('two')},
        ).followedBy(_changes(history: {'two': null, 'three': _move('three')}));

        expect(merged.history, {
          'one': _move('one'),
          'two': null,
          'three': _move('three'),
        });
      },
    );

    test('shows its moves in the snapshot that it applies to', () {
      final snapshot = _changes(history: {'one': null, 'three': _move('three')})
          .applyTo({
            'version': 1,
            'resumes': <dynamic>[],
            'bookmarks': <dynamic>[],
            'history': [_move('one'), _move('two')],
          });

      expect(_moves(snapshot), ['two', 'three']);
    });
  });
}
