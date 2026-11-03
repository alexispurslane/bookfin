import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;

const edition = Edition(
  id: 'pdf-edition',
  kind: EditionKind.text,
  label: 'PDF',
  files: [pdfSource],
  memberIds: ['pdf'],
);
const book = Book(
  id: 'work',
  title: 'PDF book',
  author: 'Writer',
  editions: [edition],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  test('PDF bookmarks and resume keep source pages through the existing reading owner', () async {
    final downloads = LocalFiles()
      ..files[pdfSource.key] = File('tool/research/readers/fixtures/simple.pdf')
          .absolute
          .uri;
    final store = MemoryResume();
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: loadPublication,
      loadDocument: loadReadingDocument,
    );
    addTearDown(downloads.dispose);
    addTearDown(reader.dispose);
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect(reader.document, isA<PdfBook>());
    reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
    await reader.addBookmark(title: 'Source page two');
    await reader.flush();
    expect(reader.position!.sourceKey, 'pdf:original');
    expect(reader.bookmarks.single.title, 'Source page two');
    reader.closeView(reader.token);
    await reader.open(book, edition);
    expect((reader.initialAddress as PdfAddress).sourcePage, 2);
    reader.checkInvariants();
    await reader.bind(account(user: 'bob'), [book]);
    await reader.open(book, edition);
    expect(reader.initialAddress, isNull);
    expect(reader.bookmarks, isEmpty);
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect((reader.initialAddress as PdfAddress).sourcePage, 2);
    expect(reader.bookmarks.single.title, 'Source page two');
    reader.checkInvariants();
  });
}
