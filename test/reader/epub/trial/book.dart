// Tool code for the on-demand trial runs (BOOKFIN_EPUB_TRIAL=1). It is not
// part of Bookfin and nothing in lib/ uses it.
//
// A test book: the publication that Bookfin's sanitizer admits, with each
// style sheet either as admitted or as the book wrote it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:image/image.dart' as img;

import '../../../../tool/showcase_media.dart' as media;

class TrialBook {
  TrialBook._(this.publication, this._sheets, this._opf, this._imageSizes);

  /// Admits [bytes]. With [originalCss], each style sheet is the book's own
  /// text, which Bookfin's sanitizer may have emptied.
  factory TrialBook.open(Uint8List bytes, {bool originalCss = true}) {
    final publication = Publication.admit(bytes);
    final sheets = <String, Uint8List>{};
    if (originalCss) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final MapEntry(key: path, value: type)
          in publication.mediaTypes.entries) {
        if (type != 'text/css') continue;
        final file = archive.findFile(path);
        final content = file?.readBytes();
        if (content != null) sheets[path] = Uint8List.fromList(content);
      }
    }
    // The image package reads only each image's header here.
    final imageSizes = <String, (int, int)>{
      for (final MapEntry(key: path, value: type)
          in publication.mediaTypes.entries)
        if (type.startsWith('image/'))
          if (publication.resources[path] case final bytes?)
            if (img.findDecoderForData(bytes)?.startDecode(bytes)
                case final info?)
              path: (info.width, info.height),
    };
    return TrialBook._(
      publication,
      sheets,
      utf8.decode(publication.resources[publication.packagePath]!),
      imageSizes,
    );
  }

  final Publication publication;
  final Map<String, Uint8List> _sheets;
  final String _opf;
  final Map<String, (int, int)> _imageSizes;

  int get sections => publication.spine.length;

  Uint8List? resource(String path) =>
      _sheets[path] ?? publication.resources[path];

  /// What preparing section [index] reads.
  SectionSource source(int index) {
    final path = publication.spine[index];
    return SectionSource(
      index: index,
      path: path,
      xhtml: utf8.decode(publication.resources[path]!),
      fontPrefix: 'bookfin-${publication.identity.substring(0, 12)}',
      styleSheets: styleSheets,
      imageSizes: _imageSizes,
    );
  }

  /// The spine step of the CFIs of section [index].
  String spine(int index) => spineStep(_opf, index);

  /// Every style sheet text of the book, by path.
  late final Map<String, String> styleSheets = {
    for (final MapEntry(key: path, value: type)
        in publication.mediaTypes.entries)
      if (type == 'text/css') path: _decode(resource(path)!),
  };
}

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

/// The test books in .cache/epub-trial/books, which the trial downloads
/// from Standard Ebooks and Project Gutenberg. Empty when they are absent.
List<File> trialBooks() {
  final directory = Directory('.cache/epub-trial/books');
  if (!directory.existsSync()) return [];
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.epub'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String bookName(File file) =>
    file.uri.pathSegments.last.replaceAll('.epub', '');

/// The made-up books of tool/showcase_media.dart, by trial name. Each is
/// zipped again with a fixed file time, because the showcase stamps each
/// file with the time it was made and the publication identity hashes the
/// archive bytes too.
Map<String, Uint8List> showcaseBooks() => {
  for (final (id, title, chapters) in [
    ('frost', 'First Frost', media.firstFrost),
    ('salt', 'Salt and Lantern', media.saltAndLantern),
    ('winter', 'The Winter Ledger', media.winterLedger),
  ])
    'showcase-$id': ZipEncoder().encodeBytes(
      ZipDecoder().decodeBytes(
        media.epub(id, title, 'Bookfin Showcase', chapters),
      ),
      modified: DateTime(2026, 11, 7),
    ),
};
