import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/platform_io.dart';

import '../playback/playback_test.dart' show MemoryResume;

import 'transfer_test.dart' show MediaFixture, waitForBytes;

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-retained-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
    );
    await downloads.bind(fixture.session(), fixture.books);
  });

  tearDown(() async {
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  Future<File> downloadText() async {
    await downloads.request(fixture.text);
    await downloads.idle;
    return File.fromUri(
      (await downloads.localFile(fixture.text.files.single))!,
    );
  }

  test('removing a downloaded book removes its converted copy', () async {
    final file = await downloadText();
    final cache = Directory('${file.parent.path}/.bookfin-mobi/converted');
    await cache.create(recursive: true);
    await File('${cache.path}/book.epub').writeAsBytes([7, 8, 9]);
    await downloads.remove(fixture.text);
    expect(await cache.exists(), isFalse);
    expect(await file.exists(), isFalse);
  });

  test(
    'retained storage counts converted bytes and removes cache-only books',
    () async {
      final file = await downloadText();
      final cache = Directory('${file.parent.path}/.bookfin-mobi/converted');
      await cache.create(recursive: true);
      await File('${cache.path}/book.epub').writeAsBytes([7, 8, 9]);
      await file.delete();
      await downloads.refresh();
      expect(downloads.status(fixture.text).unavailableBytes, 3);
      await downloads.bind(fixture.session(), []);
      final retained = await downloads.retainedStorage();
      expect(retained, hasLength(1));
      expect(retained.single.bytes, 3);
      await downloads.removeRetained(retained.single);
      expect(await cache.exists(), isFalse);
    },
  );

  test('removal waits for a running native MOBI import and no cache can reappear', () async {
    final bytes = await File('tool/research/readers/fixtures/mobi6-plain.mobi')
        .readAsBytes();
    fixture.textSources = [
      {...fixture.source('text'), 'Size': bytes.length, 'Container': 'mobi'},
    ];
    final source = fixture.text.files.single;
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    final directory = Directory(
      '${root.path}/${hash(fixture.session().scope.key)}/${hash(jsonEncode([source.key, source.revision]))}',
    );
    await directory.create(recursive: true);
    final original = await File('${directory.path}/complete')
        .writeAsBytes(bytes);
    await File('${directory.path}/record.json').writeAsString(
      jsonEncode({
        'key': source.key,
        'revision': source.revision,
        'length': bytes.length,
        'digest': sha256.convert(bytes).toString(),
        'complete': true,
        'requested': false,
      }),
    );
    await downloads.bind(fixture.session(), fixture.books);
    expect(await downloads.localFile(source), original.uri);
    final started = Completer<void>();
    final release = Completer<void>();
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (file, source) async {
        started.complete();
        await release.future;
        return loadReadingDocument(file, source);
      },
    );
    addTearDown(() async {
      reader.dispose();
      await reader.flush();
    });
    await reader.bind(fixture.session(), fixture.books);
    final opening = reader.open(fixture.books.single, fixture.text);
    await Future.any([
      started.future,
      opening.then((_) {
        if (!started.isCompleted) {
          throw StateError('Import did not start: ${reader.message}');
        }
      }),
    ]);
    var removed = false;
    final removal = downloads.remove(fixture.text).then((_) => removed = true);
    await Future.any([
      removal,
      Future<void>.delayed(const Duration(milliseconds: 100)),
    ]);
    final removedDuringImport = removed;
    release.complete();
    await opening;
    await removal;
    expect(removedDuringImport, isFalse);
    expect(reader.document?.format, 'mobi', reason: reader.message);
    expect(await original.exists(), isFalse);
    expect(
      await Directory('${original.parent.path}/.bookfin-mobi').exists(),
      isFalse,
    );
    var readAgain = false;
    await downloads.readLocalFile(fixture.text.files.single, (_) async {
      readAgain = true;
    });
    expect(readAgain, isFalse);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
  });

  test(
    'derived storage never counts or removes symbolic-link targets',
    () async {
      final original = await downloadText();
      final outside = await Directory.systemTemp.createTemp(
        'bookfin-cache-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      final target = await File('${outside.path}/private')
          .writeAsBytes([8, 9, 10, 11]);
      final cache = Directory('${original.parent.path}/.bookfin-mobi');
      await cache.create();
      await File('${cache.path}/book.epub').writeAsBytes([7]);
      await Link('${cache.path}/external').create(outside.path);
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      expect(retained.bytes, 7);
      await downloads.removeRetained(retained);
      expect(await target.readAsBytes(), [8, 9, 10, 11]);
      expect(await cache.exists(), isFalse);
    },
  );

  for (final immediateReturn in [false, true]) {
    test(
      'accepted multi-file cancellation survives account switch (immediate return: $immediateReturn)',
      () async {
        policy.network = MediaNetwork.disconnected;
        await downloads.request(fixture.audio);
        Future<void>? switching;
        var switched = false;
        void switchAfterCancellation() {
          if (!switched &&
              downloads.status(fixture.audio).phase == DownloadPhase.none) {
            switched = true;
            switching = downloads.bind(
              fixture.session(user: 'bob'),
              fixture.books,
            );
            if (immediateReturn) {
              switching = downloads.bind(fixture.session(), fixture.books);
            }
          }
        }

        downloads.addListener(switchAfterCancellation);
        await downloads.cancel(fixture.audio);
        downloads.removeListener(switchAfterCancellation);
        expect(switched, isTrue);
        await switching;
        await downloads.bind(fixture.session(), fixture.books);
        expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
        policy.network = MediaNetwork.wifi;
        await downloads.idle;
        expect(fixture.mediaRequests, isEmpty);
        downloads.checkInvariants();
      },
    );
  }

  test(
    'catalog removal retains files without advertising availability',
    () async {
      final file = await downloadText();
      final source = fixture.text.files.single;
      await downloads.bind(fixture.session(), []);
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      expect(await downloads.localFile(source), isNull);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      final retained = await downloads.retainedStorage();
      expect(retained, hasLength(1));
      expect(retained.single.sourceKey, 'text:text');
      expect(retained.single.bytes, 6);
      expect(retained.single.removable, isTrue);
      expect(fixture.mediaRequests, ['text']);
    },
  );

  test(
    'reselection restores verified availability without another transfer',
    () async {
      await downloadText();
      await downloads.bind(fixture.session(), []);
      expect(await downloads.retainedStorage(), hasLength(1));
      await downloads.bind(fixture.session(), fixture.books);
      expect(await downloads.retainedStorage(), isEmpty);
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(await downloads.localFile(fixture.text.files.single), isNotNull);
      expect(fixture.mediaRequests, ['text']);
      downloads.checkInvariants();
    },
  );

  test(
    'retained inventory belongs only to the current server and user',
    () async {
      await downloadText();
      await downloads.bind(fixture.session(), []);
      final alice = (await downloads.retainedStorage()).single;
      await downloads.bind(fixture.session(user: 'bob'), []);
      expect(await downloads.retainedStorage(), isEmpty);
      await expectLater(
        downloads.removeRetained(alice),
        throwsA(isA<Exception>()),
      );
      fixture.serverId = 'other-server';
      await downloads.bind(fixture.session(), []);
      expect(await downloads.retainedStorage(), isEmpty);
      await downloads.bind(null, []);
      expect(await downloads.retainedStorage(), isEmpty);
      fixture.serverId = 'fixture-server';
      await downloads.bind(fixture.session(), []);
      expect(await downloads.retainedStorage(), hasLength(1));
      await expectLater(
        downloads.removeRetained(alice),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('explicit removal deletes only identified downloader files', () async {
    final file = await downloadText();
    final unrelated = await File('${file.parent.path}/notes.txt')
        .writeAsString('keep');
    await downloads.bind(fixture.session(), []);
    final retained = (await downloads.retainedStorage()).single;
    await downloads.removeRetained(retained);
    expect(await file.exists(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
    expect(await downloads.retainedStorage(), isEmpty);
    await downloads.bind(fixture.session(), fixture.books);
    expect(downloads.status(fixture.text).phase, DownloadPhase.none);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
  });

  test('retained removal survives restart and reselection without transferring again', () async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), []);
    await downloads.removeRetained((await downloads.retainedStorage()).single);
    downloads.dispose();
    await downloads.idle;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
    );
    await downloads.bind(fixture.session(), []);
    expect(await downloads.retainedStorage(), isEmpty);
    expect(await file.exists(), isFalse);
    await downloads.bind(fixture.session(), fixture.books);
    await downloads.idle;
    expect(downloads.status(fixture.text).phase, DownloadPhase.none);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    expect(fixture.mediaRequests, ['text']);
    downloads.checkInvariants();
  });

  test('retained removal tolerates a saved file disappearing after confirmation opens', () async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), []);
    final retained = (await downloads.retainedStorage()).single;
    await file.delete();
    await downloads.removeRetained(retained);
    expect(await downloads.retainedStorage(), isEmpty);
    expect(await File('${file.parent.path}/record.json').exists(), isFalse);
    await downloads.bind(fixture.session(), fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    expect(downloads.status(fixture.text).phase, DownloadPhase.none);
    expect(fixture.mediaRequests, ['text']);
    downloads.checkInvariants();
  });

  test('removing one account copy preserves another account copy of the same source', () async {
    final aliceFile = await downloadText();
    fixture.authenticatedUser = 'bob';
    await downloads.bind(fixture.session(user: 'bob'), fixture.books);
    final bobFile = await downloadText();
    expect(bobFile.path, isNot(aliceFile.path));
    await downloads.bind(fixture.session(user: 'bob'), []);
    await downloads.removeRetained((await downloads.retainedStorage()).single);
    expect(await bobFile.exists(), isFalse);
    expect(await aliceFile.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    await downloads.bind(fixture.session(), []);
    expect(await downloads.retainedStorage(), hasLength(1));
  });

  test('another server address cannot see retained files with the same server and user identifiers', () async {
    final file = await downloadText();
    final session = fixture.session();
    await downloads.bind(
      JellyfinSession(
        scope: AccountScope(
          server: Uri.parse('http://127.0.0.1:1/jellyfin'),
          serverId: session.scope.serverId,
          userId: session.scope.userId,
        ),
        token: session.token,
        username: session.username,
        canDownload: true,
      ),
      [],
    );
    expect(await downloads.retainedStorage(), isEmpty);
    expect(await file.exists(), isTrue);
  });

  test(
    'a source reselected during confirmation cannot be removed as retained',
    () async {
      final file = await downloadText();
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      await downloads.bind(fixture.session(), fixture.books);
      await expectLater(
        downloads.removeRetained(retained),
        throwsA(isA<Exception>()),
      );
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'old revisions are separate retained storage, not current availability',
    () async {
      final file = await downloadText();
      fixture.revision = 'source-v2';
      await downloads.bind(fixture.session(), fixture.books);
      final retained = (await downloads.retainedStorage()).single;
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      await downloads.request(fixture.text);
      await downloads.idle;
      final current = await downloads.localFile(fixture.text.files.single);
      await downloads.removeRetained(retained);
      expect(await file.exists(), isFalse);
      expect(await File.fromUri(current!).exists(), isTrue);
      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    },
  );

  for (final invalid in [
    'not json',
    '{"key":"other","revision":"wrong"}',
    '[]',
  ]) {
    test(
      'ambiguous metadata stays visible but cannot authorize removal: $invalid',
      () async {
        final file = await downloadText();
        await File('${file.parent.path}/record.json').writeAsString(invalid);
        await downloads.bind(fixture.session(), []);
        final retained = (await downloads.retainedStorage()).single;
        expect(retained.bytes, 6);
        expect(retained.removable, isFalse);
        await expectLater(
          downloads.removeRetained(retained),
          throwsA(isA<Exception>()),
        );
        expect(await file.exists(), isTrue);
      },
    );
  }

  test(
    'removal rechecks metadata instead of trusting an earlier inventory',
    () async {
      final file = await downloadText();
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      await File('${file.parent.path}/record.json').writeAsString('{}');
      await expectLater(
        downloads.removeRetained(retained),
        throwsA(isA<Exception>()),
      );
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'inventory restoration never resumes transfers outside the catalog',
    () async {
      fixture.interruptOnce = true;
      await downloads.request(fixture.text);
      await downloads.idle;
      await downloads.bind(fixture.session(), []);
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => 1000000,
        policy: policy,
      );
      final restoring = downloads.bind(fixture.session(), []);
      final inventory = downloads.retainedStorage();
      await restoring;
      expect((await inventory).single.bytes, 3);
      await downloads.idle;
      expect(fixture.mediaRequests, ['text']);
      downloads.checkInvariants();
    },
  );

  test(
    'a symlinked retained directory never exposes or deletes its target',
    () async {
      final file = await downloadText();
      final outside = await Directory.systemTemp.createTemp('bookfin-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final target = await File('${outside.path}/complete')
          .writeAsString('outside');
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      await file.parent.delete(recursive: true);
      await Link(file.parent.path).create(outside.path);
      expect(await downloads.retainedStorage(), isEmpty);
      await expectLater(
        downloads.removeRetained(retained),
        throwsA(isA<Exception>()),
      );
      expect(await target.readAsString(), 'outside');
    },
  );

  test('foreign and forged record paths do not authorize traversal', () async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), []);
    final retained = (await downloads.retainedStorage()).single;
    final forged = RetainedDownload(
      accountKey: retained.accountKey,
      binding: retained.binding,
      id: '../${retained.id}',
      sourceKey: retained.sourceKey,
      revision: retained.revision,
      bytes: 6,
    );
    await expectLater(
      downloads.removeRetained(forged),
      throwsA(isA<Exception>()),
    );
    expect(await file.exists(), isTrue);
    final wrong = sha256
        .convert(utf8.encode(jsonEncode(['other:key', 'v1'])))
        .toString();
    final directory = await Directory('${file.parent.parent.path}/$wrong')
        .create();
    await File('${directory.path}/record.json').writeAsString(
      await File('${file.parent.path}/record.json').readAsString(),
    );
    await File('${directory.path}/complete').writeAsString('unknown');
    final entries = await downloads.retainedStorage();
    expect(entries.where((entry) => entry.removable), hasLength(1));
    expect(entries.where((entry) => !entry.removable), hasLength(1));
  });

  test(
    'deselection stops an in-flight transfer before explicit removal',
    () async {
      fixture.holdItem = 'text';
      await downloads.request(fixture.text);
      await fixture.firstChunk.future;
      await waitForBytes(downloads, fixture.text, 3);
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      expect(retained.bytes, 3);
      await downloads.removeRetained(retained);
      fixture.release();
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.idle;
      expect(downloads.status(fixture.text).phase, DownloadPhase.none);
      expect(fixture.mediaRequests, ['text']);
      downloads.checkInvariants();
    },
  );

  test(
    'an account switch invalidates an inventory already being read',
    () async {
      final file = await downloadText();
      await downloads.bind(fixture.session(), []);
      final reading = downloads.retainedStorage();
      final switching = downloads.bind(fixture.session(user: 'bob'), []);
      expect(await reading, isEmpty);
      await switching;
      expect(await downloads.retainedStorage(), isEmpty);
      expect(await file.exists(), isTrue);
    },
  );

  test('restoration to another account cannot act on a held removal', () async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), []);
    final retained = (await downloads.retainedStorage()).single;
    final switching = downloads.bind(fixture.session(user: 'bob'), []);
    await expectLater(
      downloads.removeRetained(retained),
      throwsA(isA<Exception>()),
    );
    await switching;
    expect(await file.exists(), isTrue);
  });

  for (final metadata in ['missing', 'directory', 'symlink', 'oversized']) {
    test('$metadata metadata cannot establish ownership for removal', () async {
      final file = await downloadText();
      final manifest = File('${file.parent.path}/record.json');
      final original = await manifest.readAsString();
      await manifest.delete();
      if (metadata == 'directory') await Directory(manifest.path).create();
      if (metadata == 'symlink') {
        final unrelated = await File('${root.path}/unrelated.json')
            .writeAsString(original);
        await Link(manifest.path).create(unrelated.path);
      }
      if (metadata == 'oversized') {
        await manifest.writeAsString(original.padRight(65537));
      }
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      expect(retained.removable, isFalse);
      await expectLater(
        downloads.removeRetained(retained),
        throwsA(isA<Exception>()),
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    });
  }

  test(
    'a symlinked account directory cannot expose or remove any files',
    () async {
      final file = await downloadText();
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      final account = file.parent.parent;
      final moved = await account.rename('${root.path}/unrelated-account');
      await Link(account.path).create(moved.path);
      await expectLater(downloads.retainedStorage(), throwsA(isA<Exception>()));
      await expectLater(
        downloads.removeRetained(retained),
        throwsA(isA<Exception>()),
      );
      final actual = File('${moved.path}/${retained.id}/complete');
      expect(await actual.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    },
  );

  test(
    'retained removal never follows or deletes a linked media file',
    () async {
      final file = await downloadText();
      await downloads.bind(fixture.session(), []);
      final retained = (await downloads.retainedStorage()).single;
      final unrelated = await File('${root.path}/unrelated-media')
          .writeAsString('keep');
      await file.delete();
      final link = await Link(file.path).create(unrelated.path);
      await downloads.removeRetained(retained);
      expect(await unrelated.readAsString(), 'keep');
      expect(await link.exists(), isTrue);
    },
  );

  test(
    'verified lookup refuses a source directory replaced with a symlink',
    () async {
      final file = await downloadText();
      final moved = await file.parent.rename('${root.path}/unrelated-source');
      await Link(file.parent.path).create(moved.path);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
      expect(
        downloads.status(fixture.text).phase,
        isNot(DownloadPhase.downloaded),
      );
      expect(await File('${moved.path}/complete').readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    },
  );

  test('a corrupt retained copy is not playable after reselection', () async {
    final file = await downloadText();
    await downloads.bind(fixture.session(), []);
    await file.writeAsBytes([6, 5, 4, 3, 2, 1]);
    expect((await downloads.retainedStorage()).single.bytes, 6);
    await downloads.bind(fixture.session(), fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    expect(
      downloads.status(fixture.text).phase,
      isNot(DownloadPhase.downloaded),
    );
    expect(fixture.mediaRequests, ['text']);
  });
}
