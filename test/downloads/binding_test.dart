import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transfer_test.dart' show MediaFixture, waitForBytes;

/// Real disk reads completed in microtasks, with one explicit storage gate.
/// This makes completion-order assertions independent of filesystem timing.
class _Storage {
  String? heldPath;
  String? heldStat;
  final entered = Completer<void>();
  final released = Completer<void>();
  final paths = <String>[];
  final manifests = <String>[];

  T run<T>(T Function() body) => IOOverrides.runZoned(
    body,
    fseGetType: (path, followLinks) async {
      paths.add(path);
      if (path == heldPath) {
        if (!entered.isCompleted) entered.complete();
        await released.future;
      }
      return Zone.root.run(
        () => FileSystemEntity.typeSync(path, followLinks: followLinks),
      );
    },
    createFile: (path) => _File(Zone.root.run(() => File(path)), this),
    createDirectory: (path) => _Directory(Zone.root.run(() => Directory(path))),
  );

  void release() {
    if (!released.isCompleted) released.complete();
  }
}

class _File extends Fake implements File {
  _File(this.file, this.storage);
  final File file;
  final _Storage storage;
  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  Directory get parent => Directory(file.parent.path);
  @override
  Future<int> length() async => file.lengthSync();
  @override
  Future<FileStat> stat() async {
    if (path == storage.heldStat) {
      if (!storage.entered.isCompleted) storage.entered.complete();
      await storage.released.future;
    }
    return file.statSync();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    storage.manifests.add(path);
    return file.readAsStringSync(encoding: encoding);
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(file.readAsBytesSync().sublist(start ?? 0, end));
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    file.writeAsStringSync(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    return file;
  }

  @override
  Future<File> rename(String newPath) async => file.renameSync(newPath);
}

class _Directory extends Fake implements Directory {
  _Directory(this.directory);
  final Directory directory;
  @override
  String get path => directory.path;
  @override
  Uri get uri => directory.uri;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.fromIterable(
    directory
        .listSync(recursive: recursive, followLinks: followLinks)
        .map((entry) => entry is Directory ? _Directory(entry) : entry),
  );
  @override
  Future<Directory> delete({bool recursive = false}) async {
    directory.deleteSync(recursive: recursive);
    return directory;
  }
}

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;
  LocalDownloads create() => LocalDownloads(
    root: root,
    freeBytes: () async => 1000000,
    policy: policy,
  );
  List<Book> books(List<Edition> editions, {int padding = 0}) => [
    Book(
      id: 'work',
      title: 'Work',
      author: 'Author',
      editions: [
        ...editions,
        if (padding > 0)
          Edition(
            id: 'padding',
            kind: EditionKind.audio,
            label: 'Padding',
            memberIds: [],
            files: [
              for (var n = 0; n < padding; n++)
                SourceFile(
                  itemId: 'extra-$n',
                  mediaSourceId: 'extra-$n',
                  displayName: 'Extra',
                  revision: 'v1',
                  durationMs: null,
                  container: 'm4b',
                  sizeBytes: null,
                ),
            ],
          ),
      ],
    ),
  ];
  String directory(SourceFile source) {
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    return '${root.path}/${hash(fixture.session().scope.key)}/${hash(jsonEncode([source.key, source.revision]))}';
  }

  Future<void> restart() async {
    downloads.dispose();
    await downloads.idle;
    downloads = create();
  }

  Future<void> saveAll() async {
    await downloads.bind(fixture.session(), fixture.books);
    await downloads.request(fixture.audio);
    await downloads.request(fixture.text);
    await downloads.idle;
    policy.network = MediaNetwork.disconnected;
  }

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-binding-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = create();
  });
  tearDown(() async {
    fixture.release();
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  test(
    'fresh restoration publishes no availability before verification finishes',
    () async {
      await saveAll();
      await restart();
      final storage = _Storage()
        ..heldStat = '${directory(fixture.text.files.single)}/complete';
      final binding = storage.run(
        () => downloads.bind(fixture.session(), fixture.books),
      );
      try {
        await storage.entered.future;
        await pumpEventQueue();
        expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      } finally {
        storage.release();
        await binding;
      }
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  test(
    'unfinished restoration satisfies the record ownership invariants',
    () async {
      await saveAll();
      await restart();
      final storage = _Storage()
        ..heldPath = '${directory(fixture.text.files.single)}/record.json';
      final binding = storage.run(
        () => downloads.bind(fixture.session(), fixture.books),
      );
      try {
        await storage.entered.future;
        downloads.checkInvariants();
      } finally {
        storage.release();
        await binding;
      }
    },
  );

  test(
    'adding a held source keeps verified availability and its narrow signal',
    () async {
      await saveAll();
      await downloads.bind(fixture.session(), books([fixture.text]));
      final notices = <DownloadPhase>[];
      downloads
          .watch(fixture.text)
          .addListener(() => notices.add(downloads.status(fixture.text).phase));
      final storage = _Storage()
        ..heldPath = '${directory(fixture.audio.files.first)}/record.json';
      final binding = storage.run(
        () => downloads.bind(fixture.session(), fixture.books),
      );
      try {
        await storage.entered.future;
        expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
        expect(notices, isEmpty);
      } finally {
        storage.release();
        await binding;
      }
    },
  );

  test('adding a source reads only added sources', () async {
    await saveAll();
    await downloads.bind(fixture.session(), books([fixture.text]));
    final storage = _Storage();
    await storage.run(() => downloads.bind(fixture.session(), fixture.books));
    expect(
      storage.paths.where(
        (path) => path.startsWith(directory(fixture.text.files.single)),
      ),
      isEmpty,
    );
    expect(
      storage.manifests,
      unorderedEquals([
        '${directory(fixture.audio.files.first)}/record.json',
        '${directory(fixture.audio.files.last)}/record.json',
      ]),
    );
  });

  for (final read in [false, true]) {
    test(
      '${read ? 'owned reading' : 'file lookup'} finishes while an unrelated initial restore is held',
      () async {
        await saveAll();
        await restart();
        final storage = _Storage()
          ..heldPath = '${directory(fixture.audio.files.first)}/record.json';
        final binding = storage.run(
          () => downloads.bind(fixture.session(), fixture.books),
        );
        var finished = false;
        Uri? found;
        try {
          expect(downloads.status(fixture.text).phase, DownloadPhase.none);
          await storage.entered.future;
          final lookup = storage.run(() async {
            found = read
                ? await downloads.readLocalFile(
                    fixture.text.files.single,
                    (file) async => file.uri,
                  )
                : await downloads.localFile(fixture.text.files.single);
            finished = true;
          });
          await pumpEventQueue();
          expect(
            finished,
            isTrue,
            reason: 'Only the unrelated source is held.',
          );
          expect(found, isNotNull);
          expect(await File.fromUri(found!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
          await lookup;
        } finally {
          storage.release();
          await binding;
        }
      },
    );
  }

  test('same-account credential renewal keeps availability without disk restoration', () async {
    await saveAll();
    final session = fixture.session();
    final renewed = JellyfinSession(
      scope: session.scope,
      token: 'renewed-token',
      username: session.username,
      canDownload: true,
    );
    final storage = _Storage();
    final binding = storage.run(() => downloads.bind(renewed, fixture.books));
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    await binding;
    expect(storage.paths, isEmpty);
  });

  test('credential renewal still resets mobile permission while keeping local availability', () async {
    await saveAll();
    policy.network = MediaNetwork.mobile;
    policy.allowMobileForSession();
    final session = fixture.session();
    await downloads.bind(
      JellyfinSession(
        scope: session.scope,
        token: 'renewed-token',
        username: session.username,
        canDownload: true,
      ),
      fixture.books,
    );
    expect(policy.mobileAllowed, isFalse);
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
  });

  Edition changedText({
    String? revision,
    int? size,
    bool? original,
    bool rename = false,
  }) {
    final source = fixture.text.files.single;
    return Edition(
      id: fixture.text.id,
      kind: EditionKind.text,
      label: 'EPUB',
      memberIds: fixture.text.memberIds,
      files: [
        SourceFile(
          itemId: source.itemId,
          mediaSourceId: source.mediaSourceId,
          displayName: rename ? 'New name' : source.displayName,
          revision: revision ?? source.revision,
          sizeBytes: size ?? source.sizeBytes,
          isItemOriginal: original ?? source.isItemOriginal,
          durationMs: source.durationMs,
          container: source.container,
          chapters: rename
              ? [const AudioChapter('New chapter', 0)]
              : source.chapters,
        ),
      ],
    );
  }

  test(
    'display metadata changes keep verified files without reading storage',
    () async {
      await saveAll();
      final renamed = changedText(rename: true);
      final storage = _Storage();
      await storage.run(
        () =>
            downloads.bind(fixture.session(), books([fixture.audio, renamed])),
      );
      expect(storage.paths, isEmpty);
      expect(downloads.status(renamed).phase, DownloadPhase.downloaded);
      downloads.checkInvariants();
    },
  );

  for (final change in ['revision', 'length', 'original']) {
    test(
      'a changed source $change restores only that source and rejects incompatible bytes',
      () async {
        await saveAll();
        final oldPath = '${directory(fixture.text.files.single)}/complete';
        final changed = changedText(
          revision: change == 'revision' ? 'v2' : null,
          size: change == 'length' ? 7 : null,
          original: change == 'original' ? false : null,
        );
        final storage = _Storage();
        await storage.run(
          () => downloads.bind(
            fixture.session(),
            books([fixture.audio, changed]),
          ),
        );
        expect(await downloads.localFile(changed.files.single), isNull);
        expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
        for (final source in fixture.audio.files) {
          expect(
            storage.paths.where((path) => path.startsWith(directory(source))),
            isEmpty,
          );
        }
        expect(await File(oldPath).exists(), isTrue);
        if (change != 'revision') {
          expect(storage.manifests, [
            '${directory(changed.files.single)}/record.json',
          ]);
        }
        downloads.checkInvariants();
      },
    );
  }

  for (final counts in [(0, 20), (20, 0), (20, 30)]) {
    test(
      'overlapping plans with ${counts.$1} then ${counts.$2} extra sources share unchanged restoration',
      () async {
        await saveAll();
        await restart();
        final storage = _Storage()
          ..heldPath = '${directory(fixture.text.files.single)}/record.json';
        final first = storage.run(
          () => downloads.bind(
            fixture.session(),
            books([fixture.text], padding: counts.$1),
          ),
        );
        await storage.entered.future;
        final second = storage.run(
          () => downloads.bind(
            fixture.session(),
            books([fixture.text, fixture.audio], padding: counts.$2),
          ),
        );
        final lookup = downloads.localFile(fixture.text.files.single);
        storage.release();
        await Future.wait([first, second]);
        expect(await lookup, isNotNull);
        expect(
          storage.manifests.where(
            (path) =>
                path == '${directory(fixture.text.files.single)}/record.json',
          ),
          hasLength(1),
        );
        expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
        downloads.checkInvariants();
      },
    );
  }

  test(
    'lookups and commands follow the latest of queued large and small plans',
    () async {
      await saveAll();
      final changed = changedText(size: 7);
      final first = downloads.bind(
        fixture.session(),
        books([fixture.audio], padding: 20),
      );
      final second = downloads.bind(fixture.session(), books([fixture.text]));
      final third = downloads.bind(
        fixture.session(),
        books([fixture.audio, changed], padding: 30),
      );
      final lookup = downloads.localFile(changed.files.single);
      final request = downloads.request(fixture.audio);
      await Future.wait([first, second, third, request]);
      expect(await lookup, isNull);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(downloads.status(changed).phase, isNot(DownloadPhase.downloaded));
      downloads.checkInvariants();
    },
  );

  test(
    'switching account does not wait for the old account held restoration',
    () async {
      await saveAll();
      await restart();
      final storage = _Storage()
        ..heldPath = '${directory(fixture.text.files.single)}/record.json';
      final first = storage.run(
        () => downloads.bind(fixture.session(), fixture.books),
      );
      await storage.entered.future;
      final second = storage.run(
        () => downloads.bind(fixture.session(user: 'bob'), fixture.books),
      );
      var finished = false;
      final lookup = downloads.localFile(fixture.text.files.single).then((uri) {
        expect(uri, isNull);
        finished = true;
      });
      try {
        await pumpEventQueue();
        expect(finished, isTrue);
        expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      } finally {
        storage.release();
        await Future.wait([first, second, lookup]);
      }
      downloads.checkInvariants();
    },
  );

  test('disposal during restoration publishes no late notification', () async {
    await saveAll();
    await restart();
    final storage = _Storage()
      ..heldPath = '${directory(fixture.text.files.single)}/record.json';
    final binding = storage.run(
      () => downloads.bind(fixture.session(), fixture.books),
    );
    await storage.entered.future;
    var notices = 0;
    downloads.addListener(() => notices++);
    downloads.dispose();
    storage.release();
    await binding;
    expect(notices, 0);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    await downloads.idle;
    downloads = create();
  });

  test(
    'a removed source keeps its files and reintroduction verifies them again',
    () async {
      await saveAll();
      final path = '${directory(fixture.text.files.single)}/complete';
      await downloads.bind(fixture.session(), books([fixture.audio]));
      expect(await File(path).exists(), isTrue);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      expect(await downloads.retainedStorage(), hasLength(1));
      await File(path).writeAsBytes([6, 5, 4, 3, 2, 1], flush: true);
      await File(path).setLastModified(DateTime.utc(2020));
      await downloads.bind(fixture.session(), fixture.books);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(await File(path).exists(), isTrue);
    },
  );

  test('restoration waits for an accepted read and a later removal waits for restoration', () async {
    await saveAll();
    final started = Completer<void>();
    final release = Completer<void>();
    final reading = downloads.readLocalFile(fixture.text.files.single, (
      _,
    ) async {
      started.complete();
      await release.future;
      return true;
    });
    await started.future;
    final changed = changedText(size: 7);
    final binding = downloads.bind(fixture.session(), books([changed]));
    final removal = downloads.remove(changed);
    release.complete();
    await Future.wait([reading, binding, removal]);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    downloads.checkInvariants();
  });

  test(
    'pending downloads and later cancellation survive an added source',
    () async {
      policy.network = MediaNetwork.disconnected;
      await downloads.bind(fixture.session(), books([fixture.text]));
      await downloads.request(fixture.text);
      final binding = downloads.bind(fixture.session(), fixture.books);
      expect(downloads.status(fixture.text).phase, DownloadPhase.waiting);
      final cancellation = downloads.cancel(fixture.text);
      await Future.wait([binding, cancellation]);
      policy.network = MediaNetwork.wifi;
      await downloads.idle;
      expect(fixture.mediaRequests, isEmpty);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      downloads.checkInvariants();
    },
  );

  test('an unchanged active download survives adding sources without another transfer', () async {
    await downloads.bind(fixture.session(), books([fixture.text]));
    fixture.holdItem = 'text';
    await downloads.request(fixture.text);
    await fixture.firstChunk.future;
    await waitForBytes(downloads, fixture.text, 3);
    final binding = downloads.bind(fixture.session(), fixture.books);
    expect(downloads.status(fixture.text).bytes, 3);
    fixture.release();
    await binding;
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    expect(fixture.mediaRequests, ['text']);
  });
}
