import 'dart:io';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transfer_test.dart' show MediaFixture;

Never _storage(Object? _, [Object? _, Object? _]) =>
    throw StateError('Download status touched storage.');

/// Runs [read] where any file-system access throws.
T withoutStorage<T>(T Function() read) => IOOverrides.runZoned(
  read,
  createDirectory: _storage,
  createFile: _storage,
  createLink: _storage,
  fseGetType: _storage,
  fseGetTypeSync: _storage,
  fseIdentical: _storage,
  fseIdenticalSync: _storage,
  stat: _storage,
  statSync: _storage,
);

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  late LocalDownloads downloads;

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-status-');
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

  test('status answers from memory without touching storage', () async {
    await downloadText();
    final state = withoutStorage(() => downloads.status(fixture.text));
    expect(state.phase, DownloadPhase.downloaded);
    expect(state.completeFiles, 1);
    expect(state.bytes, 6);
    expect(state.unavailableBytes, 0);
    expect(
      withoutStorage(() => downloads.status(fixture.audio)).phase,
      DownloadPhase.none,
    );
  });

  test('refresh notices an original removed outside the app', () async {
    final file = await downloadText();
    final cache = Directory('${file.parent.path}/.bookfin-mobi/converted');
    await cache.create(recursive: true);
    await File('${cache.path}/book.epub').writeAsBytes([7, 8, 9]);
    await file.delete();
    await downloads.refresh();
    final state = downloads.status(fixture.text);
    expect(state.phase, DownloadPhase.none);
    expect(state.unavailableBytes, 3);
    downloads.checkInvariants();
  });

  test('refresh stays silent when no saved file changed', () async {
    final file = await downloadText();
    await downloads.request(fixture.audio);
    await downloads.cancel(fixture.audio);
    await downloads.idle;
    var notified = 0;
    void count() => notified++;
    downloads.addListener(count);
    addTearDown(() => downloads.removeListener(count));
    await downloads.refresh();
    expect(notified, 0);
    await file.delete();
    await downloads.refresh();
    expect(notified, greaterThan(0));
    expect(downloads.status(fixture.text).phase, DownloadPhase.none);
  });

  test(
    'the invariant checker rejects a status that no longer matches saved files',
    () async {
      final file = await downloadText();
      downloads.checkInvariants();
      await file.delete();
      expect(downloads.checkInvariants, throwsStateError);
      await downloads.refresh();
      downloads.checkInvariants();
    },
  );

  test('removal leaves no saved bytes in the reported status', () async {
    final file = await downloadText();
    final cache = Directory('${file.parent.path}/.bookfin-ocr');
    await cache.create(recursive: true);
    await File('${cache.path}/page').writeAsBytes([7, 8]);
    await downloads.remove(fixture.text);
    final state = downloads.status(fixture.text);
    expect(state.phase, DownloadPhase.none);
    expect(state.bytes, 0);
    expect(state.unavailableBytes, 0);
    downloads.checkInvariants();
  });
}
