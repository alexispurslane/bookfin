// Tool code: the committed corpus list keeps its rules, so that the fetch
// script and the on-demand corpus run can rely on them.
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';
import 'list.dart';

void main() {
  final books = corpusList();

  test('the list holds 50 to 100 books, each with its own id', () {
    expect(books.length, inInclusiveRange(50, 100));
    expect({for (final book in books) book.id}, hasLength(books.length));
  });

  test('every book pins its SHA-256 and its size', () {
    for (final book in books) {
      expect(book.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: book.id);
      expect(book.bytes, isNotNull, reason: book.id);
      // Publication.maxArchiveBytes: Bookfin admits no larger book.
      expect(
        book.bytes,
        inInclusiveRange(1, 64 * 1024 * 1024),
        reason: book.id,
      );
    }
  });

  test('every download comes over HTTPS from Standard Ebooks or Gutenberg', () {
    for (final book in books.where((book) => book.url != null)) {
      final host = switch (book.source) {
        'standard-ebooks' => 'standardebooks.org',
        'gutenberg' => 'www.gutenberg.org',
        _ => null,
      };
      final url = Uri.parse(book.url!);
      expect(url.scheme, 'https', reason: book.id);
      expect(url.host, host, reason: book.id);
    }
  });

  test('every book is an EPUB or a Kindle file and says why it is in', () {
    for (final book in books) {
      expect(book.format, anyOf('epub', 'azw3'), reason: book.id);
      expect(book.why, isNotEmpty, reason: book.id);
    }
  });

  test('the list mixes Standard Ebooks, Gutenberg EPUBs and Kindle files', () {
    int count(String source, String format) => books
        .where((book) => book.source == source && book.format == format)
        .length;
    expect(count('standard-ebooks', 'epub'), greaterThanOrEqualTo(30));
    expect(count('gutenberg', 'epub'), greaterThanOrEqualTo(30));
    expect(count('gutenberg', 'azw3'), greaterThanOrEqualTo(5));
  });

  test('each showcase book pins the bytes that the tests make', () {
    final made = showcaseBooks();
    final listed = books.where((book) => book.source == 'bookfin-showcase');
    expect({for (final book in listed) book.id}, made.keys.toSet());
    for (final book in listed) {
      expect(book.url, isNull, reason: book.id);
      expect(sha256.convert(made[book.id]!).toString(), book.sha256);
      expect(made[book.id]!.length, book.bytes);
    }
  });
}
