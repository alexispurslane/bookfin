import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, MemoryResume;
import 'ocr_test.dart' show blankPages, englishPage;

const pdfSource = SourceFile(
  itemId: 'pdf',
  displayName: 'Scan',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'pdf',
  sizeBytes: null,
  isItemOriginal: true,
);
const edition = Edition(
  id: 'pdf-edition',
  kind: EditionKind.text,
  label: 'PDF',
  files: [pdfSource],
  memberIds: ['pdf'],
);
const book = Book(
  id: 'work',
  title: 'Scan',
  author: 'Writer',
  editions: [edition],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late File original;
  late LocalDownloads downloads;
  late MediaPolicy policy;
  late ReaderSession reader;
  late PdfBook pdf;
  late Completer<void> nativeStarted;
  late Completer<String> nativeResult;
  var calls = 0;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    root = await Directory.systemTemp.createTemp('bookfin-read-lifetime-');
    policy = MediaPolicy()..network = MediaNetwork.disconnected;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 100000000,
      policy: policy,
    );
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    final directory = Directory(
      '${root.path}/${hash(account().scope.key)}/${hash(jsonEncode([pdfSource.key, pdfSource.revision]))}',
    );
    await directory.create(recursive: true);
    final bytes = blankPages(3);
    original = await File('${directory.path}/complete').writeAsBytes(bytes);
    await File('${directory.path}/record.json').writeAsString(
      jsonEncode({
        'key': pdfSource.key,
        'revision': pdfSource.revision,
        'length': bytes.length,
        'digest': sha256.convert(bytes).toString(),
        'complete': true,
        'requested': false,
      }),
    );
    await downloads.bind(account(), [book]);
    reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (file, source) =>
          loadReadingDocument(file, source, textSupply: BundledEnglishText()),
    );
    nativeStarted = Completer<void>();
    nativeResult = Completer<String>();
    calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'recognize') return null;
          calls++;
          if (calls == 1) return englishPage;
          if (!nativeStarted.isCompleted) nativeStarted.complete();
          return nativeResult.future;
        });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect(reader.message, isNull);
    pdf = reader.document! as PdfBook;
    expect((await pdf.text(1)).text, 'The quiet garden.');
  });

  tearDown(() async {
    if (!nativeResult.isCompleted) nativeResult.complete(englishPage);
    reader.dispose();
    await PdfRuntime.instance.shutdown();
    downloads.dispose();
    await downloads.idle;
    policy.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  test(
    'failed shared acquisition settles all users and allows a later retry',
    () async {
      final failure = Completer<void>();
      pdf.textSupply!.bind((read) async {
        await failure.future;
        throw const FileSystemException('Owned read unavailable');
      });
      const absent = PdfText(
        source: '',
        text: '',
        sourceOffsets: [],
        status: PdfTextStatus.absent,
      );
      final first = pdf.textSupply!.text(pdf, 1, absent);
      final second = pdf.textSupply!.text(pdf, 1, absent);
      failure.complete();
      for (final result in await Future.wait([first, second])) {
        expect(result.status, PdfTextStatus.failed);
      }
      pdf.textSupply!.bind((read) async {
        bool Function() owned = () => false;
        return downloads.readLocalFile<PdfText>(
          pdfSource,
          (file) => read(file, owned),
          onOwnership: (live) => owned = live,
        );
      });
      expect((await pdf.text(1)).text, 'The quiet garden.');
      expect(calls, 1);
      (pdf.textSupply! as BundledEnglishText).checkInvariants();
    },
  );

  test('selected text joins a read still acquiring ownership before recognition starts', () async {
    final acquiring = Completer<void>();
    final acquired = Completer<void>();
    var reads = 0;
    pdf.textSupply!.bind((read) async {
      bool Function() owned = () => false;
      return downloads.readLocalFile<PdfText>(pdfSource, (file) async {
        if (++reads == 1) {
          acquiring.complete();
          await acquired.future;
        }
        return read(file, owned);
      }, onOwnership: (live) => owned = live);
    });
    final second = pdf.text(2);
    try {
      await acquiring.future.timeout(const Duration(seconds: 5));
      final first = pdf.text(1);
      // Give the request a chance to enter read acquisition before releasing it.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      acquired.complete();
      await nativeStarted.future.timeout(const Duration(seconds: 5));
      expect(
        (await first.timeout(const Duration(seconds: 3))).text,
        'The quiet garden.',
      );
      expect(calls, 2);
    } finally {
      if (!acquired.isCompleted) acquired.complete();
      if (!nativeResult.isCompleted) nativeResult.complete(englishPage);
      await second;
    }
  });

  test('ordinary native failure does not expire selected text while its cache read waits', () async {
    final second = pdf.text(2);
    await nativeStarted.future;
    final reading = Completer<void>();
    final release = Completer<void>();
    final parent = Zone.current;
    // The download lookup runs outside the zone that holds the type query of
    // the original, so only the cache read of page 1 waits.
    pdf.textSupply!.bind(
      (read) => parent.run(() {
        bool Function() owned = () => false;
        return downloads.readLocalFile<PdfText>(
          pdfSource,
          (file) => read(file, () => owned()),
          onOwnership: (live) => owned = live,
        );
      }),
    );
    final first = IOOverrides.runZoned(
      () => pdf.text(1),
      fseGetType: (path, followLinks) async {
        if (path == original.path) {
          if (!reading.isCompleted) reading.complete();
          await release.future;
        }
        return parent.run(
          () => FileSystemEntity.type(path, followLinks: followLinks),
        );
      },
    );
    try {
      await reading.future.timeout(const Duration(seconds: 5));
      nativeResult.completeError(PlatformException(code: 'recognition'));
      expect((await second).status, PdfTextStatus.failed);
      release.complete();
      expect((await first).text, 'The quiet garden.');
      expect(calls, 2);
    } finally {
      if (!release.isCompleted) release.complete();
      await first;
    }
  });
}
