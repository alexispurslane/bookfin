// A book whose chapter file is missing from the book file, or fails the
// ZIP check, still opens (t5-gk30, user decision of 2026-11-11). Each
// such chapter keeps its place in the reading order and shows a short note
// instead of its text, so saved places in the other chapters still open
// where they did. A contents entry that names a file that the book lacks
// is left out of the contents.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'epubjs_fixtures.dart' show immediateSource, pageAt;
import 'zip_test.dart' show withEntry;

/// The text of chapter [number].
String _chapter(int number) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter '
    '$number</title></head><body><h1>Chapter $number</h1><p>The river '
    'bends for the ${['first', 'second', 'third'][number - 1]} time.</p>'
    '</body></html>';

/// A book of three chapters with an NCX of their [contents], without the
/// files of [missing].
Uint8List _book({
  Set<String> missing = const {},
  List<(String, String)> contents = const [
    ('Chapter 1', 'one.xhtml'),
    ('Chapter 2', 'two.xhtml'),
    ('Chapter 3', 'three.xhtml'),
  ],
}) {
  final ncx =
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
      '<navMap>${[for (final (index, (title, src)) in contents.indexed) '<navPoint id="p$index"><navLabel><text>$title</text></navLabel>'
            '<content src="$src"/></navPoint>'].join()}</navMap></ncx>';
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
      '</rootfiles></container>',
    ),
    'OPS/book.opf': utf8.encode(
      '<package version="2.0"><metadata/><manifest>'
      '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="three" href="three.xhtml" '
      'media-type="application/xhtml+xml"/>'
      '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
      '</manifest><spine toc="toc"><itemref idref="one"/>'
      '<itemref idref="two"/><itemref idref="three"/></spine></package>',
    ),
    'OPS/toc.ncx': utf8.encode(ncx),
    'OPS/one.xhtml': utf8.encode(_chapter(1)),
    'OPS/two.xhtml': utf8.encode(_chapter(2)),
    'OPS/three.xhtml': utf8.encode(_chapter(3)),
  };
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    if (missing.contains(name)) continue;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// [book] with the ZIP directory's CRC-32 of [name] changed, so that the
/// file fails the ZIP check.
Uint8List _damaged(Uint8List book, String name) =>
    withEntry(book, name, crc: 0x12345678);

/// The text of the body of section [index] of [publication].
String _text(Publication publication, int index) =>
    utf8.decode(publication.resources[publication.spine[index]]!);

void main() {
  test('a book whose later chapter file is missing opens, and that chapter '
      'shows a short note instead of its text', () {
    final publication = Publication.admit(_book(missing: {'OPS/two.xhtml'}));

    expect(publication.spine, hasLength(3));
    expect(
      _text(publication, 1),
      contains('This chapter is missing from the book file.'),
    );
    expect(_text(publication, 0), contains('for the first time'));
    expect(_text(publication, 2), contains('for the third time'));
    publication.checkInvariants();
  });

  test('a book whose later chapter fails the ZIP check opens, and that '
      'chapter shows a short note instead of its text', () {
    final publication = Publication.admit(_damaged(_book(), 'OPS/two.xhtml'));

    expect(publication.spine, hasLength(3));
    expect(
      _text(publication, 1),
      contains('This chapter could not be read from the book file.'),
    );
    expect(_text(publication, 1), isNot(contains('second time')));
    expect(_text(publication, 0), contains('for the first time'));
  });

  test('a contents entry that names a file that the book lacks is left out, '
      'and the book opens with the other entries', () {
    final publication = Publication.admit(
      _book(
        contents: const [
          ('Chapter 1', 'one.xhtml'),
          ('Lost appendix', 'appendix.xhtml'),
          ('Chapter 3', 'three.xhtml'),
        ],
      ),
    );

    expect(
      [for (final entry in publication.contents) entry.title],
      ['Chapter 1', 'Chapter 3'],
    );
  });

  test('the contents entry of a missing chapter stays, and opens its note', () {
    final publication = Publication.admit(_book(missing: {'OPS/two.xhtml'}));

    expect(
      [for (final entry in publication.contents) entry.title],
      ['Chapter 1', 'Chapter 2', 'Chapter 3'],
    );
  });

  test('a book whose first chapter is missing still opens, at the note of '
      'that chapter', () {
    final publication = Publication.admit(_book(missing: {'OPS/one.xhtml'}));

    expect(
      _text(publication, 0),
      contains('This chapter is missing from the book file.'),
    );
    expect(_text(publication, 1), contains('for the second time'));
  });

  test('a place saved in a good chapter opens on the same text when another '
      'chapter is missing', () async {
    final whole = Publication.admit(_book());
    final damaged = Publication.admit(_book(missing: {'OPS/two.xhtml'}));
    final cfi = 'epubcfi(${whole.spineSteps[2]}!/4/4/1:4)';

    for (final publication in [whole, damaged]) {
      final source = immediateSource(publication)..settings = pageAt(20);
      addTearDown(source.dispose);
      final dom = (await source.section(2)).dom;
      final place = placeOf(dom, 2, cfi);

      expect(place, isNotNull);
      expect(quoteMatches(dom, place!, 'river bends for the third'), isTrue);
    }
    expect(damaged.spineSteps, whole.spineSteps);
  });

  test('a book whose package document is missing is still refused', () {
    expect(
      () => Publication.admit(_book(missing: {'OPS/book.opf'})),
      throwsFormatException,
    );
  });
}
