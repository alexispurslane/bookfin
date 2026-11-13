// Tool code for the on-demand runs over real books. It is not part of
// Bookfin and nothing in lib/ uses it.
//
// A test book: the publication that Bookfin's sanitizer admits, read as
// the page source reads it. Each section is styled by the book's own style
// sheets (Publication.bookStyles), sized by the admitted image sizes
// (Publication.imageSizes) and hyphenated in the book's language
// (Publication.language).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';

import '../../../../tool/showcase_media.dart' as media;

class CorpusBook {
  CorpusBook(this.publication)
    : _spine = spineSteps(
        utf8.decode(publication.textFiles[publication.packagePath]!),
      );

  /// Admits [bytes].
  factory CorpusBook.open(Uint8List bytes) =>
      CorpusBook(Publication.admit(bytes));

  final Publication publication;

  /// The spine step of each section's CFIs.
  final List<String> _spine;

  int get sections => publication.spine.length;

  Future<Uint8List?> resource(String path) => publication.bytesOf(path);

  /// What preparing section [index] reads.
  SectionSource source(int index) {
    final path = publication.spine[index];
    return SectionSource(
      index: index,
      path: path,
      xhtml: utf8.decode(publication.textFiles[path]!),
      styleSheets: publication.bookStyles,
      imageSizes: publication.imageSizes,
      language: publication.language,
    );
  }

  /// The spine step of the CFIs of section [index].
  String spine(int index) => _spine[index];
}

/// The made-up books of tool/showcase_media.dart, by trial name. Each is
/// zipped again with the fixed file time used by the recorded corpus
/// identities. Retain that time because identity includes the archive bytes.
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

/// A made-up EPUB with one section for each of [bodies], all styled by one
/// style sheet, [css], with the PNG images of [images] and the WOFF fonts of
/// [fonts] by path.
Uint8List madeUpEpub(
  List<String> bodies, {
  String css = '',
  Map<String, Uint8List> images = const {},
  Map<String, Uint8List> fonts = const {},
}) {
  final sections = [for (var index = 0; index < bodies.length; index++) index];
  final items = sections
      .map(
        (index) =>
            '<item id="s$index" href="s$index.xhtml" '
            'media-type="application/xhtml+xml"/>',
      )
      .join();
  final spine = sections.map((index) => '<itemref idref="s$index"/>').join();
  final pictures = [
    for (final (index, path) in images.keys.indexed)
      '<item id="i$index" href="$path" media-type="image/png"/>',
    for (final (index, path) in fonts.keys.indexed)
      '<item id="f$index" href="$path" media-type="font/woff"/>',
  ].join();
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'book.opf',
        '<package version="3.0"><metadata/><manifest>$items$pictures'
            '<item id="css" href="book.css" media-type="text/css"/>'
            '</manifest><spine>$spine</spine></package>',
      ),
    )
    ..add(ArchiveFile.string('book.css', css));
  for (final MapEntry(key: path, value: bytes) in {
    ...images,
    ...fonts,
  }.entries) {
    archive.add(ArchiveFile.noCompress(path, bytes.length, bytes));
  }
  for (final (index, body) in bodies.indexed) {
    archive.add(
      ArchiveFile.string(
        's$index.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
            '<link rel="stylesheet" href="book.css"/></head>'
            '<body>$body</body></html>',
      ),
    );
  }
  // Rebuilding identical content must keep the source digest of saved places.
  final builtAt = DateTime(2026).millisecondsSinceEpoch ~/ 1000;
  for (final file in archive.files) {
    file.lastModTime = builtAt;
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
