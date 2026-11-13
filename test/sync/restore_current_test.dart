import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../research/journal_growth_measurement_test.dart' show seededState;
import '../playback/playback_test.dart' show recording, first;
import '../support/record_reads.dart';
import '../research/current_restore_measurement_test.dart' show versionThree;

Future<R> isolated<M, R>(FutureOr<R> Function(M) work, M input) =>
    Isolate.run(() => work(input));

/// A real SQLite factory with the unsendable lock that an overlapping close
/// can retain. No timing or sleep is needed to hold that condition open.
class ClosingFiles implements DatabaseFactory {
  final close = Completer<void>();

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      databaseFactoryFfi.openDatabase(path, options: options);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Disk {
  Disk(this.path, this.database);
  final String path;
  RecordDatabase database;
  late LocalResumeStore store = LocalResumeStore(
    openDatabase: () async => database,
  );
  static Future<Disk> open() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-lazy-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final disk = Disk(
      path,
      await RecordDatabase.open(factory: databaseFactoryFfi, path: path),
    );
    addTearDown(() => disk.database.close());
    return disk;
  }

  Future<void> restart() async {
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    store = LocalResumeStore(openDatabase: () async => database);
  }

  Future<Database> get sql => databaseFactoryFfi.openDatabase(path);
  Future<void> seed(RecordJournal journal) async {
    await database.commit(
      journal.account,
      {
        'version': 3,
        'reading': {'version': 1},
      },
      journal,
      initialize: true,
    );
    await restart();
  }
}

Future<List<int>> damageActions(Disk disk, {String? index}) async {
  final sql = await disk.sql;
  await sql.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  await sql.execute('PRAGMA cache_size = 0');
  await sql.execute('PRAGMA shrink_memory');
  final roots = await sql.rawQuery(
    'SELECT rootpage FROM sqlite_master WHERE ${index == null ? 'tbl_name' : 'name'} = ?',
    [index ?? 'record_actions'],
  );
  final file = File(disk.path);
  final bytes = await file.readAsBytes();
  final original = List<int>.of(bytes);
  for (final row in roots) {
    final root = row['rootpage'] as int;
    bytes.fillRange((root - 1) * 4096, root * 4096, 0xff);
  }
  await file.writeAsBytes(bytes, flush: true);
  return original;
}

Map<String, dynamic> place(int milliseconds) => {
  'edition': recording.id,
  'source': first.key,
  'revision': first.revision,
  'sources': editionSources(recording),
  'milliseconds': milliseconds,
  'pendingOffline': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('a remote replacement keeps the last local place and the next local identity after reopen', () async {
    final disk = await Disk.open();
    final record = resumeRecordAddress(recording);
    final local = RecordJournal('alice', 'local')
      ..change(record, place(1000))
      ..change(record, place(2000));
    final remote = RecordJournal('alice', 'remote')..receive(local.uploads);
    remote.change(record, place(9000));
    local.receive(remote.uploads);
    await disk.seed(local);
    final origin = await disk.store.origin('alice', recording);
    expect((origin.own as AudioPosition).milliseconds, 2000);
    expect(origin.elsewhere, isTrue);
    final seen = await disk.store.read('alice');
    disk.store.acceptSnapshot('alice', seen);
    await disk.store.save(
      'alice',
      ListeningChanges(
        {'version': 3},
        resumes: {
          recording.id: [place(3000)],
        },
      ),
    );
    await disk.restart();
    final uploads = await disk.store.pendingUploads('alice');
    final next = uploads.singleWhere(
      (action) => RecordJournal.identity(action) == 'action.local.3',
    );
    expect(next['context'], {'local': 2, 'remote': 1});
    expect(next['value']['milliseconds'], 3000);
    await disk.store.receivePage('alice', [
      local.retained('action.local.1')!,
    ], 10);
    await expectLater(
      disk.store.receivePage('alice', [
        {...local.retained('action.local.1')!, 'value': place(7000)},
      ], 11),
      throwsFormatException,
    );
    await disk.restart();
    expect(await disk.store.discoveryCursor('alice'), 10);
    expect(
      (await disk.store.origin('alice', recording)).own,
      isA<AudioPosition>().having((p) => p.milliseconds, 'milliseconds', 3000),
    );
    await disk.store.checkInvariants();
  });

  test('a held conflict validates its historical preserved version when a late predecessor arrives', () async {
    final disk = await Disk.open();
    final record = resumeRecordAddress(recording);
    final local = RecordJournal('alice', 'local')..change(record, place(1000));
    final original = local.uploads.single;
    local.change(record, place(2000));
    final held = <String, dynamic>{
      'version': 1,
      'account': 'alice',
      'replica': 'remote',
      'sequence': 2,
      'context': {'remote': 1, 'local': 2},
      'record': record,
      'value': place(9000),
      'preserve': ['action.local.1'],
    };
    local.receive([held]);
    await disk.seed(local);
    final predecessor = {
      ...held,
      'sequence': 1,
      'context': <String, int>{},
      'preserve': <String>[],
      'value': place(8000),
    };
    await disk.store.receivePage('alice', [predecessor], 2);
    local.receive([predecessor]);
    await disk.restart();
    expect((await disk.database.load('alice'))!['current'], local.current);
    expect(
      (await disk.database.rows('alice'))!.identities,
      contains(RecordJournal.identity(original)),
    );
    await disk.store.checkInvariants();
  });

  test('a needed corrupt pending payload fails without overwriting its recoverable bytes', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000))
      ..change(resumeRecordAddress(recording), place(2000));
    await disk.seed(journal);
    await (await disk.sql).rawUpdate(
      "UPDATE record_actions SET payload = '{broken' WHERE identity = 'action.local.1'",
    );
    final before = (await disk.database.rows('alice'))!;
    expect(await disk.store.read('alice'), isNotNull);
    await expectLater(
      disk.store.pendingUploads('alice'),
      throwsFormatException,
    );
    expect((await disk.database.rows('alice'))!.payloads, before.payloads);
    expect((await disk.database.rows('alice'))!.pending, before.pending);
    await expectLater(disk.store.checkInvariants(), throwsA(anything));
  });

  test('a covered duplicate whose retained original is unavailable is not silently reinserted', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000))
      ..change(resumeRecordAddress(recording), place(2000));
    await disk.seed(journal);
    await (await disk.sql).rawDelete(
      "DELETE FROM record_actions WHERE identity = 'action.local.1'",
    );
    await expectLater(
      disk.store.receivePage('alice', [journal.retained('action.local.1')!], 7),
      throwsFormatException,
    );
    expect(await disk.store.discoveryCursor('alice'), 0);
    expect((await disk.database.rows('alice'))!.identities, ['action.local.2']);
  });

  test('a missing current record is recovered from retained actions and the damaged rows stay aside', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000));
    await disk.seed(journal);
    await (await disk.sql).delete('record_versions');
    final snapshot = await disk.store.read('alice');
    expect(snapshot!['resumes'], contains(recording.id));
    expect(snapshot['resumes'][recording.id].single['milliseconds'], 1000);
    expect(disk.store.setAside('alice'), isTrue);
    expect(
      await (await disk.sql).query('set_aside_record_actions'),
      hasLength(1),
    );
    await disk.store.checkInvariants();
  });

  test('a restoration contract failure is reported and never retried as a successful read', () async {
    final disk = await Disk.open();
    await disk.seed(
      RecordJournal('alice', 'local')
        ..change(resumeRecordAddress(recording), place(1000)),
    );
    var calls = 0;
    Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
      if (++calls == 1) throw AssertionError('restore contract');
      return work(input);
    }

    final store = LocalResumeStore(
      openDatabase: () async => disk.database,
      hop: hop,
    );
    await expectLater(store.read('alice'), throwsA(isA<AssertionError>()));
    expect(calls, 1);
  });

  test('an unsendable database connection still restores and reads needed originals', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000))
      ..change(resumeRecordAddress(recording), place(2000));
    await disk.seed(journal);
    await disk.database.close();
    disk.database = await RecordDatabase.open(
      factory: ClosingFiles(),
      path: disk.path,
    );
    disk.store = LocalResumeStore(openDatabase: () async => disk.database);
    expect(
      (await disk.store.read(
        'alice',
      ))!['resumes'][recording.id].single['milliseconds'],
      2000,
    );
    expect(await disk.store.pendingUploads('alice'), journal.uploads);
    expect(
      (await disk.store.origin('alice', recording)).own,
      isA<AudioPosition>().having((p) => p.milliseconds, 'milliseconds', 2000),
    );
    expect(
      await disk.store.takeServerCopies('alice', [
        {...journal.uploads.first, 'value': place(1500)},
      ]),
      1,
    );
    await disk.restart();
    await disk.store.checkInvariants();
  });

  for (final fallback in [false, true]) {
    test(
      'a mismatched last-local lookup fails without changing originals (${fallback ? 'owner connection' : 'reader worker'})',
      () async {
        final disk = await Disk.open();
        final local = RecordJournal('alice', 'local')
          ..change(resumeRecordAddress(recording), place(1000));
        final remote = RecordJournal('alice', 'remote')..receive(local.uploads);
        remote.change(resumeRecordAddress(recording), place(2000));
        local.receive(remote.uploads);
        await disk.seed(local);
        if (fallback) {
          await disk.database.close();
          disk.database = await RecordDatabase.open(
            factory: ClosingFiles(),
            path: disk.path,
          );
          disk.store = LocalResumeStore(
            openDatabase: () async => disk.database,
          );
        }
        await disk.store.read('alice');
        final originals = (await disk.database.rows('alice'))!.payloads;
        await (await disk.sql).rawUpdate(
          "UPDATE record_actions SET author = 'local', sequence = 2 WHERE identity = 'action.remote.1'",
        );
        await expectLater(
          disk.store.origin('alice', recording),
          throwsFormatException,
        );
        expect((await disk.database.rows('alice'))!.payloads, originals);
      },
    );
  }

  test('full verification detects a changed current payload even when its identity is unchanged', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000));
    await disk.seed(journal);
    await disk.store.read('alice');
    await (await disk.sql).update('record_actions', {
      'payload': jsonEncode({...journal.uploads.single, 'value': place(9000)}),
    });
    await expectLater(disk.store.checkInvariants(), throwsStateError);
  });

  for (final deletion in [true, false]) {
    test(
      'incomplete reconstruction preserves ${deletion ? 'a deletion barrier' : 'an unresolved resume'} through partial delivery and retry',
      () async {
        final disk = await Disk.open();
        final record = deletion
            ? jsonEncode(['audio', 'bookmarks', 'mark'])
            : resumeRecordAddress(recording);
        final local = RecordJournal('alice', 'local')
          ..change(
            record,
            deletion
                ? {
                    'id': 'mark',
                    'position': place(1000),
                    'createdAt': '1970-01-01T00:00:00Z',
                    'bookTitle': 'Book',
                    'editionLabel': 'Audio',
                    'title': 'Mark',
                  }
                : place(1000),
          );
        final first = local.uploads.single;
        for (var i = 2; i < 100; i++) {
          local.change(resumeRecordAddress(recording), place(i * 1000));
        }
        if (deletion) {
          local.change(record, null);
        } else {
          final remote = RecordJournal('alice', 'remote')
            ..change(record, place(9000));
          local.receive(remote.uploads);
        }
        await disk.seed(local);
        RecordJournal? resident;
        Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
          final result = await isolated(work, input);
          if (result case (:final restored, :final damaged)) {
            if (damaged == false && restored != null) {
              resident = (restored as dynamic).stored.journal as RecordJournal;
            }
          }
          return result;
        }

        disk.store = LocalResumeStore(
          openDatabase: () async => disk.database,
          hop: hop,
        );
        await disk.store.read('alice');
        final expected = resident!.current;
        final originalFile = await damageActions(disk);
        await expectLater(
          disk.store.pendingUploads('alice'),
          throwsA(anything),
        );
        expect(
          await disk.database.rows('alice'),
          isNull,
          reason: 'an incomplete replacement must not become committed state',
        );
        expect(resident!.current, expected);
        await expectLater(
          disk.store.receivePage('alice', [first], 1),
          throwsFormatException,
        );
        expect(resident!.current, expected);
        expect(await disk.database.rows('alice'), isNull);
        final kept = File(disk.database.keptFile!);
        expect(await kept.exists(), isTrue);
        // A repaired retained copy lets the same owner retry its entire rewrite.
        await kept.writeAsBytes(originalFile, flush: true);
        await disk.store.receivePage('alice', [first], 1);
        await disk.restart();
        final restored = (await disk.database.load('alice'))!;
        expect(restored['current'], expected);
        await disk.store.read('alice');
        await disk.store.checkInvariants();
      },
    );
  }

  test('reconstruction keeps an accepted server original ahead of its rejected archive', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local')
      ..change(resumeRecordAddress(recording), place(1000))
      ..change(resumeRecordAddress(recording), place(2000));
    await disk.seed(journal);
    final accepted = {...journal.uploads.first, 'value': place(1500)};
    expect(await disk.store.takeServerCopies('alice', [accepted]), 1);
    await disk.restart();
    await disk.store.read('alice');
    await damageActions(disk, index: 'record_action_own');
    await expectLater(disk.store.origin('alice', recording), throwsA(anything));
    expect(disk.database.keptFile, isNotNull);
    await disk.restart();
    final rows = (await disk.database.rows('alice'))!;
    expect(
      jsonDecode(rows.payloads[rows.identities.indexOf('action.local.1')]),
      accepted,
    );
    expect(
      (await disk.database.reader.kept()).rows.any(
        (copy) => copy.rows.payloads.any(
          (payload) => payload == jsonEncode(journal.uploads.first),
        ),
      ),
      isTrue,
    );
    await disk.store.read('alice');
    await disk.store.checkInvariants();
  });

  test('incomplete reconstruction keeps an unsaved place until its retained predecessors can be read', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local');
    for (var i = 1; i <= 100; i++) {
      journal.change(resumeRecordAddress(recording), place(i * 1000));
    }
    await disk.seed(journal);
    await disk.store.read('alice');
    final originalFile = await damageActions(disk);
    await expectLater(
      disk.store.save(
        'alice',
        ListeningChanges(
          {'version': 3},
          resumes: {
            recording.id: [place(101000)],
          },
        ),
      ),
      throwsFormatException,
    );
    expect(disk.store.setAside('alice'), isTrue);
    expect(await disk.database.rows('alice'), isNull);
    await File(disk.database.keptFile!).writeAsBytes(originalFile, flush: true);
    await disk.store.read('alice');
    await disk.restart();
    expect(
      (await disk.store.read(
        'alice',
      ))!['resumes'][recording.id].single['milliseconds'],
      101000,
    );
    final kept = await disk.database.reader.kept();
    expect(kept.kept, isTrue);
    expect((await disk.database.rows('alice'))!.identities, hasLength(101));
    await disk.store.checkInvariants();
  });

  test('a failed version-three upgrade leaves original rows intact and can be retried', () async {
    final disk = await Disk.open();
    final journal = RecordJournal('alice', 'local');
    for (var i = 1; i <= 40; i++) {
      journal.change(resumeRecordAddress(recording), place(i * 1000));
    }
    journal.cursor = 97;
    await disk.seed(journal);
    final originals = (await disk.database.rows('alice'))!;
    await disk.database.close();
    await versionThree(disk.path);
    var sql = await disk.sql;
    await sql.execute(
      "CREATE TRIGGER fail_upgrade BEFORE UPDATE ON record_actions BEGIN SELECT RAISE(ABORT, 'upgrade full disk'); END",
    );
    await sql.close();
    await expectLater(
      RecordDatabase.open(factory: databaseFactoryFfi, path: disk.path),
      throwsA(isA<DatabaseException>()),
    );
    sql = await disk.sql;
    expect((await sql.rawQuery('PRAGMA user_version')).single.values.single, 3);
    expect(
      (await sql.query(
        'record_actions',
        orderBy: 'rowid',
      )).map((row) => row['payload']),
      originals.payloads,
    );
    await sql.execute('DROP TRIGGER fail_upgrade');
    await sql.close();
    await disk.restart();
    expect(
      (await disk.store.read(
        'alice',
      ))!['resumes'][recording.id].single['milliseconds'],
      40000,
    );
    expect(await disk.store.discoveryCursor('alice'), 97);
    expect((await disk.store.pendingUploads('alice')).length, 40);
    expect((await disk.database.rows('alice'))!.payloads, originals.payloads);
    await disk.store.checkInvariants();
  });

  test(
    'a version-three upgrade preserves malformed historical bytes for salvage',
    () async {
      final disk = await Disk.open();
      await disk.seed(
        RecordJournal('alice', 'local')
          ..change(resumeRecordAddress(recording), place(1000))
          ..change(resumeRecordAddress(recording), place(2000)),
      );
      await disk.database.close();
      await versionThree(disk.path);
      final sql = await disk.sql;
      await sql.rawUpdate(
        "UPDATE record_actions SET payload = '{unreadable' WHERE identity = 'action.local.1'",
      );
      await sql.close();
      await disk.restart();
      await disk.store.read('alice');
      expect(disk.store.setAside('alice'), isTrue);
      expect(
        (await (await disk.sql).query(
          'set_aside_record_actions',
          where: "identity = 'action.local.1'",
        )).single['payload'],
        '{unreadable',
      );
      expect(
        (await disk.database.rows('alice'))!.identities,
        contains('action.local.2'),
      );
      await disk.store.checkInvariants();
    },
  );

  test('a local save releases a held action that preserves a superseded historical version', () async {
    final disk = await Disk.open();
    final record = resumeRecordAddress(recording);
    final other = RecordJournal('alice', 'other')..change(record, place(1000));
    other.change(record, place(2000));
    final local = RecordJournal('alice', 'local')..receive(other.uploads);
    local.receive([
      {
        'version': 1,
        'account': 'alice',
        'replica': 'held',
        'sequence': 1,
        'context': {'local': 1, 'other': 2},
        'record': record,
        'value': place(9000),
        'preserve': ['action.other.1'],
      },
    ]);
    await disk.seed(local);
    final snapshot = await disk.store.read('alice');
    disk.store.acceptSnapshot('alice', snapshot);
    await disk.store.save(
      'alice',
      ListeningChanges(
        {'version': 3},
        resumes: {
          recording.id: [place(3000)],
        },
      ),
    );
    local.change(record, place(3000));
    await disk.restart();
    expect((await disk.database.load('alice'))!['current'], local.current);
    expect((await disk.database.load('alice'))!['coverage'], {
      'other': 2,
      'local': 1,
      'held': 1,
    });
    await disk.store.checkInvariants();
  });

  test('full verification rejects lookup metadata that disagrees with its retained original', () async {
    final disk = await Disk.open();
    await disk.seed(
      RecordJournal('alice', 'local')
        ..change(resumeRecordAddress(recording), place(1000)),
    );
    await disk.store.read('alice');
    await (await disk.sql).rawUpdate(
      'UPDATE record_actions SET sequence = sequence + 1',
    );
    await expectLater(disk.store.checkInvariants(), throwsStateError);
  });

  for (final lookup in ['pending uploads', 'last local place']) {
    test(
      'damage found by $lookup keeps the file and the cached place recoverable',
      () async {
        final disk = await Disk.open();
        final journal = RecordJournal('alice', 'local');
        for (var i = 1; i <= 100; i++) {
          journal.change(resumeRecordAddress(recording), place(i * 1000));
        }
        await disk.seed(journal);
        await disk.store.read('alice');
        final originalFile = await damageActions(disk);
        await expectLater(
          lookup == 'pending uploads'
              ? disk.store.pendingUploads('alice')
              : disk.store.origin('alice', recording),
          throwsA(anything),
        );
        expect(disk.store.setAside('alice'), isTrue);
        expect(await disk.database.rows('alice'), isNull);
        await File(disk.database.keptFile!)
            .writeAsBytes(originalFile, flush: true);
        await disk.store.read('alice');
        await disk.restart();
        expect(
          (await disk.store.read(
            'alice',
          ))!['resumes'][recording.id].single['milliseconds'],
          100000,
        );
        expect((await disk.database.reader.kept()).kept, isTrue);
        await disk.store.checkInvariants();
      },
    );
  }

  test(
    'reopening many superseded positions reads and holds only needed payloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'bookfin-current-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.sqlite';
      var database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(() => database.close());
      final state = seededState(3600, allPending: false, account: 'alice');
      await database.write('alice', jsonEncode(state));
      final original = LocalResumeStore(openDatabase: () async => database);
      final expected = await original.read('alice');
      final expectedReading = await original.reading.read('alice');
      final before = (await database.rows('alice'))!;
      await database.close();

      final replies = ReceivePort();
      addTearDown(replies.close);
      final queries = <RecordQuery>[];
      final readDone = Completer<void>();
      final subscription = replies.listen((message) {
        queries.addAll((message as List).cast<RecordQuery>());
        if (message.isEmpty && !readDone.isCompleted) {
          readDone.complete();
        }
      });
      addTearDown(subscription.cancel);
      database = await RecordDatabase.open(
        factory: ObservedFiles(databaseFactoryFfi, replies.sendPort),
        path: path,
      );
      RecordJournal? restoredJournal;
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        final result = await isolated(work, input);
        if (result case (:final restored, :final damaged)) {
          // This observes the journal returned by the real restoration worker,
          // through its existing retained-action query, not its private maps.
          if (damaged == false && restored != null) {
            restoredJournal =
                (restored as dynamic).stored.journal as RecordJournal;
          }
        }
        return result;
      }

      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: hop,
      );
      expect(await store.read('alice'), expected);
      expect(await store.reading.read('alice'), expectedReading);
      expect(await store.hasPendingUploads('alice'), isTrue);
      expect(await store.discoveryCursor('alice'), 0);
      await readDone.future;
      final loadedPayloads = queries
          .expand((query) => query.rows)
          .where((row) => row['payload'] != null || row['kind'] == 1)
          .length;
      expect(
        loadedPayloads,
        lessThan(64),
        reason:
            'restoration must not read the 3,600 superseded position payloads',
      );
      expect(restoredJournal, isNotNull);
      expect(
        before.identities
            .where((id) => restoredJournal!.retained(id) != null)
            .length,
        lessThan(64),
        reason: 'superseded payloads must not stay in the restored journal',
      );
      expect((await database.rows('alice'))!.payloads, before.payloads);
      expect(
        (await store.pendingUploads('alice')).map(RecordJournal.identity),
        before.pending,
      );
      await store.checkInvariants();
    },
  );
}
