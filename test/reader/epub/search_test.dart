import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/search.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/showcase_media.dart' as media;

/// A made-up section at spine index [index] whose body is [body].
SearchSection chapter(int index, String body, {String head = ''}) =>
    SearchSection(
      index: index,
      path: 'OPS/c$index.xhtml',
      xhtml: utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>$head</head>'
        '<body>$body</body></html>',
      ),
      spine: '/6/${(index + 1) * 2}',
    );

/// Runs the work of an isolate hop on this isolate.
Future<R> inline<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);

/// Searches [sections] for [query] as the pager does, without a cancel.
Future<ReaderSearchReport> search(
  List<SearchSection> sections,
  String query, {
  List<ContentsEntry> contents = const [],
}) => searchBook(
  sections,
  query,
  contents,
  'OPS/book.opf',
  isCurrent: () => true,
  hop: inline,
);

/// The excerpts of the hits that a search of [body] for [query] finds.
Future<List<String>> excerpts(String body, String query) async => [
  for (final hit in (await search([chapter(0, body)], query)).hits) hit.excerpt,
];

/// The saved location of [hit].
ReadingLocation location(ReaderHit hit) =>
    (hit.address as EpubAddress).location;

/// What reader.js `searchBook` reported in headless Chromium 138 on
/// 2026-11-08 (ticket tc-866u): for each book and query, the number of hits,
/// the error ('book' for more than 500 hits in the book, 'chapter' for more
/// than 500 in a section) and a digest of the hits (see [digest]). The books
/// are the showcase books of tool/showcase_media.dart and the trial books
/// in .cache/epub-trial/books.
///
/// Publication.contents folds U+FEFF in a contents title to a space, where
/// epub.js keeps it (ticket td-vjzg), so the recorded chapter labels fold
/// it too. Only three titles of se-poetry have one.
const _reportedByWebView =
    <(String book, String query, int hits, String? error, String digest)>[
      ('frost', "the", 79, null, 'ce0a9e5b18e92cb8'),
      ('frost', "and", 23, null, '8bc29b47ba8ee8cb'),
      ('frost', "said", 4, null, 'ef879704d76a6c97'),
      ('frost', "harbour", 0, null, '4f53cda18c2baa0c'),
      ('frost', "of the", 3, null, 'ad7100559be36114'),
      ('frost', "It was", 1, null, '964bb9dc07097bd9'),
      ('frost', "whale", 0, null, '4f53cda18c2baa0c'),
      ('frost', "e", 296, null, 'ba0647dcd400868b'),
      ('frost', "Chapter", 0, null, '4f53cda18c2baa0c'),
      ('frost', "“", 0, null, '4f53cda18c2baa0c'),
      ('frost', "o’", 0, null, '4f53cda18c2baa0c'),
      ('frost', "NEVER", 1, null, '27a0ddff168fd58c'),
      ('frost', "the end", 0, null, '4f53cda18c2baa0c'),
      ('salt', "the", 35, null, '40e0d4345b76cdca'),
      ('salt', "and", 11, null, 'ebb1256dacc3a5b3'),
      ('salt', "said", 0, null, '4f53cda18c2baa0c'),
      ('salt', "harbour", 0, null, '4f53cda18c2baa0c'),
      ('salt', "of the", 4, null, '7964c151afd1b609'),
      ('salt', "It was", 0, null, '4f53cda18c2baa0c'),
      ('salt', "whale", 1, null, '4e6e7fc785b1560c'),
      ('salt', "e", 106, null, 'ad8812d15622a609'),
      ('salt', "Chapter", 0, null, '4f53cda18c2baa0c'),
      ('salt', "“", 0, null, '4f53cda18c2baa0c'),
      ('salt', "o’", 0, null, '4f53cda18c2baa0c'),
      ('salt', "NEVER", 0, null, '4f53cda18c2baa0c'),
      ('salt', "the end", 1, null, 'e39651bafff32781'),
      ('winter', "the", 15, null, '93a28ec5905af3d1'),
      ('winter', "and", 3, null, '7ff51e5da92245d4'),
      ('winter', "said", 0, null, '4f53cda18c2baa0c'),
      ('winter', "harbour", 0, null, '4f53cda18c2baa0c'),
      ('winter', "of the", 0, null, '4f53cda18c2baa0c'),
      ('winter', "It was", 0, null, '4f53cda18c2baa0c'),
      ('winter', "whale", 0, null, '4f53cda18c2baa0c'),
      ('winter', "e", 46, null, '7d8dced1b00bce21'),
      ('winter', "Chapter", 0, null, '4f53cda18c2baa0c'),
      ('winter', "“", 0, null, '4f53cda18c2baa0c'),
      ('winter', "o’", 0, null, '4f53cda18c2baa0c'),
      ('winter', "NEVER", 0, null, '4f53cda18c2baa0c'),
      ('winter', "the end", 0, null, '4f53cda18c2baa0c'),
      ('se-moby-dick', "the", 500, 'book', '48d2a9cad4c76f98'),
      ('se-moby-dick', "and", 500, 'book', 'b82b22aa782b8df1'),
      ('se-moby-dick', "said", 309, null, '305fe66e7a09e71d'),
      ('se-moby-dick', "harbour", 2, null, 'fec8184349003c7b'),
      ('se-moby-dick', "of the", 500, 'book', 'ae355646427d97a0'),
      ('se-moby-dick', "It was", 299, null, '1a7649c453df0093'),
      ('se-moby-dick', "whale", 500, 'book', 'def2e74d307dac74'),
      ('se-moby-dick', "e", 500, 'book', '41f8dc09722d913b'),
      ('se-moby-dick', "Chapter", 46, null, '455ea56be4d321be'),
      ('se-moby-dick', "“", 500, 'book', '3edb2a1a7854e514'),
      ('se-moby-dick', "o’", 51, null, 'baee4a2f9cd3221e'),
      ('se-moby-dick', "NEVER", 272, null, 'ab9d2140693a2507'),
      ('se-moby-dick', "the end", 36, null, 'a11fe0b83f24c348'),
      ('se-frankenstein', "the", 500, 'book', 'b66cb3fb0fd62c09'),
      ('se-frankenstein', "and", 500, 'book', '4a3108b09a4421d5'),
      ('se-frankenstein', "said", 105, null, '27d5f94223516f96'),
      ('se-frankenstein', "harbour", 3, null, '87d4a195a974817a'),
      ('se-frankenstein', "of the", 500, 'book', '918a914f66fb27cb'),
      ('se-frankenstein', "It was", 150, null, '73ea9930ae677adc'),
      ('se-frankenstein', "whale", 4, null, 'e90721aa6fa5173a'),
      ('se-frankenstein', "e", 500, 'book', '10530bc1872dcbeb'),
      ('se-frankenstein', "Chapter", 24, null, '1cb075f7777ff569'),
      ('se-frankenstein', "“", 490, null, '73e7bd5584933dae'),
      ('se-frankenstein', "o’", 7, null, '1eb71d728439f46b'),
      ('se-frankenstein', "NEVER", 74, null, 'ea8e375407dbde6a'),
      ('se-frankenstein', "the end", 10, null, 'd2abe6345f9a73d0'),
      ('pg-84-frankenstein', "the", 500, 'book', '702501ebdb0ba216'),
      ('pg-84-frankenstein', "and", 500, 'book', '3dc8491d1ea58d68'),
      ('pg-84-frankenstein', "said", 102, null, 'a5da9d00de65b1e3'),
      ('pg-84-frankenstein', "harbour", 3, null, '862dfb0670d19c78'),
      ('pg-84-frankenstein', "of the", 500, 'book', '3ceeb3856ad3ff60'),
      ('pg-84-frankenstein', "It was", 141, null, '4709d90fcffd9f40'),
      ('pg-84-frankenstein', "whale", 4, null, '411473ed352cd93c'),
      ('pg-84-frankenstein', "e", 500, 'book', '13eeedec586ac76e'),
      ('pg-84-frankenstein', "Chapter", 48, null, '01728b31f42fbcc2'),
      ('pg-84-frankenstein', "“", 491, null, '1daf3134b43d3257'),
      ('pg-84-frankenstein', "o’", 7, null, '98d5b06fc49dd2ba'),
      ('pg-84-frankenstein', "NEVER", 72, null, '4369fa32b78a8ba4'),
      ('pg-84-frankenstein', "the end", 8, null, '9b567b14f4a112a0'),
      (
        'se-alices-adventures-in-wonderland',
        "the",
        500,
        'book',
        'bc07bf267c488c28',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "and",
        500,
        'book',
        '10b0832414022bc3',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "said",
        464,
        null,
        'e480b9ebd53bc70a',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "harbour",
        0,
        null,
        '4f53cda18c2baa0c',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "of the",
        158,
        null,
        'c184be2f08c9e9e4',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "It was",
        84,
        null,
        'd2da72c1fd4ffed4',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "whale",
        0,
        null,
        '4f53cda18c2baa0c',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "e",
        500,
        'book',
        '22cbdb3b563665d2',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "Chapter",
        0,
        null,
        '4f53cda18c2baa0c',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "“",
        500,
        'book',
        '0309b9fbc6a3f271',
      ),
      ('se-alices-adventures-in-wonderland', "o’", 5, null, 'b6e01930df86a751'),
      (
        'se-alices-adventures-in-wonderland',
        "NEVER",
        51,
        null,
        '6e2f47fc2bbf03d7',
      ),
      (
        'se-alices-adventures-in-wonderland',
        "the end",
        14,
        null,
        'af907632d3b05cda',
      ),
      ('se-poetry', "the", 500, 'book', '9cd5d6110eb71b75'),
      ('se-poetry', "and", 500, 'book', 'fcbc868374f6b5f8'),
      ('se-poetry', "said", 85, null, '4d2c6481b1a9ebe2'),
      ('se-poetry', "harbour", 4, null, 'b15dbaaa0b7d08fb'),
      ('se-poetry', "of the", 310, null, 'acb370c0c8717ca7'),
      ('se-poetry', "It was", 30, null, 'dbea7584c4aebbce'),
      ('se-poetry', "whale", 5, null, 'e2f7b09e2c298282'),
      ('se-poetry', "e", 500, 'book', '399167619db7bc63'),
      ('se-poetry', "Chapter", 2, null, '9d54a90026996348'),
      ('se-poetry', "“", 446, null, 'dcd43dd6648b01f6'),
      ('se-poetry', "o’", 172, null, '37ff068f014e61c7'),
      ('se-poetry', "NEVER", 112, null, '92ce26c276483640'),
      ('se-poetry', "the end", 10, null, '8f7f7f6fc2c8d489'),
      ('pg-46-christmas-carol', "the", 500, 'book', '372a1791a77bdb27'),
      ('pg-46-christmas-carol', "and", 500, 'book', 'ef7764c614e1576e'),
      ('pg-46-christmas-carol', "said", 221, null, 'b9d9c0e971c4a767'),
      ('pg-46-christmas-carol', "harbour", 0, null, '4f53cda18c2baa0c'),
      ('pg-46-christmas-carol', "of the", 168, null, '493a3c92fa608132'),
      ('pg-46-christmas-carol', "It was", 100, null, '72c6dd4d003ac23b'),
      ('pg-46-christmas-carol', "whale", 0, null, '4f53cda18c2baa0c'),
      ('pg-46-christmas-carol', "e", 500, 'book', '748405fe2c0aa9bc'),
      ('pg-46-christmas-carol', "Chapter", 0, null, '4f53cda18c2baa0c'),
      ('pg-46-christmas-carol', "“", 500, 'book', '4e665b89f9ecc10c'),
      ('pg-46-christmas-carol', "o’", 6, null, 'e91efb85f5482c84'),
      ('pg-46-christmas-carol', "NEVER", 44, null, 'a60947d1e01c9b70'),
      ('pg-46-christmas-carol', "the end", 9, null, '743f16ce0e7b018d'),
      ('se-pride-and-prejudice', "the", 500, 'book', 'f06dff6849ef0611'),
      ('se-pride-and-prejudice', "and", 500, 'book', '767f874b01cf9928'),
      ('se-pride-and-prejudice', "said", 402, null, 'd4699c9803671e67'),
      ('se-pride-and-prejudice', "harbour", 1, null, 'd85052f8dc2a6bf0'),
      ('se-pride-and-prejudice', "of the", 500, 'book', '17c66e997682fc45'),
      ('se-pride-and-prejudice', "It was", 257, null, '23b5a39932946405'),
      ('se-pride-and-prejudice', "whale", 0, null, '4f53cda18c2baa0c'),
      ('se-pride-and-prejudice', "e", 500, 'book', '083864e8016f52b1'),
      ('se-pride-and-prejudice', "Chapter", 0, null, '4f53cda18c2baa0c'),
      ('se-pride-and-prejudice', "“", 500, 'book', 'e92c3508663fb6e4'),
      ('se-pride-and-prejudice', "o’", 5, null, '6280e5580a4d1a7f'),
      ('se-pride-and-prejudice', "NEVER", 244, null, '2e3bc120aca5e6d8'),
      ('se-pride-and-prejudice', "the end", 10, null, '1590bb9e3e8d8ef1'),
    ];

/// The first 16 hex digits of the SHA-256 of the JSON list of [hits], each
/// as its CFI, resource, quote, chapter and excerpt.
String digest(Iterable<ReaderHit> hits) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          for (final hit in hits)
            [
              location(hit).cfi,
              location(hit).resource,
              location(hit).quote,
              location(hit).chapter,
              hit.excerpt,
            ],
        ]),
      ),
    )
    .toString()
    .substring(0, 16);

/// The book [name] of [_reportedByWebView], admitted as Bookfin admits it,
/// or null when it is a trial book that is not in .cache/epub-trial/books.
Publication? _book(String name) {
  final made = switch (name) {
    'frost' => (media.firstFrost, 'First Frost'),
    'salt' => (media.saltAndLantern, 'Salt and Lantern'),
    'winter' => (media.winterLedger, 'The Winter Ledger'),
    _ => null,
  };
  if (made case (final chapters, final title)) {
    return Publication.admit(
      media.epub(name, title, 'Bookfin Showcase', chapters),
    );
  }
  final file = File('.cache/epub-trial/books/$name.epub');
  return file.existsSync() ? Publication.admit(file.readAsBytesSync()) : null;
}

/// The search sections of [publication], in spine order.
List<SearchSection> _sections(Publication publication) {
  final steps = spineSteps(
    utf8.decode(publication.resources[publication.packagePath]!),
  );
  return [
    for (final (index, path) in publication.spine.indexed)
      SearchSection(
        index: index,
        path: path,
        xhtml: publication.resources[path]!,
        spine: steps[index],
      ),
  ];
}

void main() {
  group('the cases of reader.js search.test.cjs', () {
    test('a phrase across more than five inline nodes is one hit', () async {
      expect(
        await excerpts(
          '<p>A phrase <em>crosses</em> <b>several</b> <i>inline</i> '
              'nodes.</p>',
          'phrase crosses several inline nodes',
        ),
        ['phrase crosses several inline nodes'],
      );
    });

    test('a short section keeps each repeated occurrence', () async {
      expect(
        await excerpts('<p>Repeat phrase. Repeat phrase.</p>', 'Repeat phrase'),
        hasLength(2),
      );
    });

    test('a query that grows when lowercased is still found', () async {
      final phrase = 'İ' * 200;
      final report = await search([chapter(0, '<p>$phrase</p>')], phrase);
      expect(report.error, isNull);
      expect(report.hits, hasLength(1));
      expect(location(report.hits.single).quote, phrase.substring(0, 120));
    });

    test('text in the head and explicitly hidden text are not found', () async {
      final report = await search([
        chapter(
          0,
          '<p hidden="hidden">Needle</p><p style="display:none">Needle</p>'
          '<h1>Needle</h1>',
          head: '<title>Needle</title>',
        ),
      ], 'Needle');
      expect(report.hits, hasLength(1));
    });

    test('a letter that grows when lowercased does not shift the hit that '
        'follows it', () async {
      final report = await search([chapter(0, '<p>İ 🦦 AFTER</p>')], 'after');
      expect(report.hits.single.excerpt, 'AFTER');
      expect(location(report.hits.single).quote, 'AFTER');
    });

    test(
      'a section that cannot be searched makes the search incomplete',
      () async {
        final broken = SearchSection(
          index: 1,
          path: 'OPS/c1.xhtml',
          xhtml: utf8.encode(
            '<html><body><p>A searchable phrase.</body></html>',
          ),
          spine: '/6/4',
        );
        final report = await search([
          chapter(0, '<p>A searchable phrase.</p>'),
          broken,
        ], 'searchable');
        expect(report.hits, hasLength(1));
        expect(
          report.error,
          'Search is incomplete. A chapter could not be searched. '
          'Retry or use Contents.',
        );
      },
    );
  });

  group('the query', () {
    test('an empty query, a query of only white space, and a query longer '
        'than 256 characters are refused', () async {
      final book = [chapter(0, '<p>${'a' * 300}</p>')];
      for (final query in ['', ' \n\t ', 'a' * 257]) {
        final report = await search(book, query);
        expect(report.hits, isEmpty, reason: query);
        expect(report.error, 'Enter between 1 and 256 characters.');
      }
      expect((await search(book, 'a' * 256)).error, isNull);
    });

    test('case and runs of white space do not matter, and the excerpt keeps '
        'the book text', () async {
      expect(
        await excerpts(
          '<p>the Harbour\n   LIGHT shone</p>',
          ' harbour \t light ',
        ),
        ['Harbour\n   LIGHT'],
      );
    });

    test('a capital sigma at the end of a query word becomes a final sigma, '
        'as JavaScript lowercases a whole query', () async {
      expect(await excerpts('<p>ο δρόμος</p>', 'ΔΡΌΜΟΣ'), ['δρόμος']);
      // The book text folds one character at a time, so its capital sigma
      // stays a plain sigma and no longer matches.
      expect(await excerpts('<p>Ο ΔΡΌΜΟΣ</p>', 'ΔΡΌΜΟΣ'), isEmpty);
    });

    test(
      'a NEXT LINE character is not white space, as in JavaScript',
      () async {
        final report = await search([chapter(0, '<p>a</p>')], '\u0085');
        expect(report.error, isNull);
        expect(report.hits, isEmpty);
      },
    );
  });

  group('the searched text', () {
    test('a change of block element separates words', () async {
      expect(await excerpts('<p>end</p><p>start</p>', 'end start'), [
        'endstart',
      ]);
      expect(
        await excerpts(
          '<div><span>end</span><span>start</span></div>',
          'endstart',
        ),
        ['endstart'],
      );
    });

    test('text outside any block after a block runs into the next block, '
        'as in reader.js', () async {
      expect(await excerpts('<p>one</p>two<p>three</p>', 'one two'), [
        'onetwo',
      ]);
      expect(await excerpts('<p>one</p>two<p>three</p>', 'twothree'), [
        'twothree',
      ]);
    });

    test('aria-hidden, visibility:hidden, script, style and template text is '
        'not found', () async {
      expect(
        await excerpts(
          '<p aria-hidden="true">Needle</p>'
              '<div style="color: red; VISIBILITY : hidden"><span>Needle</span></div>'
              '<script>Needle</script><style>Needle</style>'
              '<template><p>Needle</p></template>'
              '<p aria-hidden="false">Needle</p>',
          'needle',
        ),
        ['Needle'],
      );
    });

    test(
      'CDATA text is not searched, but an excerpt across it keeps it',
      () async {
        expect(await excerpts('<p><![CDATA[needle]]></p>', 'needle'), isEmpty);
        expect(
          await excerpts('<p>one <![CDATA[ two ]]> three</p>', 'one three'),
          ['one  two  three'],
        );
      },
    );

    test('overlapping occurrences are each a hit', () async {
      expect(await excerpts('<p>aaaa</p>', 'aa'), hasLength(3));
    });

    test('an excerpt is at most 160 characters of the matched text', () async {
      final phrase = List.generate(40, (index) => 'word$index').join(' ');
      final hits = await excerpts('<p>$phrase</p>', phrase.substring(0, 200));
      expect(hits.single, phrase.substring(0, 160));
    });
  });

  group('limits', () {
    test('a section gives at most 500 hits, and more makes the search '
        'incomplete', () async {
      final exact = await search([chapter(0, '<p>${'x ' * 500}</p>')], 'x');
      expect(exact.hits, hasLength(500));
      expect(exact.error, isNull);
      final more = await search([
        chapter(0, '<p>${'x ' * 501}</p>'),
        chapter(1, '<p>none</p>'),
      ], 'x');
      expect(more.hits, hasLength(500));
      expect(
        more.error,
        'Search is incomplete. Only the first 500 matches per chapter are '
        'shown.',
      );
    });

    test('the book gives at most 500 hits, and more makes the search '
        'incomplete', () async {
      final exact = await search([
        chapter(0, '<p>${'x ' * 250}</p>'),
        chapter(1, '<p>${'x ' * 250}</p>'),
      ], 'x');
      expect(exact.hits, hasLength(500));
      expect(exact.error, isNull);
      final more = await search([
        chapter(0, '<p>${'x ' * 600}</p>'),
        chapter(1, '<p>x</p>'),
      ], 'x');
      expect(more.hits, hasLength(500));
      expect(
        more.error,
        'Search is incomplete. Only the first 500 matches are shown. Use a '
        'longer phrase.',
      );
    });
  });

  group('hits', () {
    test('a hit opens on a place whose text starts with the match', () async {
      const body =
          '<h1 id="one">The river</h1><p>Quiet water. <em>Quiet</em> '
          'stones.</p><h2 id="two">The bridge</h2><p>Quiet arches.</p>';
      final section = chapter(3, body);
      final report = await search(
        [section],
        'QUIET',
        contents: const [
          ContentsEntry('The river', 'c3.xhtml#one'),
          ContentsEntry('The bridge', 'c3.xhtml#two'),
        ],
      );
      final dom = DomSection.parse(utf8.decode(section.xhtml));
      expect(
        [for (final hit in report.hits) location(hit).chapter],
        ['The river', 'The river', 'The bridge'],
      );
      for (final hit in report.hits) {
        final saved = location(hit);
        expect(saved.resource, 'OPS/c3.xhtml');
        expect(saved.cfi, startsWith('epubcfi(/6/8!/4/'));
        expect(saved.progress, isNull);
        final place = placeOf(dom, 3, saved.cfi)!;
        expect(quoteAt(dom, place), startsWith(hit.excerpt));
        expect(hit.excerpt, 'Quiet');
      }
    });

    test('hits come in spine order across batches of sections', () async {
      final book = [
        for (var index = 0; index < 20; index++)
          chapter(index, '<p>needle $index needle</p>'),
      ];
      final report = await search(book, 'needle');
      expect(
        [for (final hit in report.hits) location(hit).resource],
        [
          for (var index = 0; index < 20; index++) ...[
            'OPS/c$index.xhtml',
            'OPS/c$index.xhtml',
          ],
        ],
      );
    });
  });

  group('worker isolates', () {
    test('sections go to the worker in batches of at most 8', () async {
      final batches = <int>[];
      Future<R> counted<M, R>(FutureOr<R> Function(M) work, M input) async {
        final result = await work(input);
        batches.add((result as List).length);
        return result;
      }

      await searchBook(
        [for (var index = 0; index < 20; index++) chapter(index, '<p>x</p>')],
        'x',
        const [],
        'OPS/book.opf',
        isCurrent: () => true,
        hop: counted,
      );
      expect(batches, [8, 8, 4]);
    });

    test('a cancel stops the search between batches', () async {
      var batches = 0;
      var current = true;
      Future<R> cancelling<M, R>(FutureOr<R> Function(M) work, M input) async {
        batches++;
        current = false;
        return work(input);
      }

      final report = await searchBook(
        [for (var index = 0; index < 20; index++) chapter(index, '<p>x</p>')],
        'x',
        const [],
        'OPS/book.opf',
        isCurrent: () => current,
        hop: cancelling,
      );
      expect(batches, 1);
      expect(report.hits, isEmpty);
      expect(report.error, isNull);
    });

    test(
      'the search runs in Isolate.run and finds what it finds inline',
      () async {
        final book = [
          for (var index = 0; index < 10; index++)
            chapter(index, '<p>Harbour $index. The harbour light.</p>'),
        ];
        final there = await searchBook(
          book,
          'harbour',
          const [],
          'OPS/book.opf',
          isCurrent: () => true,
        );
        final here = await search(book, 'harbour');
        expect(there.hits, hasLength(20));
        expect(
          [for (final hit in there.hits) location(hit).toJson()],
          [for (final hit in here.hits) location(hit).toJson()],
        );
      },
    );
  });

  test('every search that the WebView reader reported in the showcase and '
      'trial books finds the same hits in the same order', () async {
    final books = <String, (Publication, List<SearchSection>)?>{};
    var compared = 0;
    for (final (name, query, count, error, hits) in _reportedByWebView) {
      final book = books.putIfAbsent(name, () {
        final publication = _book(name);
        return publication == null
            ? null
            : (publication, _sections(publication));
      });
      if (book == null) continue;
      final (publication, sections) = book;
      final report = await searchBook(
        sections,
        query,
        publication.contents,
        publication.packagePath,
        isCurrent: () => true,
      );
      final reason = '$name "$query"';
      expect(report.hits, hasLength(count), reason: reason);
      expect(report.error, switch (error) {
        'book' =>
          'Search is incomplete. Only the first 500 matches are shown. Use '
              'a longer phrase.',
        'chapter' =>
          'Search is incomplete. Only the first 500 matches per chapter are '
              'shown.',
        _ => null,
      }, reason: reason);
      expect(digest(report.hits), hits, reason: reason);
      compared++;
    }
    expect(compared, greaterThanOrEqualTo(39));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
