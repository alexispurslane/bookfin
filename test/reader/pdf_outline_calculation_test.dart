// These calculations need no file, PDFium initialization or native test fixture.
import 'package:bookfin/reader/pdf_outline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a PDF outline from its pages and bookmarks', () {
    test('in a book that is mostly text, a page without a text layer is a '
        'picture or a blank page and holds no characters', () {
      final outline = pdfOutlineOf(const [1200, 0, 1100], const []);

      expect(outline.parts.map((part) => part.characters), [1200, 0, 1100]);
    });

    test('in a scanned book, where most pages lack a text layer, places '
        'fall by pages: halfway through the book is the start of the third '
        'of four pages', () {
      final outline = pdfOutlineOf(const [0, 0, 0, 0], const []);

      expect(outline.placeAt(outline.length / 2), (part: 2, progress: 0.0));
    });

    test('in a scanned book, a page with a text layer keeps its own '
        'characters', () {
      final outline = pdfOutlineOf(const [0, 0, 0, 900], const []);

      expect(outline.parts.last.characters, 900);
    });

    test('a bookmark starts at its page, after the characters above its '
        'place there', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Two', depth: 0, page: 2, above: 300),
        ],
      );

      expect(
        [for (final entry in outline.entries) (entry.title, entry.start)],
        [('One', 0), ('Two', 1300)],
      );
    });

    test('bookmarks that the outline lists out of page order are entries in '
        'the order of the book', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'Index', depth: 0, page: 2, above: 500),
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Two', depth: 0, page: 2, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), [
        'One',
        'Two',
        'Index',
      ]);
    });

    test('a bookmark without a title names no chapter and is left out', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: ' ', depth: 0, page: 2, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), ['One']);
    });

    test('a bookmark to a page outside the book is left out', () {
      final outline = pdfOutlineOf(
        const [1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Lost', depth: 0, page: 7, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), ['One']);
    });
  });
}
