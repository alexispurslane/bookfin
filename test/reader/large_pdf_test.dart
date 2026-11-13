// The 64 MiB limit of Publication.maxArchiveBytes protects the memory of
// the isolate that loads an EPUB or a MOBI whole. PDFium reads a PDF from
// its path, so a PDF has no such limit (boo-3q1m). Scanned books are often
// larger than 64 MiB.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

SourceFile sourceOf(String container) => SourceFile(
  itemId: 'book',
  displayName: 'book.$container',
  mediaSourceId: 'original',
  revision: 'r1',
  durationMs: null,
  container: container,
  sizeBytes: Publication.maxArchiveBytes + 1,
);

/// A valid copy of the PDF [small] at [path] that is larger than the EPUB
/// limit: the original, then a hole of zero bytes (white space to a PDF
/// reader), then an incremental update that changes no object.
Future<File> grownPdf(File small, String path) async {
  final original = await small.readAsBytes();
  final tail = latin1.decode(original.sublist(original.length - 512));
  final previous = RegExp(r'startxref\s+(\d+)').allMatches(tail).last[1];
  final root = RegExp(r'/Root (\d+ \d+ R)').firstMatch(tail)![1];
  final size = RegExp(r'/Size (\d+)').firstMatch(tail)![1];
  final file = File(path);
  final output = await file.open(mode: FileMode.write);
  try {
    await output.writeFrom(original);
    await output.truncate(Publication.maxArchiveBytes + 1);
    await output.setPosition(Publication.maxArchiveBytes + 1);
    final update = Publication.maxArchiveBytes + 2;
    await output.writeString(
      '\nxref\n0 0\ntrailer\n'
      '<< /Size $size /Root $root /Prev $previous >>\n'
      'startxref\n$update\n%%EOF\n',
    );
  } finally {
    await output.close();
  }
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookfin-large-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('a PDF larger than 64 MiB opens and gives its text', () async {
    final file = await grownPdf(
      File('tool/research/readers/fixtures/simple.pdf'),
      '${directory.path}/complete',
    );
    expect(await file.length(), greaterThan(Publication.maxArchiveBytes));

    final document = await loadReadingDocument(
      VerifiedFile(file.uri, 'd' * 64),
      sourceOf('pdf'),
    );
    addTearDown(document.dispose);

    expect(document, isA<PdfBook>());
    expect((await (document as PdfBook).text(1)).text, contains('The river'));
  });

  test('a PDF larger than 64 MiB needs no preparation after its download',
      () async {
    final file = await grownPdf(
      File('tool/research/readers/fixtures/simple.pdf'),
      '${directory.path}/complete',
    );

    await expectLater(
      prepareDownloadedBook(VerifiedFile(file.uri, 'd' * 64), sourceOf('pdf')),
      completes,
    );
  });

  test('an EPUB larger than 64 MiB is refused, and its download is kept',
      () async {
    final file = File('${directory.path}/complete');
    final output = await file.open(mode: FileMode.write);
    await output.writeFrom(
      await File('tool/research/readers/fixtures/river.epub').readAsBytes(),
    );
    await output.truncate(Publication.maxArchiveBytes + 1);
    await output.close();

    await expectLater(
      loadReadingDocument(VerifiedFile(file.uri, 'e' * 64), sourceOf('epub')),
      throwsFormatException,
    );
    expect(await file.length(), Publication.maxArchiveBytes + 1);
  });
}
