import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class WorkerOnlyJson {
  WorkerOnlyJson(this.ui, this.value);

  final SendPort ui;
  final Map<String, dynamic> value;

  Map<String, dynamic> toJson() {
    if (Isolate.current.controlPort == ui) {
      throw StateError('Growing settings were encoded on the UI isolate.');
    }
    return value;
  }
}

Future<R> inWorker<M, R>(FutureOr<R> Function(M) work, M input) =>
    Isolate.run(() => work(input));

class Workers {
  final texts = <String>[];
  int completed = 0;
  final copied = <int, Completer<void>>{};
  final copiesReady = Completer<void>();
  bool holdCopies = false;

  Future<R> call<M, R>(FutureOr<R> Function(M) work, M input) async {
    final result = await inWorker(work, input);
    completed++;
    if (result is String) texts.add(result);
    if (holdCopies && result is Map && result.containsKey('pdfBooks')) {
      final release = Completer<void>();
      copied[result['submission'] as int] = release;
      if (copied.length == 3) copiesReady.complete();
      await release.future;
    }
    return result;
  }
}

Map<String, dynamic> choices(String view) => {
  for (var index = 0; index < 2000; index++)
    'book-$index': {'view': view, 'trimMargins': false},
};

Map<String, dynamic> readingSettings(Object books) => {
  'version': 1,
  'fontSize': 20.0,
  'pdfBooks': books,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late RecordDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('settings-worker-');
    addTearDown(() => directory.delete(recursive: true));
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/records.sqlite',
    );
    addTearDown(database.close);
  });

  for (final sqlite in [false, true]) {
    test('${sqlite ? 'SQLite' : 'preferences'} copies growing reading settings '
        'and encodes their durable text outside the UI isolate', () async {
      final workers = Workers();
      final store = LocalResumeStore(
        openDatabase: sqlite ? () async => database : null,
        hop: workers.call,
      );
      final books = choices('text');
      await store.reading.saveReading(
        'alice',
        ReadingChanges(
          readingSettings(WorkerOnlyJson(Isolate.current.controlPort, books)),
        ),
      );

      final text = sqlite
          ? (await database.rows('alice'))!.metadata
          : (await SharedPreferences.getInstance()).getString(
              'bookfin.playback.v1.alice',
            )!;
      expect(workers.texts.contains(text), isTrue);
      expect(jsonDecode(text)['reading']['pdfBooks'], books);
      final restarted = LocalResumeStore(
        openDatabase: sqlite ? () async => database : null,
        hop: workers.call,
      );
      expect((await restarted.reading.read('alice'))!['pdfBooks'], books);
    });
  }

  test('audio saves encode retained reading preferences in a worker', () async {
    final workers = Workers();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: workers.call,
    );
    await store.reading.saveReading(
      'alice',
      ReadingChanges(readingSettings(choices('pageWords'))),
    );
    workers.texts.clear();

    await store.save('alice', ListeningChanges({'version': 3, 'speed': 1.5}));

    final text = (await database.rows('alice'))!.metadata;
    expect(workers.texts.contains(text), isTrue);
    expect(jsonDecode(text)['speed'], 1.5);
    expect(jsonDecode(text)['reading']['pdfBooks']['book-1999'], {
      'view': 'pageWords',
      'trimMargins': false,
    });
  });

  test('settings-only SQLite accounts restore and copy large metadata '
      'in workers even without reading records', () async {
    final store = LocalResumeStore(openDatabase: () async => database);
    await store.reading.saveReading(
      'alice',
      ReadingChanges(readingSettings(choices('text'))),
    );
    final workers = Workers();
    final restarted = LocalResumeStore(
      openDatabase: () async => database,
      hop: workers.call,
    );

    expect(
      (await restarted.reading.read('alice'))!['pdfBooks'],
      choices('text'),
    );
    expect(workers.completed, greaterThan(0));
    final restored = workers.completed;
    expect(
      (await restarted.reading.read('alice'))!['pdfBooks'],
      choices('text'),
    );
    expect(workers.completed, greaterThan(restored));
  });

  test(
    'worker completion order cannot reorder account-specific saves',
    () async {
      final workers = Workers()..holdCopies = true;
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: workers.call,
      );
      final first = {...readingSettings(choices('original')), 'submission': 1};
      final saves = [
        store.reading.saveReading('alice', ReadingChanges(first)),
        store.reading.saveReading(
          'alice',
          ReadingChanges({
            ...readingSettings(choices('text')),
            'submission': 2,
          }),
        ),
        store.reading.saveReading(
          'bob',
          ReadingChanges({
            ...readingSettings(choices('pageWords')),
            'submission': 3,
          }),
        ),
      ];
      first['pdfBooks'] = choices('pageWords');
      await workers.copiesReady.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      for (final submission in [3, 2, 1]) {
        workers.copied[submission]?.complete();
      }
      await Future.wait(saves);
      expect(workers.copied, hasLength(3));

      expect(
        jsonDecode(
          (await database.rows('alice'))!.metadata,
        )['reading']['pdfBooks'],
        choices('text'),
      );
      expect(
        jsonDecode(
          (await database.rows('bob'))!.metadata,
        )['reading']['pdfBooks'],
        choices('pageWords'),
      );
      final snapshot = readingSettings(choices('original'));
      workers.holdCopies = false;
      final save = store.reading.saveReading('alice', ReadingChanges(snapshot));
      (snapshot['pdfBooks'] as Map)['book-0'] = {
        'view': 'text',
        'trimMargins': true,
      };
      await save;
      expect(
        jsonDecode(
          (await database.rows('alice'))!.metadata,
        )['reading']['pdfBooks']['book-0'],
        {'view': 'original', 'trimMargins': false},
      );
    },
  );
}
