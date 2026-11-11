// The text outline of an ebook edition: its contents entries, each with its
// start in visible characters from the book's start, and the visible
// characters of each part. A visible character is a character of the body
// text that is not white space, as the book map counts it. The cross-edition
// matching pairs these entries with audio chapters.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart' show VerifiedFile;
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_native_test.dart' show bookWithoutContents, navBook;

/// Three sections. Each body lists its visible characters in a comment.
final _book = navBook(
  [
    // "Loomings" 8, "CallmeIshmael." 14: 22.
    '<h1 id="one">Loomings</h1><p>Call me Ishmael.</p>',
    // "Someyearsago." 13, "TheCarpet-Bag" 13, "Istuffedashirt." 15: 41.
    '<p>Some years ago.</p><h1 id="two">The Carpet-Bag</h1>'
        '<p>I stuffed a shirt.</p>',
    // "TheSpouter-Inn" 14, "Enteringthatgable-endedinn." 27: 41.
    '<h1>The Spouter-Inn</h1><p>Entering that gable-ended inn.</p>',
  ],
  [
    ('Loomings', 'text/s0.xhtml#one'),
    ('The Carpet-Bag', 'text/s1.xhtml#two'),
    ('The Spouter-Inn', 'text/s2.xhtml'),
  ],
);

/// A reading place of [_book] in section [resource] at [progress] of its
/// visible characters, as the reader saves it.
TextPosition _place(String resource, double? progress) => TextPosition(
  editionId: 'ebook',
  sourceKey: 'ebook:original',
  revision: 'r1',
  anchor: jsonEncode({
    'version': 1,
    'cfi': 'epubcfi(/6/4!/4/2/1:0)',
    'resource': resource,
    'quote': 'Some years ago.',
    'progress': ?progress,
  }),
);

void main() {
  test('a text outline lists each contents entry at its start in visible '
      'characters from the book\'s start', () {
    final outline = measureTextOutline(Publication.admit(_book));

    expect(
      [for (final entry in outline.entries) (entry.title, entry.start)],
      [('Loomings', 0), ('The Carpet-Bag', 35), ('The Spouter-Inn', 63)],
    );
    expect(outline.length, 104);
  });

  test('a book without contents lists one chapter for each linear section, '
      'as the reader does', () {
    final outline = measureTextOutline(
      Publication.admit(
        bookWithoutContents([
          ('<p>Title page</p>', 'no'),
          ('<p>First words.</p>', null),
          ('<p>Last words.</p>', 'yes'),
        ]),
      ),
    );

    expect(
      [for (final entry in outline.entries) (entry.title, entry.start)],
      [('Chapter 1', 9), ('Chapter 2', 20)],
    );
  });

  test('a reading place lies at the visible characters before it', () {
    final outline = measureTextOutline(Publication.admit(_book));

    expect(outline.charactersOf(_place('OPS/text/s1.xhtml', .5)), 42.5);
  });

  test('a reading place without its share of its section, as early builds '
      'saved it, or in a section that the book lacks, has no characters', () {
    final outline = measureTextOutline(Publication.admit(_book));

    expect(outline.charactersOf(_place('OPS/text/s1.xhtml', null)), isNull);
    expect(outline.charactersOf(_place('OPS/text/s9.xhtml', .5)), isNull);
  });

  test('the place at a number of characters is the section that holds them '
      'and the share of its characters before them', () {
    final outline = measureTextOutline(Publication.admit(_book));

    expect(outline.placeAt(42.5), (part: 1, progress: .5));
    expect(outline.placeAt(22), (part: 1, progress: 0.0));
    expect(outline.placeAt(500), (part: 2, progress: 1.0));
  });

  test('an outline reads back from its JSON form unchanged', () {
    final outline = measureTextOutline(Publication.admit(_book));

    final copy = TextOutline.fromJson(
      jsonDecode(jsonEncode(outline.toJson())) as Map<String, dynamic>,
    );

    expect(
      [
        for (final entry in copy.entries)
          (entry.title, entry.depth, entry.start),
      ],
      [
        for (final entry in outline.entries)
          (entry.title, entry.depth, entry.start),
      ],
    );
    expect(copy.charactersOf(_place('OPS/text/s1.xhtml', .5)), 42.5);
    expect(copy.length, outline.length);
  });

  group('a downloaded ebook measures its outline', () {
    late Directory folder;
    setUp(() async => folder = await Directory.systemTemp.createTemp());
    tearDown(() => folder.delete(recursive: true));

    Future<TextOutline?> measure(Uint8List bytes, String container) async {
      final file = File('${folder.path}/book.$container');
      await file.writeAsBytes(bytes);
      return measureDownloadedOutline(
        VerifiedFile(file.uri, sha256.convert(bytes).toString()),
        SourceFile(
          itemId: 'ebook',
          displayName: 'Book',
          mediaSourceId: 'original',
          revision: 'r1',
          durationMs: null,
          container: container,
          sizeBytes: bytes.length,
        ),
      );
    }

    test('an EPUB', () async {
      final outline = await measure(_book, 'epub');

      expect(outline!.length, 104);
      expect(outline.entries, hasLength(3));
    });

    test('a MOBI, after its conversion to EPUB', () async {
      final outline = await measure(
        File('tool/research/readers/fixtures/pg11-kf8.mobi').readAsBytesSync(),
        'mobi',
      );

      expect(
        outline!.entries.map((entry) => entry.title),
        contains(startsWith('CHAPTER I.')),
      );
      expect(outline.length, greaterThan(100000));
    });

    test('a PDF has no text outline yet', () async {
      expect(
        measure(Uint8List.fromList('%PDF-1.7'.codeUnits), 'pdf'),
        throwsUnsupportedError,
      );
    });
  });
}
