// A book opens with its kept page map (t5-4l4d, design A of
// docs/research/epub-layout-cache.md). The page source trusts the map at
// open, so the true page and its number show at once and the whole-book
// work skips every section that the map holds. Each page that a run cuts
// from a kept start checks the map, and the first page that contradicts it
// forgets the map. The map is written once the whole book is laid out.
import 'dart:async';
import 'dart:io';

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
        KeptSection([
          for (final page in await pagesOf(source, index)) page.start,
        ], complete: true),
    ];

    await _eventually(() async => await pageMaps.read(readerPage) != null);
    expect(await pageMaps.read(readerPage), sections);
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
    wrong[2] = KeptSection([...truth[2].starts]..removeAt(2), complete: true);
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
            ? KeptSection([...section.starts]..removeAt(1), complete: true)
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
    wrong[2] = KeptSection([...truth[2].starts]..removeAt(2), complete: true);
    await pageMaps.write(readerPage, wrong);

    final source = open(publication, pageMaps: pageMaps);
    final page = await pageAt(source, place);

    expect(content(page), anchored);
    expect(page.startPlace, place);
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
      wrong[0] = KeptSection([...truth[0].starts]..removeAt(2), complete: true);
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
        wrong[3] = KeptSection([
          ...truth[3].starts.take(2),
          PageStart(extra.item, extra.line - 1),
          ...truth[3].starts.skip(2),
        ], complete: true);
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
