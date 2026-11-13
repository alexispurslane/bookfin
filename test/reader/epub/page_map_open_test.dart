// A book opens with its kept page map (t5-4l4d, design A of
// docs/research/epub-layout-cache.md). The page source trusts the map at
// open, so the true page and its number show at once and the whole-book
// work skips every section that the map holds. Each page that a run cuts
// from a kept start checks the map, and the first page that contradicts it
// forgets the map. The map is written once the whole book is laid out.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_maps.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/sync/device.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart'
    show TestScheduler, book, content, paragraphs, placeIn, smallPage;

/// The fingerprint of a release build's text engine.
const _engine = 'install-1\nbuild-1\nen-US';

/// A book of six sections of several pages each.
Publication _sixSections() =>
    book([for (var i = 0; i < 6; i++) paragraphs(16, label: 'S$i')]);

/// A book of three sections whose middle one mixes short paragraphs, white
/// space between blocks, and a table, so that some places lie in white
/// space between two pages.
Publication _mixedSections() => book([
  paragraphs(6, label: 'A'),
  [
    '<h2>Middle</h2>',
    for (var i = 0; i < 30; i++) '<p>${prose(i % 3 + 1, 'M $i')}</p>',
    '<table>',
    for (var i = 0; i < 24; i++)
      '<tr><td>Row $i</td><td>${prose(1, 'Cell $i')}</td></tr>',
    '</table>',
    for (var i = 30; i < 50; i++) '<p>${prose(i % 4 + 1, 'M $i')}</p>',
  ].join('\n  '),
  paragraphs(6, label: 'C'),
]);

/// A book of three sections whose middle one is one table of 120 rows, of
/// 240 cells.
Publication _tableBook() => book([
  paragraphs(4, label: 'A'),
  [
    '<table>',
    for (var i = 0; i < 120; i++)
      '<tr><td>Row $i</td><td>${prose(i % 3 + 1, 'Cell $i')}</td></tr>',
    '</table>',
  ].join('\n'),
  paragraphs(4, label: 'C'),
]);

/// A book of three sections whose middle one has a paragraph of 300
/// sentences, of about 29,000 code units.
Publication _paragraphBook() => book([
  paragraphs(4, label: 'A'),
  '<p>${prose(2, 'Before')}</p><p>${prose(300, 'Long')}</p>',
  paragraphs(4, label: 'C'),
]);

/// The place [fraction] of the way through the longest text of [section].
EpubPlace _inLongest(PreparedSection section, double fraction) {
  final text = section.dom.texts.reduce(
    (a, b) => a.text.length >= b.text.length ? a : b,
  );
  return EpubPlace(
    section.index,
    text.order,
    (text.text.length * fraction).floor(),
  );
}

/// [section] with its kept measures replaced by [measures].
KeptSection _measured(KeptSection section, SectionMeasures measures) =>
    KeptSection(
      section.starts,
      firsts: section.firsts,
      visible: section.visible,
      complete: section.complete,
      measures: measures,
    );

/// [section] without its page [index], as a map that missed a page start.
KeptSection _leaveOut(KeptSection section, int index) => KeptSection(
  [...section.starts]..removeAt(index),
  firsts: [...section.firsts]..removeAt(index),
  visible: (
    starts: [...section.visible.starts]..removeAt(index),
    length: section.visible.length,
  ),
  complete: section.complete,
);

/// A download in a folder of its own, as Downloads keeps it.
Future<File> _download() async {
  final folder = await Directory.systemTemp.createTemp('bookfin-map-open-');
  addTearDown(() => folder.delete(recursive: true));
  return File('${folder.path}/complete').writeAsBytes([1, 2, 3]);
}

/// Waits until [test] holds, for at most two seconds of file access.
Future<void> _eventually(Future<bool> Function() test) async {
  for (var tries = 0; tries < 400; tries++) {
    if (await test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('The condition never held.');
}

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late File download;
  final sources = <PageSource>[];

  setUp(() async {
    scheduler = TestScheduler();
    download = await _download();
  });
  tearDown(() {
    for (final source in sources) {
      source.dispose();
    }
    sources.clear();
  });

  BookPageMaps mapsOf(Publication publication, {Future<String?>? engine}) =>
      BookPageMaps(
        download,
        book: publication.identity,
        engine: engine ?? Future.value(_engine),
      );

  PageSource open(
    Publication publication, {
    BookPageMaps? pageMaps,
    PageSettings settings = readerPage,
    Duration budget = const Duration(milliseconds: 4),
  }) {
    final source = PageSource(
      publication,
      schedule: scheduler.schedule,
      budget: budget,
      pageMaps: pageMaps,
    )..settings = settings;
    sources.add(source);
    return source;
  }

  /// The anchored page of [source] at [place], as an open shows it.
  Future<LaidPage> pageAt(PageSource source, EpubPlace place) async {
    await scheduler.until(source.section(place.section));
    return scheduler.until(source.pageAt(place, anchored: true, urgent: true));
  }

  /// The first place of section [index].
  Future<EpubPlace> startOf(PageSource source, int index) async {
    final dom = (await scheduler.until(source.section(index))).dom;
    return EpubPlace(index, dom.body.order, 0);
  }

  /// The pages of section [index], from its first page by turns.
  Future<List<LaidPage>> pagesOf(PageSource source, int index) async {
    final pages = [await pageAt(source, await startOf(source, index))];
    while (!pages.last.last) {
      pages.add((await scheduler.until(source.after(pages.last)))!);
    }
    return pages;
  }

  /// Opens [publication] at section 0, lets the whole book lay out, and
  /// waits for its map to be kept. Returns the map and the number of steps.
  Future<(List<KeptSection>, int)> layOutWhole(
    Publication publication, {
    Duration budget = const Duration(milliseconds: 4),
  }) async {
    final pageMaps = mapsOf(publication);
    final source = open(publication, pageMaps: pageMaps, budget: budget);
    final before = scheduler.ran.length;
    source.show(await pageAt(source, await startOf(source, 0)));
    await scheduler.settle();
    final steps = scheduler.ran.length - before;
    late List<KeptSection> kept;
    await _eventually(() async {
      final read = await pageMaps.read(readerPage);
      if (read != null) kept = read;
      return read != null;
    });
    source.dispose();
    return (kept, steps);
  }

  test('the map is written once the whole book is laid out', () async {
    final publication = _sixSections();
    final pageMaps = mapsOf(publication);
    final source = open(publication, pageMaps: pageMaps);
    final shown = await pageAt(source, await startOf(source, 2));
    source.show(shown);
    expect(await pageMaps.read(readerPage), isNull);

    await scheduler.settle();
    final sections = [
      for (var index = 0; index < 6; index++)
        if (await pagesOf(source, index) case final pages)
          KeptSection(
            [for (final page in pages) page.start],
            firsts: [for (final page in pages) page.startPlace],
            // The page index's visible starts, which the scrub bar reads.
            visible: source.bookPages.value.parts[index]!.visible!,
            complete: true,
          ),
    ];

    await _eventually(() async => await pageMaps.read(readerPage) != null);
    expect(await pageMaps.read(readerPage), sections);
  });

  test('a narrower note preserves a kept later page in its shared long '
      'paragraph and the map survives reopen', () async {
    final publication = book([
      '<p>Read the note.<a epub:type="noteref" href="s1.xhtml#n">1</a></p>',
      '<aside id="n" epub:type="footnote"><p>The note begins here.</p>'
          '<p>${prose(300, 'Note')}</p></aside>',
    ]);
    final (kept, _) = await layOutWhole(publication);
    final at = kept[1].starts.length * 3 ~/ 4;
    final place = kept[1].firsts[at]!;
    final pageMaps = mapsOf(publication);
    final source = open(publication, pageMaps: pageMaps);
    var dropped = 0;
    source.keptMapDropped.addListener(() => dropped++);
    final pager = EpubPager(
      EpubDocument(publication),
      source: source,
      onPlace: (_) {},
      onWarning: (_) {},
    );
    addTearDown(pager.dispose);
    pager.present(readerPage);
    await scheduler.settle();
    expect(pager.shown.value, isNotNull);

    for (final width in [240.0, 340.0, 240.0]) {
      final note = (await scheduler.until(
        pager.note((href: 'text/s1.xhtml#n', noteref: true), width: width),
      ))!;
      expect(note.page.startPlace, isNotNull);
      note.dispose();
    }

    final later = await pageAt(source, place);
    expect(later.startPlace, place);
    expect(later.start, kept[1].starts[at]);
    expect(dropped, 0);
    expect(await pageMaps.read(readerPage), isNotNull);
    source.checkInvariants();
    final expected = content(later);
    pager.dispose();

    final reopened = open(publication, pageMaps: mapsOf(publication));
    reopened.keptMapDropped.addListener(() => dropped++);
    expect(content(await pageAt(reopened, place)), expected);
    expect(dropped, 0);
    expect(reopened.lineSearches, 0);
  });

  test('a note that disproves kept table widths drops the map and uses fresh '
      'widths', () async {
    final publication = book([
      '<aside id="n"><p>The note begins.</p><table><tr><td>Speaker</td>'
          '<td>${prose(12)}</td></tr></table></aside>',
    ]);
    final (truth, _) = await layOutWhole(publication);
    final plain = open(publication);
    final prepared = await scheduler.until(plain.section(0));
    final expected = (await plain.excerpt(
      prepared,
      DomSelection(prepared.dom.elementById('n')!),
      width: 240,
    ))!;
    addTearDown(expected.dispose);

    final kept = truth.single;
    final entry = kept.measures.tables.entries.single;
    final widths = Float64List.fromList(entry.value)
      ..[0] *= 2
      ..[1] *= 2;
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, [
      _measured(kept, SectionMeasures(tables: {entry.key: widths})),
    ]);
    final seeded = open(publication, pageMaps: pageMaps);
    final section = await scheduler.until(seeded.section(0));
    await _eventually(() async => seeded.bookPages.value.complete);
    var dropped = 0;
    seeded.keptMapDropped.addListener(() => dropped++);

    final page = (await seeded.excerpt(
      section,
      DomSelection(section.dom.elementById('n')!),
      width: 240,
    ))!;
    addTearDown(page.dispose);

    expect(dropped, 1);
    expect(pageKey(page), pageKey(expected));
    await _eventually(() async => await pageMaps.read(readerPage) == null);
    seeded.checkInvariants();
  });

  test('an active note rebuilds when another page rejects its kept table '
      'widths', () async {
    final publication = book([
      '<aside id="n"><table><tr><td>Speaker</td>'
          '<td>${prose(300)}</td></tr>'
          '<tr><td>Later</td><td>Last row.</td></tr></table></aside>',
    ]);
    final (truth, _) = await layOutWhole(publication);
    final plain = open(publication);
    final prepared = await scheduler.until(plain.section(0));
    final expected = (await plain.excerpt(
      prepared,
      DomSelection(prepared.dom.elementById('n')!),
      width: 320,
    ))!;
    addTearDown(expected.dispose);

    final kept = truth.single;
    final entry = kept.measures.tables.entries.single;
    // Only the later row disproves the map. Its wrong first-cell extent
    // changes both columns, including those of the long first row.
    final widths = Float64List.fromList(entry.value)
      ..[4] = 200
      ..[5] = 200;
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, [
      _measured(kept, SectionMeasures(tables: {entry.key: widths})),
    ]);
    final seeded = open(publication, pageMaps: pageMaps, budget: Duration.zero);
    final section = await scheduler.until(seeded.section(0));
    await _eventually(() async => seeded.bookPages.value.complete);
    final before = LayoutRun.laidOutUnits;
    var finished = false;
    final pending = seeded
        .excerpt(
          section,
          DomSelection(section.dom.elementById('n')!),
          width: 320,
        )
        .then((page) {
          finished = true;
          addTearDown(page!.dispose);
          return page;
        });
    // Wait for actual cell text, not an assumed number of layout steps.
    while (LayoutRun.laidOutUnits == before && !finished) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(finished, isFalse);
    var dropped = 0;
    seeded.keptMapDropped.addListener(() => dropped++);
    final later = kept.starts.indexWhere(
      (start) => start.item == entry.key && start.line == 1,
    );
    expect(later, greaterThanOrEqualTo(0));
    await pageAt(seeded, kept.firsts[later]!);
    expect(dropped, 1);
    expect(
      finished,
      isFalse,
      reason: 'rejection interrupts the long first row',
    );

    final page = await pending;
    // Compare the actual column geometry before the full page signature,
    // so a failure reports the small, useful difference first.
    expect(
      page.pieces.take(2).map((piece) => (piece.x, piece.paragraph.width)),
      expected.pieces.take(2).map((piece) => (piece.x, piece.paragraph.width)),
    );
    expect(pageKey(page), pageKey(expected));
    seeded.checkInvariants();
  });

  test('a delayed note rejects kept widths after its preparation left the '
      'cache', () async {
    final publication = book([
      '<aside id="n"><table><tr><td>Speaker</td>'
          '<td>${prose(12)}</td></tr></table></aside>',
      for (var index = 1; index < 8; index++) paragraphs(1),
    ]);
    final (truth, _) = await layOutWhole(publication);
    final plain = open(publication);
    final prepared = await scheduler.until(plain.section(0));
    final expected = (await plain.excerpt(
      prepared,
      DomSelection(prepared.dom.elementById('n')!),
      width: 240,
    ))!;
    addTearDown(expected.dispose);
    final kept = truth.first;
    final entry = kept.measures.tables.entries.single;
    final widths = Float64List.fromList(entry.value)
      ..[0] *= 2
      ..[1] *= 2;
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, [
      _measured(kept, SectionMeasures(tables: {entry.key: widths})),
      ...truth.skip(1),
    ]);
    final seeded = open(publication, pageMaps: pageMaps);
    final section = await scheduler.until(seeded.section(0));
    await _eventually(() async => seeded.bookPages.value.complete);
    // The caller still holds the prepared note while other sections fill
    // the source's preparation cache, as delayed backlink lookup can do.
    for (var index = 1; index < 8; index++) {
      await scheduler.until(seeded.section(index));
    }
    var dropped = 0;
    seeded.keptMapDropped.addListener(() => dropped++);

    final page = (await seeded.excerpt(
      section,
      DomSelection(section.dom.elementById('n')!),
      width: 240,
    ))!;
    addTearDown(page.dispose);

    expect(dropped, 1);
    expect(pageKey(page), pageKey(expected));
    seeded.checkInvariants();
  });

  test('a second open of a book shows its true page number at once', () async {
    final publication = _sixSections();
    final first = open(publication, pageMaps: mapsOf(publication));
    final section = await scheduler.until(first.section(3));
    final place = placeIn(section, .6, 5);
    final truePage = await scheduler.until(
      first.pageAt(place, anchored: false),
    );
    first.show(truePage);
    await scheduler.settle();
    final number = first.numberOf(truePage);
    final truth = content(truePage);
    await _eventually(
      () async => await mapsOf(publication).read(readerPage) != null,
    );
    first.dispose();

    final second = open(publication, pageMaps: mapsOf(publication));
    final page = await pageAt(second, place);

    expect(content(page), truth);
    expect(second.isTrue(page), isTrue);
    expect(second.numberOf(page), number);
    expect(number?.count, isNotNull);
  });

  test('a seeded section is not laid out again in the background', () async {
    final publication = _sixSections();
    final (_, firstSteps) = await layOutWhole(
      publication,
      budget: Duration.zero,
    );

    final second = open(
      publication,
      pageMaps: mapsOf(publication),
      budget: Duration.zero,
    );
    final before = scheduler.ran.length;
    final page = await pageAt(
      second,
      placeIn(await scheduler.until(second.section(3)), .5),
    );
    expect([
      for (var index = 0; index < 6; index++) second.laidOut(index),
    ], everyElement(isTrue));
    second.show(page);
    await scheduler.settle();

    // The pages around the shown page cost a few steps each. The whole
    // book's main runs cost one step for each paragraph.
    expect(scheduler.ran.length - before, lessThan(firstSteps ~/ 3));
  });

  test('a viewed page that disagrees with the kept map forgets it and the '
      'book lays out again', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final pageMaps = mapsOf(publication);
    // Section 2's map leaves out its third page start, so its second page
    // seems to run on to the fourth.
    final wrong = [...truth];
    wrong[2] = _leaveOut(truth[2], 2);
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    final first = await pageAt(source, await startOf(source, 2));
    source.show(first);
    expect(source.numberOf(first)?.count, wrong[2].starts.length);
    expect(await pageMaps.read(readerPage), wrong);

    final second = (await scheduler.until(source.after(first)))!;
    expect(second.start, truth[2].starts[1]);
    await _eventually(() async => await pageMaps.read(readerPage) == null);
    expect(source.numberOf(second), isNull);

    final third = (await scheduler.until(source.after(second)))!;
    expect(third.start, truth[2].starts[2]);

    source.show(third);
    await scheduler.settle();
    expect(source.numberOf(third), (number: 3, count: truth[2].starts.length));
    await _eventually(() async => await pageMaps.read(readerPage) != null);
    expect(await pageMaps.read(readerPage), truth);
  });

  test('turning through a book whose map is wrong shows the same pages as '
      'without a map', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final wrong = [
      for (final (index, section) in truth.indexed)
        index.isOdd && section.starts.length > 2
            ? _leaveOut(section, 1)
            : section,
    ];

    Future<List<List<Object?>>> turnThrough(BookPageMaps? pageMaps) async {
      final source = open(publication, pageMaps: pageMaps);
      final pages = [await pageAt(source, await startOf(source, 0))];
      source.show(pages.last);
      while (true) {
        final next = await scheduler.until(source.after(pages.last));
        if (next == null) break;
        source.show(next);
        source.checkInvariants();
        pages.add(next);
      }
      final seen = [for (final page in pages) content(page)];
      source.dispose();
      return seen;
    }

    final plain = await turnThrough(null);
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, wrong);

    expect(await turnThrough(pageMaps), plain);
  });

  test('a kept start whose page does not hold the saved place opens the '
      'page at the line that holds it', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final plain = open(publication);
    final pages = await pagesOf(plain, 2);
    final place = pages[2].startPlace!;
    final anchored = content(await pageAt(plain, place));
    final pageMaps = mapsOf(publication);
    final wrong = [...truth];
    wrong[2] = _leaveOut(truth[2], 2);
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    final page = await pageAt(source, place);

    expect(content(page), anchored);
    expect(page.startPlace, place);
    await _eventually(() async => await pageMaps.read(readerPage) == null);
  });

  /// The places of section [index] of [source]: the start, the middle and
  /// the end of each of its text nodes, white space included.
  Future<List<EpubPlace>> placesOf(PageSource source, int index) async {
    final dom = (await scheduler.until(source.section(index))).dom;
    return [
      for (final text in dom.texts)
        for (final offset in {0, text.text.length ~/ 2, text.text.length})
          EpubPlace(index, text.order, offset),
    ];
  }

  /// The places of section [section] that [pick] picks, the true page that
  /// holds each of them in a book laid out with no kept map, the page that
  /// the anchored request of a source with [publication]'s kept map opens,
  /// and that source.
  Future<(List<EpubPlace>, List<LaidPage>, List<LaidPage>, PageSource)>
  openBoth(
    Publication publication,
    List<EpubPlace> Function(List<EpubPlace> all) pick,
    int section,
  ) async {
    await layOutWhole(publication);
    final plain = open(publication);
    final places = pick(await placesOf(plain, section));
    final expected = [
      for (final place in places)
        await scheduler.until(plain.pageAt(place, anchored: false)),
    ];
    final seeded = open(publication, pageMaps: mapsOf(publication));
    await scheduler.until(seeded.section(section));
    final found = [for (final place in places) await pageAt(seeded, place)];
    return (places, expected, found, seeded);
  }

  test('a jump into a seeded section finds its page without a line '
      'search', () async {
    final publication = _sixSections();
    final (_, expected, found, source) = await openBoth(
      publication,
      (all) => [all[all.length * 3 ~/ 5]],
      3,
    );

    expect(content(found.single), content(expected.single));
    expect(source.isTrue(found.single), isTrue);
    expect(source.numberOf(found.single)?.count, isNotNull);
    expect(source.lineSearches, 0);
  });

  test('every place of a seeded section opens the true page that holds it, '
      'as with no kept map', () async {
    final publication = _mixedSections();
    final (_, expected, found, source) = await openBoth(
      publication,
      (all) => all,
      1,
    );

    expect(
      [for (final page in found) content(page)],
      [for (final page in expected) content(page)],
    );
    expect(source.lineSearches, 0);
    source.checkInvariants();
  });

  test('a place after the last shown place of a kept page opens on the next '
      'page', () async {
    final publication = _mixedSections();
    final (places, expected, found, source) = await openBoth(
      publication,
      (all) => all,
      1,
    );
    // The places that come before the first place of the page that holds
    // them: white space after the last thing that the page before shows.
    final next = [
      for (final (index, page) in expected.indexed)
        if (page.start != const PageStart(0, 0) &&
            page.startPlace!.compareTo(places[index]) > 0)
          index,
    ];

    expect(next, isNotEmpty);
    expect(
      [for (final index in next) content(found[index])],
      [for (final index in next) content(expected[index])],
    );
    expect(source.lineSearches, 0);
  });

  test('a place in a later cell of a table row split across pages opens '
      'the page that shows it', () async {
    // The first cell of each row runs on to a second page, and the second
    // cell shows on the first page.
    final publication = book([
      '<table>${[for (var i = 0; i < 3; i++) '<tr><td>${prose(40, 'Long $i')}</td><td>${prose(1, 'Short $i')}</td></tr>'].join()}</table>',
    ]);
    final (places, expected, found, source) = await openBoth(
      publication,
      (all) => all,
      0,
    );
    final split = [
      for (final (index, page) in expected.indexed)
        if (page.startPlace case final first?
            when first.compareTo(places[index]) < 0 &&
                expected.any(
                  (other) =>
                      other.start.part > 0 &&
                      other.startPlace!.compareTo(places[index]) < 0 &&
                      other.start.compareTo(page.start) > 0,
                ))
          index,
    ];

    expect(split, isNotEmpty);
    expect(
      [for (final page in found) content(page)],
      [for (final page in expected) content(page)],
    );
    expect(source.lineSearches, 0);
  });

  test('a jump into the middle of a kept table does not measure the whole '
      'table', () async {
    final publication = _tableBook();
    await layOutWhole(publication);
    final plain = open(publication);
    final place = placeIn(await scheduler.until(plain.section(1)), .6);
    final expected = await scheduler.until(
      plain.pageAt(place, anchored: false),
    );
    final seeded = open(publication, pageMaps: mapsOf(publication));
    await scheduler.until(seeded.section(1));
    final before = LayoutRun.measuredCells;

    final page = await pageAt(seeded, place);

    expect(content(page), content(expected));
    expect(seeded.isTrue(page), isTrue);
    // It checks the kept widths of the rows of the pages that it lays out.
    expect(LayoutRun.measuredCells - before, lessThan(240 ~/ 2));
  });

  test('a kept width that disagrees with a fresh one forgets the '
      'map', () async {
    final publication = _tableBook();
    final (truth, _) = await layOutWhole(publication);
    final kept = truth[1];
    final MapEntry(key: table, value: widths) =
        kept.measures.tables.entries.single;
    // A page in the middle of the table, and its first row.
    final at = kept.starts.length ~/ 2;
    final row = kept.starts[at].line;
    expect(kept.starts[at].item, table);
    // The narrowest width of the row's first cell, one pixel narrower. It
    // is not the narrowest width of its column, so the pages stay the same.
    final wrong = [...truth];
    wrong[1] = _measured(
      kept,
      SectionMeasures(
        tables: {table: Float64List.fromList(widths)..[row * 4] -= 1},
      ),
    );
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    var dropped = 0;
    source.keptMapDropped.addListener(() => dropped++);
    final page = await pageAt(source, kept.firsts[at]!);

    expect(page.start, kept.starts[at]);
    expect(dropped, 1);
    await _eventually(() async => await pageMaps.read(readerPage) == null);
  });

  test("a jump into the middle of a kept long paragraph does not count its "
      "earlier segments' lines", () async {
    final publication = _paragraphBook();
    await layOutWhole(publication);
    final plain = open(publication);
    final section = await scheduler.until(plain.section(1));
    final place = _inLongest(section, .75);
    final expected = await scheduler.until(
      plain.pageAt(place, anchored: false),
    );
    final seeded = open(publication, pageMaps: mapsOf(publication));
    await scheduler.until(seeded.section(1));
    final before = LayoutRun.laidOutUnits;

    final page = await pageAt(seeded, place);

    expect(content(page), content(expected));
    expect(seeded.isTrue(page), isTrue);
    // The paragraph has about 29,000 code units.
    expect(LayoutRun.laidOutUnits - before, lessThan(29000 ~/ 4));
  });

  test('a kept line count that disagrees with a fresh one forgets the '
      'map', () async {
    final publication = _paragraphBook();
    final (truth, _) = await layOutWhole(publication);
    final kept = truth[1];
    final MapEntry(key: paragraph, value: segments) =
        kept.measures.paragraphs.entries.single;
    // A page in the last quarter of the paragraph, and the segment of its
    // first line.
    final at = kept.starts.length * 3 ~/ 4;
    final start = kept.starts[at];
    expect(start.item, paragraph);
    final segment = segments.lines.lastIndexWhere(
      (lines) => lines <= start.line,
    );
    expect(segment + 1, lessThan(segments.lines.length));
    // The lines before the segment after it, one more than they are.
    final wrong = [...truth];
    wrong[1] = _measured(
      kept,
      SectionMeasures(
        paragraphs: {
          paragraph: (
            starts: segments.starts,
            lines: [...segments.lines]..[segment + 1] += 1,
          ),
        },
      ),
    );
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    var dropped = 0;
    source.keptMapDropped.addListener(() => dropped++);
    final page = await pageAt(source, kept.firsts[at]!);

    expect(page.start, start);
    expect(dropped, 1);
    await _eventually(() async => await pageMaps.read(readerPage) == null);
  });

  test('the scrub bar names the page under the finger in a seeded '
      'section', () async {
    final publication = _sixSections();
    await layOutWhole(publication);
    final plain = open(publication);
    plain.show(await pageAt(plain, await startOf(plain, 0)));
    await scheduler.settle();
    final laidOut = plain.bookPages.value;

    final seeded = open(publication, pageMaps: mapsOf(publication));
    final page = await pageAt(seeded, await startOf(seeded, 2));
    final index = seeded.bookPages.value;

    expect(seeded.isTrue(page), isTrue);
    expect(index.complete, isTrue);
    // The scrub bar places each page by where it starts in the part's
    // visible characters (BookMap).
    for (var part = 0; part < 6; part++) {
      expect(index.parts[part]?.visible, isNotNull);
      expect(
        index.parts[part]!.visible!.starts,
        laidOut.parts[part]!.visible!.starts,
      );
      expect(
        index.parts[part]!.visible!.length,
        laidOut.parts[part]!.visible!.length,
      );
    }
  });

  test('a viewed page whose first place disagrees with the map forgets '
      'it', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final pageMaps = mapsOf(publication);
    final kept = truth[2];
    final moved = kept.firsts[1]!;
    final wrong = [...truth];
    wrong[2] = KeptSection(
      kept.starts,
      firsts: [...kept.firsts]
        ..[1] = EpubPlace(moved.section, moved.node, moved.offset + 1),
      visible: kept.visible,
      complete: true,
    );
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    var dropped = 0;
    source.keptMapDropped.addListener(() => dropped++);
    final first = await pageAt(source, await startOf(source, 2));
    source.show(first);
    expect(dropped, 0);
    final second = (await scheduler.until(source.after(first)))!;

    expect(second.start, kept.starts[1]);
    expect(dropped, 1);
    await _eventually(() async => await pageMaps.read(readerPage) == null);
  });

  test('a kept map with another number of sections is not used', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final pageMaps = mapsOf(publication);
    await pageMaps.write(readerPage, truth.take(5).toList());

    final source = open(publication, pageMaps: pageMaps);
    final page = await pageAt(
      source,
      placeIn(await scheduler.until(source.section(1)), .5),
    );

    expect(source.numberOf(page), isNull);
    expect(source.laidOut(5), isFalse);
  });

  test('a kept map whose section does not start at its first visible '
      'character is not used', () async {
    final publication = _sixSections();
    final (truth, _) = await layOutWhole(publication);
    final pageMaps = mapsOf(publication);
    final kept = truth[1];
    final wrong = [...truth];
    wrong[1] = KeptSection(
      kept.starts,
      firsts: kept.firsts,
      visible: (
        starts: [for (final start in kept.visible.starts) start + 1],
        length: kept.visible.length + 1,
      ),
      complete: true,
    );
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    final page = await pageAt(
      source,
      placeIn(await scheduler.until(source.section(1)), .5),
    );

    expect(source.numberOf(page), isNull);
    expect(source.laidOut(5), isFalse);
  });

  test('a debug build neither reads nor writes page maps', () async {
    final publication = _sixSections();
    final pageMaps = mapsOf(
      publication,
      engine: textEngineFingerprint(debug: true),
    );
    final source = open(publication, pageMaps: pageMaps);
    source.show(await pageAt(source, await startOf(source, 0)));
    await scheduler.settle();
    expect([
      for (var index = 0; index < 6; index++) source.laidOut(index),
    ], everyElement(isTrue));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      await Directory('${download.parent.path}/.bookfin-layout').exists(),
      isFalse,
    );
    final second = open(publication, pageMaps: pageMaps);
    final page = await pageAt(
      second,
      placeIn(await scheduler.until(second.section(3)), .5),
    );
    expect(second.numberOf(page), isNull);
  });

  group('the pager', () {
    final reported = <EpubAddress>[];
    EpubPager? opened;
    tearDown(() {
      opened?.dispose();
      opened = null;
    });

    /// A pager of [publication] at [initial], whose invariants are checked
    /// after every step.
    EpubPager openPager(
      Publication publication, {
      BookPageMaps? pageMaps,
      ReaderAddress? initial,
    }) {
      opened?.dispose();
      reported.clear();
      final source = PageSource(
        publication,
        schedule: scheduler.schedule,
        pageMaps: pageMaps,
      );
      final pager = EpubPager(
        EpubDocument(publication, pageMaps: pageMaps),
        initial: initial,
        onPlace: reported.add,
        onWarning: (_) {},
        source: source,
        hop: _inline,
      );
      scheduler.afterStep = pager.checkInvariants;
      return opened = pager;
    }

    /// Presents [settings] to [pager] and waits for its first page.
    Future<ShownPage> present(
      EpubPager pager, [
      PageSettings settings = readerPage,
    ]) async {
      final shown = Completer<ShownPage>();
      void listener() {
        if (pager.shown.value case final value? when !shown.isCompleted) {
          shown.complete(value);
        }
      }

      pager.shown.addListener(listener);
      pager.present(settings);
      final page = await scheduler.until(shown.future);
      pager.shown.removeListener(listener);
      pager.checkInvariants();
      return page;
    }

    test('the saved place opens at the same character with and without a '
        'kept map', () async {
      final publication = _sixSections();
      await layOutWhole(publication);
      // Places saved at another text size fall inside pages at this one.
      final saver = openPager(publication);
      await present(saver, smallPage);
      final saved = <EpubAddress>[];
      for (var turn = 0; turn < 40; turn++) {
        await scheduler.until(saver.move(true));
        if (turn.isEven) saved.add(reported.last);
      }

      for (final address in saved) {
        for (final pageMaps in [null, mapsOf(publication)]) {
          final pager = openPager(
            publication,
            pageMaps: pageMaps,
            initial: address,
          );
          final shown = await present(pager);

          expect(reported, [same(address)]);
          // The pager's invariants hold that the shown page holds the
          // place that the address resolves to.
          pager.checkInvariants();
          expect(shown.page.startPlace, isNotNull);
          if (pageMaps != null) {
            expect(pager.pageNumber.value?.count, isNotNull);
          }
        }
      }
    });

    test('a page number from a kept map that a neighbor page contradicts '
        'is counted again', () async {
      final publication = _sixSections();
      final (truth, _) = await layOutWhole(publication);
      int total(List<KeptSection> sections) =>
          sections.fold(0, (sum, section) => sum + section.starts.length);
      final pageMaps = mapsOf(publication);
      final wrong = [...truth];
      wrong[0] = _leaveOut(truth[0], 2);
      await pageMaps.write(readerPage, wrong);

      final pager = openPager(publication, pageMaps: pageMaps);
      await present(pager);
      expect(pager.pageNumber.value, (number: 1, count: total(wrong)));
      await scheduler.settle();

      expect(pager.pageNumber.value, (number: 1, count: total(truth)));
      await _eventually(() async => await pageMaps.read(readerPage) != null);
      expect(await pageMaps.read(readerPage), truth);
    });

    test('a second open of a book with its kept map shows whole-book page '
        'numbers at once', () async {
      final publication = _sixSections();
      final (truth, _) = await layOutWhole(publication);
      final count = truth.fold(
        0,
        (sum, section) => sum + section.starts.length,
      );
      final pager = openPager(publication, pageMaps: mapsOf(publication));

      await present(pager);

      expect(pager.bookPages.value.complete, isTrue);
      expect(pager.pageNumber.value, (number: 1, count: count));
      await scheduler.until(pager.move(true));
      expect(pager.pageNumber.value, (number: 2, count: count));
    });

    test(
      'a kept map that a page contradicts drops its pages from the index, '
      'and the shown page keeps its number until another page shows',
      () async {
        final publication = _sixSections();
        final (truth, _) = await layOutWhole(publication);
        int total(List<KeptSection> sections) =>
            sections.fold(0, (sum, section) => sum + section.starts.length);
        final before = total(truth.take(3).toList());
        final pageMaps = mapsOf(publication);
        // Section 3's map has one start too many, inside its second page, so
        // the map's count is one higher than the book's. The first page agrees
        // with the map, and its neighbor, the second page, contradicts it.
        final wrong = [...truth];
        final extra = truth[3].starts[2];
        wrong[3] = KeptSection(
          [
            ...truth[3].starts.take(2),
            PageStart(extra.item, extra.line - 1),
            ...truth[3].starts.skip(2),
          ],
          firsts: [...truth[3].firsts]..insert(2, truth[3].firsts[1]),
          visible: (
            starts: [...truth[3].visible.starts]
              ..insert(2, truth[3].visible.starts[1]),
            length: truth[3].visible.length,
          ),
          complete: true,
        );
        expect(extra.line, greaterThan(0));
        await pageMaps.write(readerPage, wrong);
        final pager = openPager(publication, pageMaps: pageMaps);
        final shown = await present(pager);
        await scheduler.until(pager.contents('text/s3.xhtml'));
        final numbers = [pager.pageNumber.value];
        pager.pageNumber.addListener(() => numbers.add(pager.pageNumber.value));
        expect(numbers.single, (number: before + 1, count: total(wrong)));
        expect(shown.page.section, 0);

        await _eventually(() async {
          await scheduler.until(Future<void>.delayed(Duration.zero));
          return await pageMaps.read(readerPage) == null;
        });
        expect(pager.bookPages.value.complete, isFalse);
        await scheduler.settle();

        expect(pager.bookPages.value.count, total(truth));
        expect(numbers.toSet(), {
          (number: before + 1, count: total(wrong)),
        }, reason: 'The shown page\'s number never went back.');
        await scheduler.until(pager.move(true));
        expect(pager.pageNumber.value, (
          number: before + 2,
          count: total(truth),
        ));
      },
    );
  });
}

Future<R> _inline<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);
