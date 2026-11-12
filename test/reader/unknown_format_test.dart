import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/admitted_books.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../downloads/verified_reads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  final source = buildBooks([
    CatalogEntry.fromJson({
      'Id': 'ordinary-book',
      'Name': 'A book without a filename',
      'Type': 'Book',
    }, libraryId: 'books'),
  ]).single.editions.single.files.single;

  for (final fixture in [
    'simple.pdf',
    'mobi6-plain.mobi',
    'mobi6-palmdoc.mobi',
    'pg11-kf8.mobi',
    'river.epub',
  ]) {
    test(
      'ordinary Book without Container opens $fixture from an extensionless download',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'bookfin-format-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final original = await File('tool/research/readers/fixtures/$fixture')
            .readAsBytes();
        final file = await File('${directory.path}/complete')
            .writeAsBytes(original);
        // The admitted record is written after the book comes back. In the
        // app, Downloads holds the download until then (te-24cn).
        addTearDown(() => AdmittedBooks.written(file));
        expect(source.container, isEmpty);
        expect(source.isItemOriginal, isTrue);
        final document = await loadReadingDocument(verified(file), source);
        addTearDown(document.dispose);
        if (fixture.endsWith('.pdf')) {
          expect(document, isA<PdfBook>());
          expect(
            (await (document as PdfBook).text(1)).text,
            contains('The river'),
          );
        } else {
          expect(document, isA<EpubDocument>());
          expect(document.format, fixture.endsWith('.mobi') ? 'mobi' : 'epub');
          expect((document as EpubDocument).publication.spine, isNotEmpty);
        }
        expect(await file.readAsBytes(), original);
      },
    );
  }

  test('unknown bytes and linked originals remain rejected without format metadata', () async {
    final directory = await Directory.systemTemp.createTemp('bookfin-format-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/complete')
        .writeAsString('not an ebook');
    await expectLater(
      loadReadingDocument(verified(file), source),
      throwsFormatException,
    );
    final link = await Link('${directory.path}/linked').create(file.path);
    await expectLater(
      loadReadingDocument(verified(File(link.path)), source),
      throwsFormatException,
    );
    expect(await file.readAsString(), 'not an ebook');
  });
}
