import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transfer_test.dart' show MediaFixture;

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;

  /// A library of [count] audio sources that nothing saved, beside the
  /// fixture's books.
  List<Book> library(int count) => [
    ...fixture.books,
    Book(
      id: 'large',
      title: 'Large',
      author: 'Fixture Author',
      editions: [
        Edition(
          id: 'large',
          kind: EditionKind.audio,
          label: 'Recording',
          memberIds: ['large'],
          files: [
            for (var file = 0; file < count; file++)
              SourceFile(
                itemId: 'large-$file',
                displayName: 'Part $file',
                mediaSourceId: 'large-$file',
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

  Directory account() =>
      Directory('${root.path}/${_hash(fixture.session().scope.key)}');

  Directory sourceDirectory(SourceFile source) => Directory(
    '${account().path}/${_hash(jsonEncode([source.key, source.revision]))}',
  );

  /// The paths of the source directories under the signed-in account.
  Future<List<String>> sourceDirectories() async {
    if (!await account().exists()) return const [];
    return [
      await for (final entity in account().list(followLinks: false))
        if (entity is Directory) entity.path,
    ];
  }

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-directories-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
    );
  });

  tearDown(() async {
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  group('a source directory exists only for a source that saved something', () {
    test(
      'a bind of a library of 1,000 sources creates no source directory',
      () async {
        await downloads.bind(fixture.session(), library(1000));
        await downloads.idle;
        expect(await sourceDirectories(), isEmpty);
        downloads.checkInvariants();
      },
    );

    test('a download creates only the directory of its own source', () async {
      await downloads.bind(fixture.session(), library(1000));
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(await sourceDirectories(), [
        sourceDirectory(fixture.text.files.single).path,
      ]);
      downloads.checkInvariants();
    });

    test('a request without a network keeps its directory for later', () async {
      policy.network = MediaNetwork.disconnected;
      await downloads.bind(fixture.session(), library(20));
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.waiting);
      expect(await sourceDirectories(), [
        sourceDirectory(fixture.text.files.single).path,
      ]);
    });
  });

  group('a missing directory reads as nothing saved', () {
    setUp(() => downloads.bind(fixture.session(), library(20)));

    test('status and lookup find nothing and create no directory', () async {
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      expect(downloads.status(fixture.audio).bytes, 0);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      expect(
        await downloads.readLocalFile<int>(
          fixture.text.files.single,
          (_) async => fail('Nothing is saved to read.'),
        ),
        isNull,
      );
      await downloads.refresh();
      expect(await sourceDirectories(), isEmpty);
      downloads.checkInvariants();
    });

    test('the leftover inventory is empty and reports no error', () async {
      await downloads.bind(fixture.session(), []);
      expect(await downloads.retainedStorage(), isEmpty);
      final leftovers = downloads.leftovers;
      await downloads.reloadLeftovers();
      expect(leftovers.value.entries, isEmpty);
      expect(leftovers.value.error, isNull);
      expect(await sourceDirectories(), isEmpty);
    });

    test('an account that never saved anything has empty leftovers', () async {
      await downloads.bind(fixture.session(user: 'bob'), []);
      expect(await downloads.retainedStorage(), isEmpty);
      expect(await root.list().isEmpty, isTrue);
    });

    test(
      'removing an edition that saved nothing creates no directory',
      () async {
        await downloads.remove(fixture.text);
        await downloads.cancel(fixture.audio);
        expect(downloads.status(fixture.text).phase, DownloadPhase.none);
        expect(await sourceDirectories(), isEmpty);
        downloads.checkInvariants();
      },
    );
  });

  group('removal leaves no empty directory', () {
    setUp(() => downloads.bind(fixture.session(), fixture.books));

    test('removing a downloaded edition removes its directory', () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      await downloads.remove(fixture.text);
      expect(await sourceDirectories(), isEmpty);
      await downloads.request(fixture.text);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    });

    test('removing a leftover download removes its directory', () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      await downloads.removeRetained(retained);
      expect(await sourceDirectories(), isEmpty);
    });

    test('a directory that holds a file nobody saved stays', () async {
      await downloads.request(fixture.text);
      await downloads.idle;
      final note = await File(
        '${sourceDirectory(fixture.text.files.single).path}/note.txt',
      ).writeAsString('keep');
      await downloads.remove(fixture.text);
      expect(await note.readAsString(), 'keep');
    });
  });

  group('directories that an earlier version created', () {
    test('restoration removes an empty source directory', () async {
      final bound = await sourceDirectory(fixture.text.files.single)
          .create(recursive: true);
      final unbound = await Directory(
        '${account().path}/${_hash(jsonEncode(['gone:key', 'v1']))}',
      ).create(recursive: true);
      await downloads.bind(fixture.session(), library(20));
      await downloads.idle;
      expect(await bound.exists(), isFalse);
      expect(await unbound.exists(), isFalse);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
    });

    test('restoration keeps every directory that holds something', () async {
      final noted = await sourceDirectory(fixture.audio.files.first)
          .create(recursive: true);
      final note = await File('${noted.path}/note.txt').writeAsString('keep');
      final derived = await Directory(
        '${sourceDirectory(fixture.audio.files.last).path}/.bookfin-ocr',
      ).create(recursive: true);
      final other = await Directory('${account().path}/not-a-source').create();
      await downloads.bind(fixture.session(), library(20));
      await downloads.idle;
      expect(await note.readAsString(), 'keep');
      expect(await derived.exists(), isTrue);
      expect(await other.exists(), isTrue);
      expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
    });

    test('restoration through a linked account reports storage and removes nothing', () async {
      final outside = await Directory.systemTemp.createTemp('bookfin-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final target = await Directory(
        '${outside.path}/${_hash(jsonEncode([fixture.text.files.single.key, fixture.text.files.single.revision]))}',
      ).create();
      await Link(account().path).create(outside.path);
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.idle;
      expect(await target.exists(), isTrue);
      expect(downloads.status(fixture.text).phase, DownloadPhase.failed);
    });

    test('a saved download in an existing directory still restores', () async {
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.request(fixture.text);
      await downloads.idle;
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => 1000000,
        policy: policy,
      );
      await downloads.bind(fixture.session(), library(20));
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(await downloads.localFile(fixture.text.files.single), isNotNull);
      expect(fixture.mediaRequests, ['text']);
    });
  });
}
