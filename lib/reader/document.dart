import 'dart:convert';

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

abstract interface class DocumentNavigator {
  Future<void> move(bool forward);
  Future<void> display(ReaderAddress address);
  Future<void> contents(String href);
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
