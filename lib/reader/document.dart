import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_epub_viewer/navigation.dart';

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

  ReaderAddress? restore(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['processed'] != identity ||
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
  EpubDocument(this.publication)
    : format = 'epub',
      originalDigest = publication.originalDigest,
      identity = publication.identity,
      policy = Publication.policy;
  EpubDocument.mobi(this.publication, this.originalDigest)
    : format = 'mobi',
      policy = mobiPolicy,
      identity = sha256
          .convert(utf8.encode('$mobiPolicy/$originalDigest'))
          .toString();
  static const mobiPolicy =
      'bookfin-mobi-epub-1-libmobi-0.12/${Publication.policy}';
  final Publication publication;
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

abstract interface class DocumentNavigator {
  Future<void> move(bool forward);
  Future<void> display(ReaderAddress address);
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
  Future<void> configure({required double fontSize, required bool night});
  Future<ReaderSearchReport> search(String query, int request);
  Future<void> cancelSearch(int request);
}

class EpubNavigator implements DocumentNavigator {
  EpubNavigator(this.port);
  final NavigatorPort port;
  @override
  Future<void> move(bool forward) => port.move(forward);
  @override
  Future<void> display(ReaderAddress address) {
    if (address is! EpubAddress) {
      throw ArgumentError('Choose a location in this EPUB.');
    }
    return port.display(address.location);
  }

  @override
  Future<void> contents(String href) => port.contents(href);
  @override
  Future<void> seek(int part, double progress) => port.seek(part, progress);
  @override
  Future<PagePreview> preview(
    BookPlace place,
    double width,
    Future<void> abandon,
  ) async {
    final picture = await port.preview(
      place.part,
      place.progress,
      width,
      abandon,
    );
    // The engine decodes the image on another thread.
    final codec = await ui.instantiateImageCodec(picture.image);
    final ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    BookPlace? at((int, double)? place) =>
        place == null ? null : (part: place.$1, progress: place.$2);
    return PagePreview(
      part: picture.section,
      start: picture.start,
      end: picture.end,
      image: image,
      previous: at(picture.previous),
      next: at(picture.next),
    );
  }

  @override
  Future<void> configure({required double fontSize, required bool night}) =>
      port.configure(fontSize: fontSize, night: night);
  @override
  Future<ReaderSearchReport> search(String query, int request) async {
    final report = await port.search(query, request);
    return ReaderSearchReport([
      for (final hit in report.hits)
        ReaderHit(EpubAddress(hit.location), hit.excerpt),
    ], error: report.error);
  }

  @override
  Future<void> cancelSearch(int request) => port.cancelSearch(request);
}
