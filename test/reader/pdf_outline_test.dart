// A PDF edition's text outline comes from its bookmarks and its text layer
// (docs/plans/cross-edition-places.md, step 8 of the order of work). Each
// source page is a part with the visible characters of its text layer, and
// each bookmark is a contents entry at its nesting depth. Then the
// cross-edition matching works for a PDF as it works for an EPUB.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/alignment.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/playback/audio_outline.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_outline.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../crossings/crossings_test.dart' show MemoryOutlines;
import '../downloads/verified_reads.dart';

const marginsBook = 'test/reader/fixtures/reflow/margins-book.pdf';
const partsBook = 'test/reader/fixtures/outline/parts-book.pdf';
const simple = 'tool/research/readers/fixtures/simple.pdf';
const scanned = 'tool/research/readers/fixtures/scanned.pdf';

/// A PDF edition of the book whose download is [path].
Edition pdfEdition(String path) => Edition(
  id: 'pdf',
  kind: EditionKind.text,
  label: 'PDF',
  files: [
    SourceFile(
      itemId: 'pdf',
      displayName: path.split('/').last,
      mediaSourceId: 'original',
      revision: 'r1',
      durationMs: null,
      container: 'pdf',
      sizeBytes: File(path).lengthSync(),
    ),
  ],
  memberIds: const ['pdf'],
);

/// The text outline of the PDF at [path], as Bookfin measures a download.
Future<TextOutline> measure(String path) => measureDownloadedOutline(
  verified(File(path).absolute),
  pdfEdition(path).files.single,
);

/// The visible characters of each page of the PDF at [path], as the reader
/// extracts its text layer: its characters that are not white space.
Future<List<int>> readerCharacters(String path) async {
  final book = await PdfRuntime.instance.open(
    File(path).readAsBytesSync(),
    'd' * 64,
  );
  try {
    return [
      for (var page = 1; page <= book.pageCount; page++)
        (await book.textLayer(page)).source
            .replaceAll(RegExp(r'\s'), '')
            .length,
    ];
  } finally {
    await book.dispose();
  }
}

/// A recording of the parts book with a mark for each of its chapters, at
/// 12 visible characters a second of [outline].
Edition narrationOf(TextOutline outline) {
  final chapters = [
    for (final entry in outline.entries)
      if (entry.title.startsWith('Chapter')) entry,
  ];
  int at(int characters) => (characters - chapters.first.start) * 1000 ~/ 12;
  return Edition(
    id: 'narration',
    kind: EditionKind.audio,
    label: 'Narrator',
    files: [
      SourceFile(
        itemId: 'audio',
        displayName: 'Weather',
        mediaSourceId: 'm',
        revision: 'a1',
        durationMs: at(outline.length),
        container: 'mp3',
        sizeBytes: 1,
        chapters: [
          for (final (index, chapter) in chapters.indexed)
            AudioChapter('Chapter ${index + 1}', at(chapter.start)),
        ],
      ),
    ],
    memberIds: const ['audio:m'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  test('each source page of a PDF is a part of its outline, with the '
      'visible characters of its text layer', () async {
    final outline = await measure(marginsBook);

    expect(outline.parts.map((part) => part.path), [
      for (var page = 1; page <= 13; page++) 'page:$page',
    ]);
    expect(
      outline.parts.map((part) => part.characters),
      await readerCharacters(marginsBook),
    );
  });

  test('each bookmark of a PDF is a contents entry that starts where its '
      'chapter starts on its page', () async {
    final outline = await measure(marginsBook);

    // The chapters start at the top of pages 2 and 8.
    final starts = [0];
    for (final part in outline.parts) {
      starts.add(starts.last + part.characters);
    }
    expect(
      [
        for (final entry in outline.entries)
          (entry.title, entry.depth, entry.start),
      ],
      [('Falling Bodies', 0, starts[1]), ('The Pendulum', 0, starts[7])],
    );
  });

  test('bookmarks nested in a PDF are contents entries at their depth, in '
      'the order of the book', () async {
    final outline = await measure(partsBook);

    expect(
      [for (final entry in outline.entries) (entry.title, entry.depth)],
      [
        ('Part One: Water', 0),
        ('Chapter 1: Clouds', 1),
        ('Chapter 2: Rain', 1),
        ('Part Two: Air', 0),
        ('Chapter 3: Wind', 1),
        ('Chapter 4: Snow', 1),
      ],
    );
    final starts = [for (final entry in outline.entries) entry.start];
    expect(starts, orderedEquals([...starts]..sort()));
  });

  test('a chapter that starts partway down a page starts after the text '
      'above it on that page', () async {
    final outline = await measure(partsBook);

    // Six sentences of the end of chapter 1, 394 visible characters, sit
    // above chapter 2's heading on page 3.
    final page3 = outline.parts.take(2).fold(0, (sum, p) => sum + p.characters);
    final rain = outline.entries.firstWhere(
      (entry) => entry.title == 'Chapter 2: Rain',
    );
    expect(rain.start - page3, 394);
  });

  test('a picture page without a text layer holds no characters in a book '
      'with text', () async {
    final outline = await measure(partsBook);

    expect(outline.parts[4].characters, 0);
    expect(outline.parts[3].characters, greaterThan(1000));
  });

  test('a PDF without bookmarks has no contents entries, so its chapters '
      'match no recording, for the reason that one edition has no '
      'chapters', () async {
    final outline = await measure(simple);
    final narration = narrationOf(await measure(partsBook));

    expect(outline.entries, isEmpty);
    expect(
      (alignEditions(
        audioOutline(narration),
        outline,
      ) as UnmatchedChapters).reason,
      Refusal.noChapters,
    );
  });

  test('a scanned page, without a text layer, counts as more text than a '
      'phone page holds, so that a place on it lands pages away from the '
      'next scanned page', () async {
    final outline = await measure(scanned);

    expect(
      outline.parts.single.characters,
      greaterThan(MatchedChapters.pageCharacters),
    );
  });

  test('a PDF outline measures again after the reader closed every PDF and '
      'stopped PDFium', () async {
    await measure(marginsBook);
    await PdfRuntime.instance.shutdown();

    final outline = await measure(marginsBook);

    expect(outline.entries.map((entry) => entry.title), [
      'Falling Bodies',
      'The Pendulum',
    ]);
  });

  test('a PDF that PDFium cannot open has no outline, so Bookfin says that '
      'it cannot read the file', () async {
    final folder = await Directory.systemTemp.createTemp();
    addTearDown(() => folder.delete(recursive: true));
    final broken = File('${folder.path}/broken.pdf')
      ..writeAsStringSync('%PDF-1.7 and nothing more');

    await expectLater(measure(broken.path), throwsFormatException);
  });

  group('a PDF outline from its pages and bookmarks', () {
    test('in a book that is mostly text, a page without a text layer is a '
        'picture or a blank page and holds no characters', () {
      final outline = pdfOutlineOf(const [1200, 0, 1100], const []);

      expect(outline.parts.map((part) => part.characters), [1200, 0, 1100]);
    });

    test('in a scanned book, where most pages lack a text layer, places '
        'fall by pages: halfway through the book is the start of the third '
        'of four pages', () {
      final outline = pdfOutlineOf(const [0, 0, 0, 0], const []);

      expect(outline.placeAt(outline.length / 2), (part: 2, progress: 0.0));
    });

    test('in a scanned book, a page with a text layer keeps its own '
        'characters', () {
      final outline = pdfOutlineOf(const [0, 0, 0, 900], const []);

      expect(outline.parts.last.characters, 900);
    });

    test('a bookmark starts at its page, after the characters above its '
        'place there', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Two', depth: 0, page: 2, above: 300),
        ],
      );

      expect(
        [for (final entry in outline.entries) (entry.title, entry.start)],
        [('One', 0), ('Two', 1300)],
      );
    });

    test('bookmarks that the outline lists out of page order are entries in '
        'the order of the book', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'Index', depth: 0, page: 2, above: 500),
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Two', depth: 0, page: 2, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), [
        'One',
        'Two',
        'Index',
      ]);
    });

    test('a bookmark without a title names no chapter and is left out', () {
      final outline = pdfOutlineOf(
        const [1000, 1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: ' ', depth: 0, page: 2, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), ['One']);
    });

    test('a bookmark to a page outside the book is left out', () {
      final outline = pdfOutlineOf(
        const [1000],
        const [
          (title: 'One', depth: 0, page: 1, above: 0),
          (title: 'Lost', depth: 0, page: 7, above: 0),
        ],
      );

      expect(outline.entries.map((entry) => entry.title), ['One']);
    });
  });

  test('a PDF reading place lies at the start of its source page', () async {
    final outline = await measure(marginsBook);
    final place = TextPosition(
      editionId: 'pdf',
      sourceKey: 'pdf:original',
      revision: 'r1',
      anchor: jsonEncode({'page': 3, 'character': 0, 'quote': 'The rule'}),
    );

    expect(
      outline.charactersOf(place),
      outline.parts[0].characters + outline.parts[1].characters,
    );
  });

  test('a listening place lands on the page of its chapter in a PDF, and a '
      'PDF reading place lands in its chapter of the recording', () async {
    final text = pdfEdition(partsBook);
    final narration = narrationOf(await measure(partsBook));
    final crossings = Crossings(
      store: MemoryOutlines(),
      measure: (edition) => measureDownloadedOutline(
        verified(File(partsBook).absolute),
        edition.files.single,
      ),
      hop: <M, R>(work, input) async => work(input),
    );
    addTearDown(crossings.dispose);
    final wind = narration.files.single.chapters[2].startMs;

    final heard = await crossings.landing(
      AudioPosition(
        editionId: narration.id,
        sourceKey: narration.files.single.key,
        revision: 'a1',
        milliseconds: wind + 5000,
      ),
      from: narration,
      into: text,
    );
    final read = await crossings.landing(
      TextPosition(
        editionId: text.id,
        sourceKey: text.files.single.key,
        revision: 'r1',
        anchor: jsonEncode({'page': 8, 'character': 0, 'quote': 'Snow'}),
      ),
      from: text,
      into: narration,
    );

    // Chapter 3 starts on page 6, and chapter 4 on page 8.
    expect((heard as TextLanding).place.part, 5);
    expect(heard.chapter, 'Chapter 3: Wind');
    final snow = narration.files.single.chapters[3].startMs;
    expect((read as AudioLanding).place.milliseconds, closeTo(snow, 2000));
  });
}
