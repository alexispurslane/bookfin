// Tool code for the on-demand corpus run (BOOKFIN_EPUB_CORPUS=1). It is
// not part of Bookfin and nothing in lib/ uses it.
//
// The corpus list, tool/reader/epub_corpus.json. The fetch script
// tool/reader/fetch_epub_corpus.py downloads its books into
// .cache/epub-corpus/books.
import 'dart:convert';
import 'dart:io';

/// One book of the corpus list.
class CorpusEntry {
  CorpusEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      source = json['source'] as String,
      url = json['url'] as String?,
      sha256 = json['sha256'] as String?,
      bytes = json['bytes'] as int?,
      format = json['format'] as String,
      why = json['why'] as String;

  final String id;
  final String title;

  /// standard-ebooks, gutenberg, or bookfin-showcase for a book that
  /// tool/showcase_media.dart makes.
  final String source;

  /// Where the fetch script downloads the book from; null for a book that
  /// the tests make.
  final String? url;

  /// The pinned SHA-256 of the book's file, and its size in bytes.
  final String? sha256;
  final int? bytes;

  /// epub, or azw3 for a Kindle file that Bookfin converts first.
  final String format;

  /// Why the book is in the corpus.
  final String why;

  /// Where the fetch script puts the book.
  File get file => File('.cache/epub-corpus/books/$id.$format');
}

/// The books of tool/reader/epub_corpus.json, in its order.
List<CorpusEntry> corpusList() => [
  for (final book
      in (jsonDecode(File('tool/reader/epub_corpus.json').readAsStringSync())
              as Map<String, dynamic>)['books']
          as List)
    CorpusEntry.fromJson(book as Map<String, dynamic>),
];
