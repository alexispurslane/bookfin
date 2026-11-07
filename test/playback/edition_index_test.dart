import 'dart:collection';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show
        LocalFiles,
        TestEngine,
        MemoryResume,
        account,
        title,
        recording,
        first,
        second;

/// How many elements the counted lists of one fixture handed out.
class Reads {
  int count = 0;
}

/// A fixed list that counts each element it hands out, so a test can tell
/// how much of a library or an edition a call walked.
class CountingList<E> extends ListBase<E> {
  CountingList(this._items, this._reads);
  final List<E> _items;
  final Reads _reads;
  @override
  int get length => _items.length;
  @override
  set length(int value) => throw UnsupportedError('A fixed list');
  @override
  E operator [](int index) {
    _reads.count++;
    return _items[index];
  }

  @override
  void operator []=(int index, E value) =>
      throw UnsupportedError('A fixed list');
}

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late Playback playback;
  setUp(() {
    downloads = LocalFiles();
    engine = TestEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  group('a large library', () {
    // Other books come first, so a scan for the listened book walks all of
    // them. Each read of one of their editions counts.
    const others = 2000;
    final reads = Reads();
    final library = [
      for (var i = 0; i < others; i++)
        Book(
          id: 'other $i',
          title: 'Other $i',
          author: 'Someone',
          editions: CountingList([
            Edition(
              id: 'other $i',
              kind: EditionKind.audio,
              label: 'Narrator',
              files: const [],
              memberIds: const [],
            ),
          ], reads),
        ),
      title,
    ];

    setUp(() async {
      await playback.bind(account(), library);
      await playback.open(title, recording, autoplay: false);
      await playback.seekEdition(75000);
      await playback.addBookmark();
      await playback.seekEdition(0);
      reads.count = 0;
    });

    test('names a source without a scan of the library', () {
      expect(playback.sourceName(_at(second, 0)), 'Part two');
      reads.count = 0;
      expect(playback.sourceName(_at(first, 0)), 'Part one');
      expect(reads.count, lessThan(others));
    });

    test('restores a bookmark without a scan of the library', () async {
      await playback.restoreBookmark(playback.bookmarks.single.id);
      expect(playback.editionMilliseconds, 75000);
      expect(reads.count, lessThan(others));
    });

    test('reopens the saved book with one scan of the library', () async {
      await playback.seekEdition(75000);
      await playback.flush();
      await playback.bind(null, []);
      reads.count = 0;
      await playback.bind(account(), library);
      expect(playback.edition, same(recording));
      expect(playback.editionMilliseconds, 75000);
      expect(reads.count, lessThanOrEqualTo(others));
    });

    test('a refresh that keeps the open book scans the library once', () async {
      await playback.bind(account(), [...library]);
      // The refresh itself and a later lookup share one scan.
      playback.sourceName(_at(first, 0));
      expect(playback.edition, same(recording));
      expect(playback.book, same(title));
      expect(reads.count, lessThanOrEqualTo(others));
    });
  });

  group('a long recording', () {
    const parts = 500;
    final reads = Reads();
    final files = [
      for (var i = 0; i < parts; i++)
        SourceFile(
          itemId: 'part $i',
          displayName: 'Part $i',
          mediaSourceId: 'm$i',
          revision: 'r$i',
          durationMs: 1000,
          container: 'wav',
          sizeBytes: 42,
        ),
    ];
    final long = Edition(
      id: 'long',
      kind: EditionKind.audio,
      label: 'Narrator',
      files: CountingList(files, reads),
      memberIds: [for (final file in files) file.key],
    );
    final book = Book(
      id: 'long',
      title: 'The long journey',
      author: 'A. Writer',
      editions: [long],
    );

    setUp(() async {
      for (final file in files) {
        downloads.files[file.key] = Uri.file('/${file.key}.wav');
      }
      await playback.bind(account(), [book]);
      await playback.open(book, long, autoplay: false);
    });

    test('knows its length without a walk of its files', () {
      expect(playback.durationMilliseconds, parts * 1000);
      reads.count = 0;
      expect(playback.durationMilliseconds, parts * 1000);
      expect(reads.count, lessThan(parts));
    });

    test('shows its progress without a walk of its files', () {
      expect(playback.progress(long), (elapsedMs: 0, totalMs: parts * 1000));
      reads.count = 0;
      expect(playback.progress(long), (elapsedMs: 0, totalMs: parts * 1000));
      expect(reads.count, lessThan(parts));
    });

    test('a seek to the middle saves the same place', () async {
      await playback.seekEdition(250500);
      expect(playback.progress(long), (
        elapsedMs: 250500,
        totalMs: parts * 1000,
      ));
      await playback.flush();
      await playback.bind(null, []);
      await playback.bind(account(), [book]);
      expect(playback.position?.sourceKey, files[250].key);
      expect(playback.position?.milliseconds, 500);
      expect(playback.progress(long), (
        elapsedMs: 250500,
        totalMs: parts * 1000,
      ));
    });

    test('a seek past the end saves the end of the last part', () async {
      await playback.seekEdition(parts * 1000 + 5000);
      await playback.flush();
      await playback.bind(null, []);
      await playback.bind(account(), [book]);
      expect(playback.position?.sourceKey, files.last.key);
      expect(playback.position?.milliseconds, 1000);
    });
  });

  test('a recording with a part of unknown length shows no progress', () async {
    const unknown = SourceFile(
      itemId: 'three',
      displayName: 'Part three',
      mediaSourceId: 'm3',
      revision: 'r3',
      durationMs: null,
      container: 'wav',
      sizeBytes: 42,
    );
    const edition = Edition(
      id: 'partly known',
      kind: EditionKind.audio,
      label: 'Narrator',
      files: [first, second, unknown],
      memberIds: ['one:m1', 'two:m2', 'three:m3'],
    );
    const book = Book(
      id: 'partly known',
      title: 'Partly known',
      author: 'A. Writer',
      editions: [edition],
    );
    downloads.files[unknown.key] = Uri.file('/three.wav');
    await playback.bind(account(), [book]);
    await playback.open(book, edition, autoplay: false);
    await playback.seekSource(second.key, 5000);
    expect(playback.durationMilliseconds, isNull);
    expect(playback.editionMilliseconds, 65000);
    expect(playback.progress(edition), isNull);
  });

  test('a source outside the library keeps a generic name', () async {
    await playback.bind(account(), [title]);
    expect(
      playback.sourceName(
        const AudioPosition(
          editionId: 'gone',
          sourceKey: 'gone:m9',
          revision: 'r9',
          milliseconds: 0,
        ),
      ),
      'Source gone:m9',
    );
    expect(playback.sourceName(_at(first, 0)), 'Part one');
  });
}

AudioPosition _at(SourceFile file, int milliseconds) => AudioPosition(
  editionId: recording.id,
  sourceKey: file.key,
  revision: file.revision,
  milliseconds: milliseconds,
);
