import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'status_test.dart' show withoutStorage;
import 'transfer_test.dart' show MediaFixture, waitForBytes;

/// Downloads that count leftover reads and can hold each read at [gate].
class _Inventory extends LocalDownloads {
  _Inventory({
    required super.root,
    required super.freeBytes,
    required super.policy,
    super.clock,
  });
  int reads = 0;
  Completer<void>? gate;

  @override
  Future<List<RetainedDownload>> retainedStorage() async {
    reads++;
    await gate?.future;
    return super.retainedStorage();
  }
}

/// Counts how many times the main isolate opens a saved file to read it.
class _ReadCounting implements File {
  _ReadCounting(this._file, this.reads);
  final File _file;
  final List<String> reads;

  @override
  String get path => _file.path;
  @override
  Uri get uri => _file.uri;
  @override
  Directory get parent => _file.parent;
  @override
  File get absolute => _file.absolute;
  @override
  bool get isAbsolute => _file.isAbsolute;
  @override
  Future<int> length() => _file.length();
  @override
  Future<bool> exists() => _file.exists();
  @override
  Future<FileStat> stat() => _file.stat();
  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    reads.add(path);
    return _file.openRead(start, end);
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _file.open(mode: mode);
  @override
  Future<File> rename(String newPath) => _file.rename(newPath);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _file.readAsString(encoding: encoding);
  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _file.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _file.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The test file does not forward $invocation.');
}

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late _Inventory downloads;

  _Inventory create({DateTime Function() clock = DateTime.now}) => _Inventory(
    root: root,
    freeBytes: () async => 64 << 20,
    policy: policy,
    clock: clock,
  );

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-signals-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = create();
    await downloads.bind(fixture.session(), fixture.books);
  });

  tearDown(() async {
    if (downloads.gate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  /// The library without the text edition, so its saved file is left over.
  List<Book> audioOnly() => [
    Book(
      id: 'work',
      title: 'Synthetic Work',
      author: 'Fixture Author',
      editions: [fixture.audio],
    ),
  ];

  Future<File> downloadText() async {
    await downloads.request(fixture.text);
    await downloads.idle;
    return File.fromUri(
      (await downloads.localFile(fixture.text.files.single))!,
    );
  }

  /// Waits until [listenable] notifies once more.
  Future<void> nextNotice(Listenable listenable) {
    final notified = Completer<void>();
    void done() {
      if (!notified.isCompleted) notified.complete();
    }

    listenable.addListener(done);
    return notified.future
        .timeout(const Duration(seconds: 5))
        .whenComplete(() => listenable.removeListener(done));
  }

  /// Starts the leftover inventory and waits for its first read.
  Future<ValueListenable<LeftoverFiles>> readLeftovers() async {
    final leftovers = downloads.leftovers;
    if (leftovers.value.reading) await nextNotice(leftovers);
    return leftovers;
  }

  /// Downloads the text edition, then leaves it out of the library.
  Future<File> leaveTextOver() async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), audioOnly());
    return file;
  }

  group('each edition has its own download signal', () {
    test('a byte notice for one edition notifies only that edition', () async {
      fixture.holdItem = 'audio1';
      final audio = downloads.watch(fixture.audio);
      final text = downloads.watch(fixture.text);
      final audioBytes = <int>[];
      var textNotices = 0;
      audio.addListener(() => audioBytes.add(audio.value.bytes));
      text.addListener(() => textNotices++);
      await downloads.request(fixture.audio);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, fixture.audio, 3);
      expect(audio.value.bytes, 3);
      expect(audioBytes, contains(3));
      fixture.release();
      await downloads.idle;
      expect(audio.value.phase, DownloadPhase.downloaded);
      expect(textNotices, 0);
    });

    test('byte progress reaches only the watch of its edition, and the '
        'broad listeners hear the start and the end', () async {
      downloads.dispose();
      await downloads.idle;
      var now = DateTime(2026);
      fixture.payload = Uint8List(256 << 10);
      fixture.pieceBytes = 4 << 10;
      downloads = create(
        clock: () => now = now.add(const Duration(seconds: 1)),
      );
      await downloads.bind(fixture.session(), fixture.books);
      final watched = downloads.watch(fixture.text);
      final watchedBytes = <int>[];
      final broadBytes = <int>[];
      final phaseBytes = <int>[];
      watched.addListener(() => watchedBytes.add(watched.value.bytes));
      downloads.addListener(
        () => broadBytes.add(downloads.status(fixture.text).bytes),
      );
      downloads.phases.addListener(
        () => phaseBytes.add(downloads.status(fixture.text).bytes),
      );
      await downloads.request(fixture.text);
      await downloads.idle;
      final length = fixture.payload.length;
      expect(downloads.status(fixture.text).bytes, length);
      expect(
        watchedBytes.where((bytes) => bytes > 0 && bytes < length).length,
        greaterThanOrEqualTo(10),
      );
      for (final heard in [broadBytes, phaseBytes]) {
        expect(heard.first, 0);
        expect(heard.last, length);
        expect(heard.where((bytes) => bytes > 0 && bytes < length), isEmpty);
      }
    });

    test(
      'watching an edition twice gives one signal that follows its status',
      () async {
        final watched = downloads.watch(fixture.text);
        expect(downloads.watch(fixture.text), same(watched));
        expect(watched.value.phase, DownloadPhase.none);
        await downloadText();
        expect(watched.value.phase, DownloadPhase.downloaded);
        expect(watched.value.bytes, downloads.status(fixture.text).bytes);
      },
    );
  });

  group('Downloads owns the leftover inventory', () {
    test('no leftover read happens until something asks for it', () async {
      await leaveTextOver();
      policy.network = MediaNetwork.disconnected;
      await downloads.idle;
      expect(downloads.reads, 0);
      final leftovers = await readLeftovers();
      expect(leftovers.value.entries, hasLength(1));
      expect(downloads.reads, 1);
    });

    test(
      'the inventory notifies once for each phase change and each reload',
      () async {
        await leaveTextOver();
        final leftovers = await readLeftovers();
        var notices = 0;
        leftovers.addListener(() => notices++);
        final phaseChange = nextNotice(leftovers);
        policy.network = MediaNetwork.disconnected;
        await phaseChange;
        expect(notices, 1);
        await downloads.reloadLeftovers();
        expect(notices, 2);
        expect(leftovers.value.entries, hasLength(1));
      },
    );

    test('byte progress neither reads nor notifies the inventory', () async {
      downloads.dispose();
      await downloads.idle;
      var now = DateTime(2026);
      fixture.payload = Uint8List(256 << 10);
      fixture.pieceBytes = 4 << 10;
      downloads = create(
        clock: () => now = now.add(const Duration(seconds: 1)),
      );
      await downloads.bind(fixture.session(), fixture.books);
      final leftovers = await readLeftovers();
      final readsBefore = downloads.reads;
      var phases = 0;
      var inventory = 0;
      downloads.phases.addListener(() => phases++);
      leftovers.addListener(() => inventory++);
      await downloads.request(fixture.text);
      await downloads.idle;
      await downloads.reloadLeftovers();
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(inventory, inInclusiveRange(1, phases + 1));
      expect(downloads.reads - readsBefore, lessThanOrEqualTo(phases + 1));
    });

    test('the inventory keeps the last list while a reload runs', () async {
      await leaveTextOver();
      final leftovers = await readLeftovers();
      final gate = downloads.gate = Completer<void>();
      var notices = 0;
      leftovers.addListener(() => notices++);
      final reload = downloads.reloadLeftovers();
      await pumpEventQueue();
      expect(leftovers.value.entries, hasLength(1));
      expect(leftovers.value.reading, isFalse);
      expect(notices, 0);
      gate.complete();
      await reload;
      expect(notices, 1);
      expect(leftovers.value.entries, hasLength(1));
    });

    test('a failed inventory read sets the error and removes no file', () async {
      final file = await leaveTextOver();
      final leftovers = await readLeftovers();
      final account = file.parent.parent;
      final moved = await account.rename('${account.path}.real');
      final link = await Link(account.path).create(moved.path);
      await downloads.reloadLeftovers();
      expect(leftovers.value.error, isNotNull);
      expect(leftovers.value.entries, hasLength(1));
      final saved = File(
        '${moved.path}/${file.parent.uri.pathSegments.where((part) => part.isNotEmpty).last}/complete',
      );
      expect(await saved.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      await link.delete();
      await moved.rename(account.path);
      await downloads.reloadLeftovers();
      expect(leftovers.value.error, isNull);
      expect(leftovers.value.entries, hasLength(1));
    });

    test('one account never sees the leftovers of another', () async {
      await leaveTextOver();
      final leftovers = await readLeftovers();
      expect(leftovers.value.entries, hasLength(1));
      downloads.gate = Completer<void>();
      await downloads.bind(fixture.session(user: 'bob'), audioOnly());
      expect(leftovers.value.entries, isEmpty);
      expect(leftovers.value.reading, isTrue);
    });

    test('reading the inventory makes no synchronous storage call', () async {
      await leaveTextOver();
      final retained = await IOOverrides.runZoned(
        downloads.retainedStorage,
        fseGetTypeSync: (_, _) =>
            throw StateError('The inventory read blocked on storage.'),
        statSync: (_) =>
            throw StateError('The inventory read blocked on storage.'),
      );
      expect(retained, hasLength(1));
    });
  });

  group('saved files are hashed off the UI isolate', () {
    test('a worker that reads the file itself computes each digest', () async {
      downloads.dispose();
      await downloads.idle;
      fixture.payload = Uint8List(256 << 10);
      downloads = create();
      await downloads.bind(fixture.session(), fixture.books);
      final mainReads = <String>[];
      await IOOverrides.runZoned(
        () async {
          await downloads.request(fixture.text);
          await downloads.idle;
          expect(
            await downloads.localFile(fixture.text.files.single),
            isNotNull,
          );
        },
        createFile: (path) =>
            _ReadCounting(Zone.root.run(() => File(path)), mainReads),
      );
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(mainReads, isEmpty);
      final saved = File.fromUri(
        (await downloads.localFile(fixture.text.files.single))!,
      );
      await saved.writeAsBytes(Uint8List(256 << 10)..[7] = 1);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
    });

    test('a saved file changed outside the app fails verification', () async {
      final file = await downloadText();
      await file.writeAsBytes([6, 5, 4, 3, 2, 1]);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      expect(
        downloads.status(fixture.text).phase,
        isNot(DownloadPhase.downloaded),
      );
    });
  });

  // The fixture's 6-byte files hash on this isolate, so the read counter
  // sees every digest.
  group('a verified saved file is read again only after it changes', () {
    Future<T> countingReads<T>(List<String> reads, Future<T> Function() body) =>
        IOOverrides.runZoned(
          body,
          createFile: (path) =>
              _ReadCounting(Zone.root.run(() => File(path)), reads),
        );

    test('a downloaded file opens without a read of its bytes', () async {
      final file = await downloadText();
      final reads = <String>[];
      final local = await countingReads(
        reads,
        () => downloads.localFile(fixture.text.files.single),
      );
      expect(local, file.uri);
      expect(reads, isEmpty);
    });

    test(
      'a restart opens a downloaded file without a read of its bytes',
      () async {
        await downloadText();
        downloads.dispose();
        await downloads.idle;
        final reads = <String>[];
        final local = await countingReads(reads, () async {
          downloads = create();
          await downloads.bind(fixture.session(), fixture.books);
          return downloads.localFile(fixture.text.files.single);
        });
        expect(local, isNotNull);
        expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
        expect(reads, isEmpty);
      },
    );

    test(
      'a file touched outside the app is read once and stays downloaded',
      () async {
        final file = await downloadText();
        await file.setLastModified(DateTime.utc(2020));
        final reads = <String>[];
        await countingReads(reads, () async {
          expect(
            await downloads.localFile(fixture.text.files.single),
            isNotNull,
          );
          expect(
            await downloads.localFile(fixture.text.files.single),
            isNotNull,
          );
        });
        expect(reads, [file.path]);
        expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      },
    );

    test(
      'a restart after a touched file was read again does not read it',
      () async {
        final file = await downloadText();
        await file.setLastModified(DateTime.utc(2020));
        expect(await downloads.localFile(fixture.text.files.single), isNotNull);
        downloads.dispose();
        await downloads.idle;
        final reads = <String>[];
        await countingReads(reads, () async {
          downloads = create();
          await downloads.bind(fixture.session(), fixture.books);
        });
        expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
        expect(reads, isEmpty);
      },
    );
  });

  group('binding computes source ids off the UI isolate', () {
    test(
      'a large library binds without hashing its sources on the UI isolate',
      () async {
        final books = [
          for (var book = 0; book < 400; book++)
            Book(
              id: 'book-$book',
              title: 'Book $book',
              author: 'Author',
              editions: [
                Edition(
                  id: 'edition-$book',
                  kind: EditionKind.audio,
                  label: 'Recording',
                  memberIds: ['book-$book'],
                  files: [
                    for (var file = 0; file < 50; file++)
                      SourceFile(
                        itemId: 'item-$book-$file',
                        displayName: 'Part $file',
                        mediaSourceId: 'source-$book-$file',
                        revision: 'revision-$book-$file',
                        durationMs: null,
                        container: 'm4b',
                        sizeBytes: 1000 + file,
                        chapters: [
                          for (var chapter = 0; chapter < 20; chapter++)
                            AudioChapter('Chapter $chapter', chapter * 1000),
                        ],
                      ),
                  ],
                ),
              ],
            ),
        ];
        // The cost that bind paid on the UI isolate before: one digest of
        // the encoded identity of each source.
        final inline = Stopwatch()..start();
        for (final book in books) {
          for (final source in book.editions.single.files) {
            sha256.convert(
              utf8.encode(jsonEncode([source.key, source.revision])),
            );
          }
        }
        inline.stop();
        final call = Stopwatch()..start();
        final binding = downloads.bind(null, books);
        call.stop();
        await binding;
        expect(
          call.elapsedMicroseconds,
          lessThan(inline.elapsedMicroseconds ~/ 2),
          reason:
              'bind held the UI isolate ${call.elapsedMicroseconds} µs; '
              'hashing inline took ${inline.elapsedMicroseconds} µs',
        );
      },
    );

    test('a download asked right after a catalog change still runs', () async {
      final binding = downloads.bind(fixture.session(), [
        Book(
          id: 'work',
          title: 'Synthetic Work',
          author: 'Fixture Author',
          editions: [fixture.text],
        ),
      ]);
      final request = downloads.request(fixture.text);
      await binding;
      await request;
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    });

    test(
      'a saved file asked for right after a catalog change is found',
      () async {
        await downloadText();
        final binding = downloads.bind(fixture.session(), [
          Book(
            id: 'work',
            title: 'Synthetic Work',
            author: 'Fixture Author',
            editions: [fixture.text],
          ),
        ]);
        expect(await downloads.localFile(fixture.text.files.single), isNotNull);
        await binding;
      },
    );

    test('status reads only memory after a bind', () async {
      await downloadText();
      final state = withoutStorage(() => downloads.watch(fixture.text).value);
      expect(state.phase, DownloadPhase.downloaded);
    });
  });

  for (final (library, padding) in [('small', 0), ('large', 20)]) {
    group('a lookup during a rebind of a $library library (t1-vtiy)', () {
      /// [books] with [padding] more sources, so a large library binds through
      /// a worker isolate.
      List<Book> padded(List<Book> books) => [
        ...books,
        if (padding > 0)
          Book(
            id: 'padding',
            title: 'Padding',
            author: 'Fixture Author',
            editions: [
              Edition(
                id: 'padding',
                kind: EditionKind.audio,
                label: 'Recording',
                memberIds: ['padding'],
                files: [
                  for (var file = 0; file < padding; file++)
                    SourceFile(
                      itemId: 'padding-$file',
                      displayName: 'Part $file',
                      mediaSourceId: 'padding-$file',
                      revision: 'revision-$file',
                      durationMs: null,
                      container: 'm4b',
                      sizeBytes: 6,
                    ),
                ],
              ),
            ],
          ),
      ];

      List<Book> textOnly() => [
        Book(
          id: 'work',
          title: 'Synthetic Work',
          author: 'Fixture Author',
          editions: [fixture.text],
        ),
      ];

      /// Starts [lookup] where each storage check waits until the returned
      /// release runs. The rebind of [books] for [session] applies first.
      Future<T> overlapRebind<T>(
        Future<T> Function() lookup,
        JellyfinSession session,
        List<Book> books,
      ) async {
        final gate = Completer<void>();
        final looking = IOOverrides.runZoned(
          lookup,
          fseGetType: (path, followLinks) async {
            await gate.future;
            return Zone.root.run(
              () => FileSystemEntity.type(path, followLinks: followLinks),
            );
          },
        );
        final applied = nextNotice(downloads.phases);
        final binding = downloads.bind(session, padded(books));
        await applied;
        gate.complete();
        final result = await looking;
        await binding;
        return result;
      }

      test('a rebind to a smaller library that keeps the edition still finds the file', () async {
        await downloadText();
        final found = await overlapRebind(
          () => downloads.localFile(fixture.text.files.single),
          fixture.session(),
          textOnly(),
        );
        expect(found, isNotNull);
        expect(await File.fromUri(found!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      });

      test('a rebind that drops the edition finds nothing', () async {
        await downloadText();
        final found = await overlapRebind(
          () => downloads.localFile(fixture.text.files.single),
          fixture.session(),
          audioOnly(),
        );
        expect(found, isNull);
      });

      test('a rebind to another account finds nothing', () async {
        await downloadText();
        final found = await overlapRebind(
          () => downloads.localFile(fixture.text.files.single),
          fixture.session(user: 'bob'),
          fixture.books,
        );
        expect(found, isNull);
      });

      test(
        'the reader reads a saved file through a rebind that keeps it',
        () async {
          await downloadText();
          final bytes = await overlapRebind(
            () => downloads.readLocalFile(
              fixture.text.files.single,
              (uri) => File.fromUri(uri).readAsBytes(),
            ),
            fixture.session(),
            textOnly(),
          );
          expect(bytes, [1, 2, 3, 4, 5, 6]);
        },
      );
    });
  }
}
