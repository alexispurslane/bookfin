import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
    await pdfrxInitialize();
  });

  test(
    'EPUB chapters and local images coexist with the pinned PDF engine',
    () async {
      final book = await EpubReader.readBook(
        File('../fixtures/river.epub').readAsBytesSync(),
      );
      final document = await PdfDocument.openFile('../fixtures/simple.pdf');
      try {
        expect(book.Schema!.Package!.Spine!.Items!.length, 1);
        expect(
          book.Content!.Html!['chapter.xhtml']!.Content,
          contains('The river follows the old road.'),
        );
        expect(book.Content!.Images!['dot.png']!.Content, isNotEmpty);
        expect(
          (await document.pages[1].loadText())!.fullText,
          contains('River chapter 2'),
        );
      } finally {
        await document.dispose();
      }
    },
  );

  test('EPUB cover bytes decode through the new image dependency', () async {
    final archive = ZipDecoder().decodeBytes(
      File('../_out/mobi6-plain.epub').readAsBytesSync(),
    );
    final original = archive.findFile('OEBPS/content.opf')!;
    final metadata = utf8
        .decode(original.content)
        .replaceFirst(
          '</metadata>',
          '<meta name="cover" content="resource00000"/></metadata>',
        );
    archive.addFile(
      ArchiveFile(
        'OEBPS/content.opf',
        utf8.encode(metadata).length,
        utf8.encode(metadata),
      ),
    );
    final book = await EpubReader.openBook(ZipEncoder().encode(archive));
    final cover = await book.readCover();
    expect(cover!.width, 24);
    expect(cover.height, 24);
  });

  for (final name in ['mobi6-plain', 'mobi6-palmdoc', 'alice']) {
    test('$name conversion retains text and an embedded image', () async {
      final book = await EpubReader.readBook(
        File('../_out/$name.epub').readAsBytesSync(),
      );
      expect(
        book.Content!.Html!.values.map((file) => file.Content).join(),
        contains(name == 'alice' ? 'Alice' : 'The river follows the old road.'),
      );
      expect(book.Content!.Images!.values.first.Content, isNotEmpty);
    });
  }
}
