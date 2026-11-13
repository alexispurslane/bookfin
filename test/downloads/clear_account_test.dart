import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transfer_test.dart' show MediaFixture, waitForBytes;

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;
  late JellyfinSession session;
  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('clear-downloads-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
    );
    session = fixture.session();
    await downloads.bind(session, fixture.books);
  });
  tearDown(() async {
    fixture.release();
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });
  Future<File> saveText() async {
    await downloads.request(fixture.text);
    await downloads.idle;
    return File.fromUri(
      (await downloads.localFile(fixture.text.files.single))!,
    );
  }

  test('clear removes current and retained versions with derived files but keeps another account', () async {
    final first = await saveText();
    final derived = File(
      '${first.parent.path}/.bookfin-mobi/example/book.epub',
    );
    await derived.parent.create(recursive: true);
    await derived.writeAsString('derived');
    fixture.revision = 'v2';
    await downloads.bind(session, fixture.books);
    final second = await saveText();
    await downloads.bind(fixture.session(user: 'bob'), fixture.books);
    fixture.authenticatedUser = 'bob';
    final bob = await saveText();
    await downloads.bind(session, []); // All of Alice's versions are retained.
    await downloads.clearAccount(session);
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isFalse);
    expect(await derived.exists(), isFalse);
    expect(await bob.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    await downloads.bind(session, fixture.books);
    expect(await downloads.localFile(fixture.text.files.single), isNull);
    expect(await downloads.retainedStorage(), isEmpty);
  });

  test('clear removes retained manifests even when their media file is empty or missing', () async {
    final file = await saveText();
    await file.delete();
    await downloads.refresh();
    await downloads.bind(session, []);
    await downloads.clearAccount(session);
    expect(await File('${file.parent.path}/record.json').exists(), isFalse);
  });

  test('clear stays pending while a read holds the file', () async {
    final file = await saveText();
    final release = Completer<void>();
    Future<void>? held;
    await downloads.readLocalFile(fixture.text.files.single, (original) async {
      held = original.hold(() => release.future);
    });
    var cleared = false;
    final clearing = downloads
        .clearAccount(session)
        .then((_) => cleared = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(cleared, isFalse);
      expect(await file.exists(), isTrue);
    } finally {
      release.complete();
      await held;
      await clearing;
    }
    expect(await file.exists(), isFalse);
  });

  test(
    'clear stops an active transfer before removing its partial files',
    () async {
      fixture.holdItem = 'audio1';
      await downloads.request(fixture.audio);
      await waitForBytes(downloads, fixture.audio, 3);
      await downloads.clearAccount(session);
      fixture.release();
      await downloads.idle;
      expect(downloads.status(fixture.audio).phase, DownloadPhase.none);
      final files = await root
          .list(recursive: true)
          .where((file) => file is File)
          .toList();
      expect(files, isEmpty);
    },
  );

  for (final replacement in [false, true]) {
    test(
      '${replacement ? 'credential replacement' : 'account change'} while waiting for a read aborts clear',
      () async {
        final file = await saveText();
        final release = Completer<void>();
        await downloads.readLocalFile(fixture.text.files.single, (
          original,
        ) async {
          unawaited(original.hold(() => release.future));
        });
        final clearing = downloads.clearAccount(session);
        final outcome = expectLater(clearing, throwsA(isA<Exception>()));
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final binding = downloads.bind(
          fixture.session(user: replacement ? 'alice' : 'bob'),
          fixture.books,
        );
        release.complete();
        await outcome;
        await binding;
        expect(await file.exists(), isTrue);
      },
    );
  }
}
