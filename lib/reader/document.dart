import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import 'epub/page_maps.dart';
import 'epub/publication.dart';

abstract class ReaderDocument {
  String get format;
  String get identity;
  String get originalDigest;
  String get policy;
  String get engine;
  bool accepts(ReaderAddress address);
  ReaderAddress decodeAddress(Map<String, dynamic> value);
  Future<void> dispose();

  Map<String, dynamic> save(ReaderAddress address) => {
    'version': 1,
    'processed': identity,
    'original': originalDigest,
    'policy': policy,
    'engine': engine,
    ...address.toJson(),
  };

  /// The address of the saved place [value], when it belongs to this
  /// document: to the same original file, read under the same policy and
  /// engine. A place that an older admission of the same file saved can
  /// carry another processed identity. One example is a book whose image
  /// header is sound but whose pixels do not decode: admission refused that
  /// image before t7-rcyp and keeps it now. Such a place still restores,
  /// because the pager opens it only where its CFI and its quote still
  /// match the text.
  ReaderAddress? restore(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['original'] != originalDigest ||
        value['policy'] != policy ||
        value['engine'] != engine) {
      return null;
    }
    final address = decodeAddress(value);
    return accepts(address) ? address : null;
  }
}

class EpubDocument extends ReaderDocument {
  EpubDocument(this.publication, {this.pageMaps})
    : format = 'epub',
      originalDigest = publication.originalDigest,
      identity = publication.identity,
      policy = Publication.policy;
  EpubDocument.mobi(this.publication, this.originalDigest, {this.pageMaps})
    : format = 'mobi',
      policy = mobiPolicy,
      identity = sha256
          .convert(utf8.encode('$mobiPolicy/$originalDigest'))
          .toString();
  static const mobiPolicy =
      'bookfin-mobi-epub-1-libmobi-0.12/${Publication.policy}';
  final Publication publication;

  /// Where Bookfin keeps the page maps of this book's download, or null
  /// when it keeps none.
  final BookPageMaps? pageMaps;
  @override
  final String format;
  @override
  final String identity;
  @override
  final String originalDigest;
  @override
  final String policy;
  @override
  String get engine => 'epubjs-0.3.93-bookfin.1';
  @override
  bool accepts(ReaderAddress address) =>
      address is EpubAddress && publication.spine.contains(address.resource);
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) =>
      EpubAddress(ReadingLocation.fromJson(value));
  @override
  Future<void> dispose() async {}
}

class ReadingLocation {
  const ReadingLocation(
    this.cfi,
    this.resource,
    this.quote, {
    this.chapter,
    this.page,
    this.pages,
    this.progress,
    this.end,
  });
  final String cfi;
  final String resource;
  final String quote;
  final String? chapter;
  final int? page;
  final int? pages;

  /// The text progress of the place through its section, from 0 to 1: the
  /// share of the section's visible characters, white space left out, that
  /// come before it. It places the location along the whole book, so it is
  /// saved with the place. A place saved before it existed has none.
  final double? progress;

  /// The text progress of the last visible character of the shown page, in
  /// the same measure as [progress]. It is for display only, such as the
  /// chapter arrows, so [toJson] does not write it and [fromJson] does not
  /// read it.
  final double? end;
  Map<String, dynamic> toJson() => {
    'cfi': cfi,
    'resource': resource,
    'quote': quote,
    if (progress != null) 'progress': progress,
  };
  factory ReadingLocation.fromJson(Map<String, dynamic> value) {
    if (value['cfi'] is! String ||
        value['resource'] is! String ||
        value['quote'] is! String) {
      throw const FormatException('The reader returned an invalid location.');
    }
    final progress = value['progress'];
    if (progress != null &&
        (progress is! num || !(progress >= 0 && progress <= 1))) {
      throw const FormatException('The reader returned an invalid location.');
    }
    final location = ReadingLocation(
      value['cfi'] as String,
      value['resource'] as String,
      value['quote'] as String,
      chapter: value['chapter'] is String ? value['chapter'] as String : null,
      page: value['page'] is int ? value['page'] as int : null,
      pages: value['pages'] is int ? value['pages'] as int : null,
      progress: (progress as num?)?.toDouble(),
    );
    if (!location.cfi.startsWith('epubcfi(') ||
        !location.cfi.endsWith(')') ||
        location.cfi.length > 4096 ||
        location.resource.length > 512 ||
        location.quote.length > 160 ||
        (location.chapter?.length ?? 0) > 512 ||
        (location.page != null &&
            (location.page! < 1 ||
                location.pages == null ||
                location.pages! < location.page!)) ||
        (location.pages != null && location.page == null)) {
      throw const FormatException('The reader returned an invalid location.');
    }
    return location;
  }
}

class ContentsEntry {
  const ContentsEntry(this.title, this.href, {this.depth = 0});
  final String title;
  final String href;
  final int depth;
}

class SearchHit {
  const SearchHit(this.location, this.excerpt);
  final ReadingLocation location;
  final String excerpt;
}

class SearchReport {
  const SearchReport(this.hits, {this.error});
  final List<SearchHit> hits;
  final String? error;
}

sealed class ReaderAddress {
  String get resource;
  String get quote;
  String? get chapter;
  int? get page;
  int? get pages;
  Map<String, dynamic> toJson();
}

class EpubAddress extends ReaderAddress {
  EpubAddress(this.location);
  final ReadingLocation location;
  @override
  String get resource => location.resource;
  @override
  String get quote => location.quote;
  @override
  String? get chapter => location.chapter;
  @override
  int? get page => location.page;
  @override
  int? get pages => location.pages;
  @override
  Map<String, dynamic> toJson() => location.toJson();
}

class PdfAddress extends ReaderAddress {
  PdfAddress(
    this.sourcePage,
    this.character, {
    this.quote = '',
    this.pageCount,
    this.representation,
  }) {
    if (sourcePage < 1 ||
        character < 0 ||
        quote.length > 160 ||
        (pageCount != null && sourcePage > pageCount!)) {
      throw const FormatException('Invalid PDF source-page position.');
    }
  }
  final int sourcePage;
  final int character;
  final int? pageCount;
  final String? representation;
  @override
  final String quote;
  @override
  String get resource => 'page:$sourcePage';
  @override
  String get chapter => 'Source page $sourcePage';
  @override
  int get page => sourcePage;
  @override
  int? get pages => pageCount;
  @override
  Map<String, dynamic> toJson() => {
    'page': sourcePage,
    'character': character,
    'quote': quote,
    if (representation != null) 'representation': representation,
  };
}

class ReaderHit {
  const ReaderHit(this.address, this.excerpt);
  final ReaderAddress address;
  final String excerpt;
}

class ReaderSearchReport {
  const ReaderSearchReport(this.hits, {this.error});
  final List<ReaderHit> hits;
  final String? error;
}

/// A place in the open book: the place [progress] of the way through part
/// [part], as the book map measures it.
typedef BookPlace = ({int part, double progress});

/// One drawn page of the open book, for the scrub deck.
class PagePreview {
  PagePreview({
    required this.part,
    required this.start,
    required this.end,
    required this.image,
    this.previous,
    this.next,
  });

  /// The part of the book that holds the page: a section of an EPUB's spine,
  /// or a PDF's source page minus one.
  final int part;

  /// How far through [part] the page's first and last places are, from 0 to
  /// 1. A PDF page is a whole part.
  final double start;
  final double end;

  /// The page as the reader shows it.
  final ui.Image image;

  /// Where the pages before and after this one start, or null at the start
  /// or the end of the book.
  final BookPlace? previous;
  final BookPlace? next;

  /// Whether [place] is on this page.
  bool holds(BookPlace place) =>
      place.part == part && place.progress >= start && place.progress <= end;
}

/// Shows the pages of an open book and moves through them, for the
/// reader session.
///
/// A valid request to show a destination ([display], [contents] or
/// [seek]) supersedes every request asked before it: once the call starts,
/// no earlier request reports a place. So the first place that the navigator reports
/// after such a request is the destination's, or a place of a later
/// request.
abstract interface class DocumentNavigator {
  /// Reports the shown place now if its report is pending. The session
  /// calls this before saving for the background or releasing the book.
  /// It does not wait for text or navigate to a requested place that has
  /// not shown yet. A navigator that reports at once has nothing to do.
  void reportPendingPlace();

  /// Turns one page, or in a PDF also scrolls the reflowed text, forward
  /// or back.
  Future<void> move(bool forward);
  Future<void> display(ReaderAddress address);

  /// Shows the destination [href]: a contents entry or an internal link,
  /// relative to the package document's directory, with an optional
  /// fragment. A PDF uses `page:N`.
  Future<void> contents(String href);

  /// Shows the place [progress] of the way through part [part] of the book,
  /// as the book map measures it: a section of an EPUB's spine, or a PDF's
  /// source page minus one. A PDF shows the start of the source page.
  Future<void> seek(int part, double progress);

  /// Draws the page that holds [place], [width] pixels wide, as the viewport
  /// would show it, without moving the shown page. When [abandon] completes
  /// before the page is drawn, the drawing can stop early and fail.
  Future<PagePreview> preview(
    BookPlace place,
    double width,
    Future<void> abandon,
  );
  Future<ReaderSearchReport> search(String query, int request);
  Future<void> cancelSearch(int request);
}
