import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:test/test.dart';

void main() {
  for (final entry in {
    'generated EPUB': '../fixtures/river.epub',
    'plain MOBI conversion': '../_out/mobi6-plain.epub',
    'PalmDOC MOBI conversion': '../_out/mobi6-palmdoc.epub',
    'KF8 conversion': '../_out/alice.epub',
  }.entries) {
    test('${entry.key} exposes chapter text and embedded images', () async {
      final book = await EpubReader.readBook(
        File(entry.value).readAsBytesSync(),
      );
      expect(book.Content!.Html!.values, isNotEmpty);
      final chapterText = book.Content!.Html!.values
          .map((chapter) => chapter.Content)
          .join('\n');
      expect(
        chapterText,
        contains(
          entry.key == 'KF8 conversion'
              ? 'Alice'
              : 'The river follows the old road.',
        ),
      );
      expect(book.Content!.Images!.values, isNotEmpty);
      expect(book.Content!.Images!.values.first.Content, isNotEmpty);
    });
  }
}
