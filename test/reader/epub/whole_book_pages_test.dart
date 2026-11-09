// The pages of the whole book: the page label names the shown page among
// all of the book's pages once every section is laid out, and the scrub bar
// gives each page of the book an equal share, so that a drag lands on the
// page that the bar names. A test scheduler runs the page source's layout
// steps, and the pager's invariants are checked after every step.
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/book_pages.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, book, paragraphs;
import 'pager_test.dart' show largerText;

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;
  late Publication publication;
  EpubPager? opened;
  final reported = <EpubAddress>[];

  EpubPager pager() => opened!;

  EpubPager open(Publication book) {
    publication = book;
    reported.clear();
    source = PageSource(book, schedule: scheduler.schedule);
    final made = EpubPager(
      EpubDocument(book),
      onPlace: reported.add,
      onWarning: (_) {},
      source: source,
    );
    scheduler.afterStep = made.checkInvariants;
    return opened = made;
  }

  Future<T> until<T>(Future<T> future) async {
    final value = await scheduler.until(future);
    pager().checkInvariants();
    return value;
  }

  Future<ShownPage> present([PageSettings settings = readerPage]) async {
    final before = pager().shown.value?.page;
    pager().present(settings);
    await until(
      Future.doWhile(() async {
        await Future<void>.delayed(Duration.zero);
        final shown = pager().shown.value;
        return shown == null ||
            identical(shown.page, before) ||
            shown.page.settings != settings;
      }),
    );
    return pager().shown.value!;
  }

  ShownPage shown() => pager().shown.value!;

  /// The true pages of each section of the open book in [settings], as a
  /// whole layout of each section cuts them.
  Future<List<List<int>>> truePages([
    PageSettings settings = readerPage,
  ]) async {
    final pages = <List<int>>[];
    for (var index = 0; index < publication.spine.length; index++) {
      final prepared = (await until(source.section(index)));
      expect(prepared.settings, settings);
      final whole = layoutSection(prepared);
      pages.add([for (final page in whole.pages) page.startVisible]);
      whole.dispose();
    }
    return pages;
  }

  /// A book of three sections. The last is long, so that it is laid out
  /// well after the first.
  Publication threeSections() => book([
    paragraphs(10),
    paragraphs(14, label: 'Middle'),
    paragraphs(220, sentences: 10, label: 'Long'),
  ]);

  setUp(() => scheduler = TestScheduler());
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  group('the page label', () {
    test('before the book is laid out the label shows the chapter '
        'numbers', () async {
      open(threeSections());
      final first = await present();
      await until(source.mainRun(first.page, end: true));
      expect(source.laidOut(2), isFalse, reason: 'The long section waits.');

      final count = pager().pageNumber.value?.count;
      expect(count, isNotNull);
      expect(pager().pageNumber.value, (number: 1, count: count));
      expect(source.numberOf(first.page)?.count, count);
    });

    test('when every section is laid out the label shows whole-book '
        'numbers', () async {
      open(threeSections());
      await present();
      await scheduler.settle();
      final pages = await truePages();
      final total = pages.fold(0, (sum, section) => sum + section.length);

      expect(pager().pageNumber.value, (number: 1, count: total));
      while (shown().page.section == 0) {
        await until(pager().move(true));
      }
      await until(pager().move(true));
      expect(pager().pageNumber.value, (
        number: pages[0].length + 2,
        count: total,
      ));
    });

    test('the whole-book number never goes backward while the reader stays '
        'on a page', () async {
      open(threeSections());
      await present();
      await until(pager().move(true));
      final page = shown().page;
      final published = <PageNumber?>[pager().pageNumber.value];
      pager().pageNumber.addListener(
        () => published.add(pager().pageNumber.value),
      );

      await scheduler.settle();

      expect(shown().page, same(page));
      final pages = await truePages();
      final total = pages.fold(0, (sum, section) => sum + section.length);
      expect(published.last, (number: 2, count: total));
      final known = published.nonNulls.toList();
      for (var at = 1; at < known.length; at++) {
        expect(known[at].number, greaterThanOrEqualTo(known[at - 1].number));
        expect(
          known[at].count ?? 0,
          greaterThanOrEqualTo(known[at - 1].count ?? 0),
        );
      }
      expect(
        known.map((number) => number.count),
        contains(pages[0].length),
        reason: 'The chapter count shows before the book is laid out.',
      );
    });

    test('a settings change goes back to chapter numbers until the book is '
        'laid out again', () async {
      open(threeSections());
      await present();
      await until(pager().move(true));
      await scheduler.settle();
      final total = (await truePages()).fold(0, (sum, s) => sum + s.length);
      expect(pager().pageNumber.value?.count, total);

      await present(largerText);
      expect(
        pager().pageNumber.value?.count,
        anyOf(isNull, lessThan(total)),
        reason: 'The count is the chapter\'s until the book is laid out.',
      );
      await until(source.mainRun(shown().page, end: true));
      expect(source.laidOut(2), isFalse);
      final chapter = await truePages(largerText).then((pages) => pages[0]);
      expect(pager().pageNumber.value?.count, chapter.length);

      await scheduler.settle();
      final all = await truePages(largerText);
      expect(
        pager().pageNumber.value?.count,
        all.fold(0, (sum, s) => sum + s.length),
      );
    });

    test('a change back to settings whose book is laid out shows whole-book '
        'numbers at once', () async {
      open(threeSections());
      await present();
      await scheduler.settle();
      final total = (await truePages()).fold(0, (sum, s) => sum + s.length);
      await present(largerText);

      await present();

      expect(pager().pageNumber.value, (number: 1, count: total));
    });
  });

  group('the page index', () {
    test('names the first visible character of each true page of each '
        'section once its main run ends, and nothing before', () async {
      open(threeSections());
      final indexes = <BookPages>[];
      source.bookPages.addListener(() => indexes.add(source.bookPages.value));
      final first = await present();
      expect(source.bookPages.value.parts, [null, null, null]);

      await until(source.mainRun(first.page, end: true));
      final pages = await truePages();
      expect(source.bookPages.value.parts[0]?.starts, pages[0]);
      expect(source.bookPages.value.complete, isFalse);
      expect(source.bookPages.value.count, isNull);

      await scheduler.settle();
      final index = source.bookPages.value;
      expect(index.complete, isTrue);
      for (final (section, starts) in pages.indexed) {
        expect(index.parts[section]!.starts, starts);
        expect(
          index.parts[section]!.length,
          (await until(source.section(section))).dom.visibleLength,
        );
      }
      expect(index.count, pages.fold(0, (sum, s) => sum + s.length));
      expect(index.numberOf(2, 0), pages[0].length + pages[1].length + 1);
      expect(
        indexes.length,
        lessThanOrEqualTo(4),
        reason: 'It changes once a section, not once a page.',
      );
    });
    test('a section whose first drawn line follows text that the book '
        'hides still starts its pages at 0', () async {
      // As the title page of Standard Ebooks' Frankenstein hides its title
      // and author before its image.
      open(
        book([
          '<h1 style="display: none">Frankenstein</h1>'
              '<p style="display: none">By Mary Shelley.</p>'
              '<p>The cover caption.</p>',
          paragraphs(12),
        ]),
      );
      await present();
      await scheduler.settle();
      final index = source.bookPages.value;
      expect(index.complete, isTrue);
      expect(index.parts[0]!.starts.first, 0);
      expect(pager().pageNumber.value?.count, index.count);
    });
  });

  group('the scrub bar of a laid-out book', () {
    /// The book map of the open book, with its page index.
    Future<BookMap> mapOf() async => (await BookMap.of(
      EpubDocument(publication),
      const [],
    ))!.paged(source.bookPages.value);

    test('a drag to a point of the bar lands on the page that the bar shows '
        'there', () async {
      open(threeSections());
      await present();
      await scheduler.settle();
      final map = await mapOf();
      final total = map.pages!;

      for (var page = 1; page <= total; page++) {
        // Each page takes an equal share of the bar.
        for (final within in [.02, .5, .98]) {
          final target = map.targetAt((page - 1 + within) / total);
          expect(target.page, page);
          await until(pager().seek(target.part, target.progress));
          expect(pager().pageNumber.value, (number: page, count: total));
        }
      }
    });

    test('the open place sits on its own page of the bar', () async {
      open(threeSections());
      await present();
      await scheduler.settle();
      final map = await mapOf();
      final total = map.pages!;

      // The reader turns through the book from its first page.
      var turns = 0;
      while (true) {
        final number = pager().pageNumber.value!;
        final at = map.fractionOf(reported.last)!;
        expect(map.targetAt(at).page, number.number);
        if (number.number == total || turns++ > total) break;
        await until(pager().move(true));
      }
      expect(turns, total - 1);
    });
  });
}
