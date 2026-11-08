// A test book for the trial renderer: the publication that Bookfin's
// sanitizer admits, with each style sheet either as admitted or as the
// book wrote it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_epub_viewer/publication.dart';

import 'cfi.dart';
import 'layout.dart';

class TrialBook {
  TrialBook._(this.publication, this._sheets, this._opf);

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
    return TrialBook._(
      publication,
      sheets,
      utf8.decode(publication.resources[publication.packagePath]!),
    );
  }

  final Publication publication;
  final Map<String, Uint8List> _sheets;
  final String _opf;

  int get sections => publication.spine.length;

  Uint8List? resource(String path) =>
      _sheets[path] ?? publication.resources[path];

  SectionInput section(int index) {
    final path = publication.spine[index];
    return SectionInput(
      path,
      utf8.decode(publication.resources[path]!),
      resource,
    );
  }

  /// The spine step of the CFIs of section [index].
  String spine(int index) => spineStep(_opf, index);

  /// Every style sheet text of the book, by path.
  Map<String, String> get styleSheets => {
    for (final MapEntry(key: path, value: type)
        in publication.mediaTypes.entries)
      if (type == 'text/css') path: utf8.decode(resource(path)!),
  };
}
