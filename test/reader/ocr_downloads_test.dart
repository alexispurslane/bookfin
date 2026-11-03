import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, MemoryResume;
import 'ocr_test.dart' show englishPage, blankPages;

const _source = SourceFile(
  itemId: 'scan',
  displayName: 'English scan',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'pdf',
  sizeBytes: null,
  isItemOriginal: true,
);
const _edition = Edition(
  id: 'scan-edition',
  kind: EditionKind.text,
  label: 'Scan',
  files: [_source],
  memberIds: ['scan'],
);
const _book = Book(
  id: 'scan-book',
  title: 'English scan',
  author: 'Writer',
  editions: [_edition],
);

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

Future<Directory> _savedScan(
  Directory root,
  String accountKey, {
  List<int>? contents,
}) async {
  const source = _source;
  final bytes =
      contents ??
      await File('tool/research/readers/fixtures/scanned.pdf').readAsBytes();
  final directory = Directory(
    '${root.path}/${_hash(accountKey)}/${_hash(jsonEncode([source.key, source.revision]))}',
  );
  await directory.create(recursive: true);
  await File('${directory.path}/complete').writeAsBytes(bytes);
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
  return directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  test('identical scans in two accounts have separate caches and returning reuses only that account cache', () async {
    final root = await Directory.systemTemp.createTemp('bookfin-account-ocr-');
    final policy = MediaPolicy()..network = MediaNetwork.disconnected;
    final downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 100000000,
      policy: policy,
    );
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (uri, source) =>
          loadReadingDocument(uri, source, textSupply: BundledEnglishText()),
    );
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'recognize') {
            calls++;
            return englishPage;
          }
          return null;
        });
    final alice = account();
    final bob = account(user: 'bob');
    final aliceDirectory = await _savedScan(root, alice.scope.key);
    final bobDirectory = await _savedScan(root, bob.scope.key);
    try {
      for (final session in [alice, bob, alice]) {
        reader.closeView(reader.token);
        await downloads.bind(session, [_book]);
        await reader.bind(session, [_book]);
        await reader.open(_book, _edition);
        expect(reader.message, isNull);
        expect(
          (await (reader.document! as PdfBook).text(1)).text,
          'The quiet garden.',
        );
      }
      expect(calls, 2);
      expect(
        await Directory('${aliceDirectory.path}/.bookfin-ocr').list().length,
        1,
      );
      expect(
        await Directory('${bobDirectory.path}/.bookfin-ocr').list().length,
        1,
      );
    } finally {
      reader.dispose();
      await PdfRuntime.instance.shutdown();
      downloads.dispose();
      await downloads.idle;
      policy.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    }
  });
  test('selected text reuses the live download read while canceled native work drains', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final root = await Directory.systemTemp.createTemp('bookfin-reuse-ocr-');
    final policy = MediaPolicy()..network = MediaNetwork.disconnected;
    final downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 100000000,
      policy: policy,
    );
    await _savedScan(root, account().scope.key, contents: blankPages(3));
    await downloads.bind(account(), [_book]);
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (uri, source) =>
          loadReadingDocument(uri, source, textSupply: BundledEnglishText()),
    );
    final held = Completer<String>();
    final started = Completer<void>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'recognize') return null;
          calls++;
          if (calls == 1) return englishPage;
          if (!started.isCompleted) started.complete();
          return held.future;
        });
    try {
      await reader.bind(account(), [_book]);
      await reader.open(_book, _edition);
      final pdf = reader.document! as PdfBook;
      expect((await pdf.text(1)).text, 'The quiet garden.');
      final pending = pdf.text(2);
      await started.future;
      pdf.textSupply!.cancel();
      try {
        expect(
          (await pdf.text(1).timeout(const Duration(seconds: 3))).text,
          'The quiet garden.',
        );
        expect(calls, 2);
        final removal = downloads.remove(_edition);
        expect(
          (await pdf.text(1).timeout(const Duration(seconds: 3))).status,
          PdfTextStatus.absent,
        );
        held.complete(englishPage);
        await removal;
      } finally {
        if (!held.isCompleted) held.complete(englishPage);
        await pending;
      }
    } finally {
      reader.dispose();
      await PdfRuntime.instance.shutdown();
      downloads.dispose();
      await downloads.idle;
      policy.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      await root.delete(recursive: true);
    }
  });

  for (final change in ['removal', 'account', 'source']) {
    test(
      '$change during recognition revokes publication through the download owner',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final root = await Directory.systemTemp.createTemp(
          'bookfin-owned-ocr-',
        );
        final policy = MediaPolicy()..network = MediaNetwork.disconnected;
        final downloads = LocalDownloads(
          root: root,
          freeBytes: () async => 100000000,
          policy: policy,
        );
        final bytes = await File('tool/research/readers/fixtures/scanned.pdf')
            .readAsBytes();
        final source = SourceFile(
          itemId: 'pdf',
          displayName: 'English scan',
          mediaSourceId: 'original',
          revision: 'one',
          durationMs: null,
          container: 'pdf',
          sizeBytes: bytes.length,
          isItemOriginal: true,
        );
        final edition = Edition(
          id: 'edition',
          kind: EditionKind.text,
          label: 'PDF',
          files: [source],
          memberIds: ['pdf'],
        );
        final book = Book(
          id: 'book',
          title: 'English scan',
          author: 'Writer',
          editions: [edition],
        );
        String hash(String value) =>
            sha256.convert(utf8.encode(value)).toString();
        final directory = Directory(
          '${root.path}/${hash(account().scope.key)}/${hash(jsonEncode([source.key, source.revision]))}',
        );
        await directory.create(recursive: true);
        await File('${directory.path}/complete').writeAsBytes(bytes);
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
        await downloads.bind(account(), [book]);
        final reader = ReaderSession(
          downloads: downloads,
          store: MemoryResume(),
          load: loadPublication,
          loadDocument: (uri, source) => loadReadingDocument(
            uri,
            source,
            textSupply: BundledEnglishText(),
          ),
        );
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        expect(reader.message, isNull);
        final pdf = reader.document! as PdfBook;
        final held = Completer<String>();
        final started = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'recognize') {
                started.complete();
                return held.future;
              }
              return null;
            });
        final pending = pdf.text(1);
        await started.future;
        Future<void> changed;
        if (change == 'removal') {
          changed = downloads.remove(edition);
        } else if (change == 'account') {
          changed = downloads.bind(account(user: 'bob'), [book]);
        } else {
          changed = downloads.bind(account(), []);
        }
        held.complete(englishPage);
        final result = await pending;
        await changed;
        reader.dispose();
        await PdfRuntime.instance.shutdown();
        downloads.dispose();
        await downloads.idle;
        policy.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
        final cached = Directory('${directory.path}/.bookfin-ocr');
        final published =
            await cached.exists() && await cached.list().isEmpty == false;
        await root.delete(recursive: true);
        expect(result.status, PdfTextStatus.absent);
        expect(published, isFalse);
      },
    );
  }
}
