// HeardWindows owns the heard windows of each audio edition: their times
// and heard words. They are derived data: local, rebuildable, never
// synced, never a personal record.
import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/derived_store.dart';
import 'package:bookfin/speech/heard_windows.dart';
import 'package:bookfin/speech/words.dart';
import 'package:flutter_test/flutter_test.dart';

SourceFile file(String key, {String revision = 'r1', int duration = 600000}) =>
    SourceFile(
      itemId: key,
      displayName: key,
      mediaSourceId: 'm',
      revision: revision,
      durationMs: duration,
      container: 'mp3',
      sizeBytes: 1,
    );

Edition edition(List<SourceFile> files) => Edition(
  id: 'audio',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: files,
  memberIds: [for (final file in files) file.key],
);

AudioPosition at(SourceFile file, int ms) => AudioPosition(
  editionId: 'audio',
  sourceKey: file.key,
  revision: file.revision,
  milliseconds: ms,
);

class MemoryStore implements DerivedStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A hearing that gives the words `w<start>` and records each call.
class FakeHearing {
  final calls = <(String path, int startMs, bool urgent)>[];
  final gates = <Completer<void>>[];
  bool gated = false;
  Heard? Function(String path, int startMs)? answer;

  Future<Heard?> call(
    String path,
    int startMs,
    int lengthMs, {
    bool urgent = false,
  }) async {
    calls.add((path, startMs, urgent));
    if (gated) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    return (answer ?? (_, start) => Heard(['w$start', 'x'], const [0, 4000]))(
      path,
      startMs,
    );
  }
}

Future<R> inline<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);

void main() {
  final one = file('one');
  final two = file('two', duration: 300000);
  final book = edition([one, two]);
  late MemoryStore store;
  late FakeHearing hearing;
  late Set<String> downloaded;

  HeardWindows windows() => HeardWindows(
    hear: hearing.call,
    store: store,
    localPath: (file) async =>
        downloaded.contains(file.itemId) ? '/media/${file.itemId}.mp3' : null,
    hop: inline,
  );

  setUp(() {
    store = MemoryStore();
    hearing = FakeHearing();
    downloaded = {'one', 'two'};
  });

  test('hears an 8 s window centered on a place and keeps it', () async {
    final heard = windows();
    final window = (await heard.hear(book, at(one, 60000)))!;
    expect(hearing.calls.single, ('/media/one.mp3', 56000, true));
    expect((window.startMs, window.lengthMs), (56000, 8000));
    expect(window.covers(at(one, 60000)), isTrue);
    expect(await heard.windowsOf(book), [window]);
  });

  test('a place that a kept window covers is not heard again', () async {
    final heard = windows();
    final first = await heard.hear(book, at(one, 60000));
    final second = await heard.hear(book, at(one, 62500));
    expect(second, same(first));
    expect(hearing.calls, hasLength(1));
  });

  test('a window keeps inside its file', () async {
    final heard = windows();
    final start = (await heard.hear(book, at(one, 2000)))!;
    final end = (await heard.hear(book, at(two, 299000)))!;
    expect((start.startMs, start.lengthMs), (0, 8000));
    expect((end.startMs, end.lengthMs), (292000, 8000));
  });

  test('an edition that is not downloaded hears nothing', () async {
    downloaded = {'two'};
    expect(await windows().hear(book, at(one, 60000)), isNull);
    expect(hearing.calls, isEmpty);
  });

  test('a window that hears no words is not kept', () async {
    hearing.answer = (_, _) => null;
    final heard = windows();
    expect(await heard.hear(book, at(one, 60000)), isNull);
    expect(await heard.windowsOf(book), isEmpty);
  });

  Future<void> hearAndStop(AudioPosition place) async {
    final heard = windows();
    await heard.hear(book, place);
    await heard.flush();
  }

  test('kept windows come back after a restart', () async {
    await hearAndStop(at(one, 60000));
    await hearAndStop(at(two, 1000));
    final again = windows();
    final kept = await again.windowsOf(book);
    expect(
      [for (final window in kept) window.heard.words.first],
      ['w56000', 'w0'],
    );
  });

  test('windows of a file whose revision changed are let go', () async {
    await hearAndStop(at(one, 60000));
    await hearAndStop(at(two, 1000));
    final changed = edition([file('one', revision: 'r2'), two]);
    final kept = await windows().windowsOf(changed);
    expect([for (final window in kept) window.sourceKey], ['two:m']);
  });

  test('windows are kept in the order of the edition', () async {
    final heard = windows();
    await heard.hear(book, at(two, 1000));
    await heard.hear(book, at(one, 120000));
    await heard.hear(book, at(one, 60000));
    expect(
      [for (final window in await heard.windowsOf(book)) window.startMs],
      [56000, 116000, 0],
    );
    heard.checkInvariants();
  });

  test(
    'an unreadable store starts empty, and new windows replace it',
    () async {
      store.values['audio'] = '{not json';
      final heard = windows();
      expect(await heard.windowsOf(book), isEmpty);
      await heard.hear(book, at(one, 60000));
      await heard.flush();
      expect(await windows().windowsOf(book), hasLength(1));
    },
  );

  test('a waiting person goes before the listening windows', () async {
    hearing.gated = true;
    final heard = windows();
    heard.hearSoon(book, at(one, 100000));
    heard.hearSoon(book, at(one, 200000));
    heard.hearSoon(book, at(one, 300000));
    await pumpEventQueue();
    final tap = heard.hear(book, at(one, 400000));
    while (hearing.calls.length < 4) {
      await pumpEventQueue();
      hearing.gates.lastOrNull?.complete();
    }
    await tap;
    for (final gate in hearing.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    expect(
      [for (final call in hearing.calls) call.$2],
      [96000, 396000, 196000, 296000],
    );
    expect(
      [for (final call in hearing.calls) call.$3],
      [false, true, false, false],
    );
  });

  test('a new window notifies its listeners', () async {
    final heard = windows();
    var notified = 0;
    heard.changes.addListener(() => notified++);
    await heard.hear(book, at(one, 60000));
    expect(notified, greaterThan(0));
  });

  test('the windows of an edition are known at once after a read', () async {
    final heard = windows();
    expect(heard.windowsNow(book), isNull);
    await heard.windowsOf(book);
    expect(heard.windowsNow(book), isEmpty);
  });

  test('a store that cannot write keeps the window for this run', () async {
    final heard = HeardWindows(
      hear: hearing.call,
      store: _FailingStore(),
      localPath: (file) async => '/media/${file.itemId}.mp3',
      hop: inline,
    );
    expect(await heard.hear(book, at(one, 60000)), isNotNull);
    expect(await heard.windowsOf(book), hasLength(1));
  });
}

class _FailingStore implements DerivedStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw const FileSystemExceptionLike();
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike();
}
