import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart'
    show HeldPrepares, TestScheduler, book, paragraphs, smallPage;
import 'section_part_test.dart' show monologue;

// These observers count reads at existing input boundaries. They leave
// admission, preparation, layout, page reporting and title selection real.
class _ReadEntry extends ContentsEntry {
  _ReadEntry(ContentsEntry entry, this.read)
    : super(entry.title, entry.href, depth: entry.depth);

  final void Function() read;

  @override
  String get href {
    read();
    return super.href;
  }
}

class _Publication extends Fake implements Publication {
  _Publication(this.book, this.contents);
  final Publication book;
  @override
  final List<ContentsEntry> contents;
  @override
  String get identity => book.identity;
  @override
  String get originalDigest => book.originalDigest;
  @override
  String get packagePath => book.packagePath;
  @override
  List<String> get spine => book.spine;
  @override
  List<String> get spineSteps => book.spineSteps;
  @override
  Map<String, Uint8List> get textFiles => book.textFiles;
  @override
  Map<String, String> get bookStyles => book.bookStyles;
  @override
  Map<String, String> stylesForSection(String path) =>
      book.stylesForSection(path);
  @override
  Map<String, (int, int)> get imageSizes => book.imageSizes;
  @override
  String? get language => book.language;
  @override
  double get mainTextSize => book.mainTextSize;
  @override
  Map<String, List<String>> get sectionFaces => book.sectionFaces;
  @override
  Future<Uint8List?> bytesOf(String path) => book.bytesOf(path);
}

class _ReadList<T> extends ListBase<T> {
  _ReadList(this.values);
  final List<T> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  T operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('read only');
}

class _Dom extends Fake implements DomSection {
  _Dom(this.dom) : texts = _ReadList(dom.texts);
  final DomSection dom;
  @override
  final _ReadList<DomText> texts;
  int headings = 0;
  int targets = 0;
  @override
  DomElement get root {
    headings++;
    return dom.root;
  }

  @override
  DomElement get body => dom.body;
  @override
  DomNode nodeAt(int order) => dom.nodeAt(order);
  @override
  DomText? textAt(EpubPlace place) => dom.textAt(place);
  @override
  DomText? textFrom(DomNode node) => dom.textFrom(node);
  @override
  DomElement? elementById(String id) {
    targets++;
    return dom.elementById(id);
  }
}

void main() {
  setUpAll(loadReaderFont);

  test(
    'repeated page reports use section facts prepared in the worker',
    () async {
      var inWorker = false;
      var workerReads = 0;
      var reportReads = 0;
      void read() => inWorker ? workerReads++ : reportReads++;
      Future<R> work<R>(FutureOr<R> Function() computation) async {
        inWorker = true;
        try {
          return await computation();
        } finally {
          inWorker = false;
        }
      }

      final publication = _Publication(book([paragraphs(80)]), [
        for (var index = 0; index < 2000; index++)
          _ReadEntry(
            ContentsEntry('Elsewhere $index', 'elsewhere.xhtml'),
            read,
          ),
        _ReadEntry(const ContentsEntry('Harbour', 'text/s0.xhtml'), read),
      ]);
      final scheduler = TestScheduler()..animating = true;
      final source = PageSource(
        publication,
        schedule: scheduler.schedule,
        work: work,
      );
      final reports = <EpubAddress>[];
      final pager = EpubPager(
        EpubDocument(publication),
        source: source,
        onPlace: reports.add,
        onWarning: (warning) => fail(warning),
      );
      addTearDown(pager.dispose);
      final opened = Completer<void>();
      pager.shown.addListener(() {
        if (pager.shown.value != null && !opened.isCompleted) opened.complete();
      });
      pager.present(readerPage);
      await scheduler.until(opened.future);
      for (var turn = 0; turn < 12; turn++) {
        await scheduler.until(pager.move(true));
      }
      expect(reports, hasLength(13));
      expect(
        reports.map((report) => report.location.chapter),
        everyElement('Harbour'),
      );
      expect(
        reportReads,
        0,
        reason: 'Page reports must resolve no contents URLs.',
      );
      expect(
        workerReads,
        2001,
        reason: 'One section resolves each entry once.',
      );
      stdout.writeln(
        '13 page reports: $reportReads report href reads, '
        '$workerReads worker href reads.',
      );
      pager.checkInvariants();
    },
  );

  test('a saved quote near the section end does not scan preceding text nodes', () {
    final dom = _Dom(
      DomSection.parse(
        '<html><body>${[for (var i = 0; i < 4000; i++) '<p>Earlier $i</p>'].join()}'
        '<p>Last words.</p><p>Afterwards.</p></body></html>',
      ),
    );
    final place = EpubPlace(0, dom.dom.texts[4000].order, 5);
    expect(quoteAt(dom, place), 'words.Afterwards.');
    expect(
      dom.texts.reads,
      lessThan(40),
      reason: 'Only a logarithmic lookup and the quote suffix are needed.',
    );
    stdout.writeln(
      'Quote after 4000 text nodes: ${dom.texts.reads} text-list reads.',
    );
  });

  test(
    'repeated chapter labels reuse resolved targets and the fallback heading',
    () {
      final dom = _Dom(
        DomSection.parse(
          '<html><head><title>Fallback</title></head><body><p>Before</p>'
          '<h2 id="a">First</h2><p id="b">Second</p></body></html>',
        ),
      );
      var hrefReads = 0;
      final contents = [
        for (var index = 0; index < 2000; index++)
          _ReadEntry(
            ContentsEntry('Elsewhere $index', 'elsewhere.xhtml'),
            () => hrefReads++,
          ),
        _ReadEntry(
          const ContentsEntry('First chapter', 'one.xhtml#a'),
          () => hrefReads++,
        ),
        _ReadEntry(
          const ContentsEntry('Second chapter', 'one.xhtml#b'),
          () => hrefReads++,
        ),
      ];
      final title = ChapterTitles(dom, contents, 'book.opf', 'one.xhtml').at;
      final places = [
        for (final text in dom.dom.texts) EpubPlace(0, text.order, 0),
      ];
      for (var report = 0; report < 20; report++) {
        expect(places.map(title), [
          'Fallback',
          'First chapter',
          'Second chapter',
        ]);
      }
      expect(hrefReads, 2002);
      expect(dom.targets, 2);
      expect(dom.headings, 1);
      stdout.writeln(
        '60 title queries: $hrefReads href reads, ${dom.targets} target '
        'lookups, ${dom.headings} heading traversals.',
      );
    },
  );

  test(
    'chapter labels preserve URI resolution, CFI order and equal-position ties',
    () {
      final dom = DomSection.parse(
        '<html><head><title>Heading</title></head><body><p>Before</p>'
        '<div>Intro <span id="a b">One</span></div><p id="end">End</p></body></html>',
      );
      const contents = [
        ContentsEntry('End chapter', '../text/one%20book.xhtml#end'),
        ContentsEntry('First name', '../text/one%20book.xhtml#a%20b'),
        ContentsEntry('Missing', '../text/one%20book.xhtml#absent'),
        ContentsEntry('Malformed URI', 'http://['),
        ContentsEntry('Malformed fragment', '../text/one%20book.xhtml#%FF'),
        ContentsEntry('Other section', '../text/other.xhtml'),
        ContentsEntry('Last name', '../text/one%20book.xhtml#a%20b'),
      ];
      final title = ChapterTitles(
        dom,
        contents,
        'OPS/package/book.opf',
        'OPS/text/one book.xhtml',
      ).at;
      expect(
        [for (final text in dom.texts) title(EpubPlace(0, text.order, 0))],
        ['Heading', 'Last name', 'Last name', 'End chapter'],
      );
      final target = dom.elementById('a b')!;
      expect(title(EpubPlace(0, target.order, 0)), 'Last name');
      expect(title(EpubPlace(0, dom.texts[1].order, 3)), 'Last name');
    },
  );

  test(
    'a part and its note excerpt keep titles from outside the prepared flow',
    () {
      var reads = 0;
      final source = SectionSource(
        index: 3,
        path: 'OPS/one.xhtml',
        packagePath: 'OPS/book.opf',
        contents: [
          _ReadEntry(
            const ContentsEntry('Earlier chapter', 'one.xhtml#begin'),
            () => reads++,
          ),
        ],
        xhtml:
            '<html><head><title>Fallback</title></head><body>'
            '<h1 id="begin">Opening</h1>${paragraphs(150)}'
            '<aside id="note"><p>Note words.</p></aside>${paragraphs(150)}'
            '</body></html>',
      );
      final result = preparePart(
        source,
        readerPage,
        (dom) => destination(dom, 3, 'note'),
      );
      final part = result.section!;
      expect(part.whole, isFalse);
      expect(part.firstPrepared, greaterThan(0));
      expect(part.reachesEnd, isFalse);
      expect(part.chapters.at(result.place!), 'Earlier chapter');
      final excerpt = part.excerpt(part.dom.elementById('note')!, smallPage)!;
      expect(excerpt.chapters.at(result.place!), 'Earlier chapter');
      expect(excerpt.chapters, same(part.chapters));
      expect(reads, 1);
      final whole = prepareSections([source], readerPage).single;
      expect(whole.chapters.at(result.place!), 'Earlier chapter');
      expect(reads, 2, reason: 'A new DOM prepares its own facts.');
    },
  );

  test('a part that must prepare the whole section resolves its contents only once', () {
    var reads = 0;
    final source = SectionSource(
      index: 0,
      path: 'one.xhtml',
      contents: [
        _ReadEntry(
          const ContentsEntry('Whole chapter', 'one.xhtml#long'),
          () => reads++,
        ),
      ],
      xhtml:
          '<html><body>${paragraphs(20)}<div id="long">'
          '${monologue(600)}</div>${paragraphs(20)}</body></html>',
    );
    final result = preparePart(
      source,
      readerPage,
      (dom) => placeAt(dom, 0, .5),
    );
    expect(result.section!.whole, isTrue);
    expect(result.section!.chapters.at(result.place!), 'Whole chapter');
    expect(reads, 1);
  });

  test('worker-prepared parts and their whole replacement report the same chapter', () async {
    final publication = _Publication(
      book([paragraphs(500, sentences: 12)]),
      const [ContentsEntry('Large chapter', 'text/s0.xhtml')],
    );
    final held = HeldPrepares();
    final scheduler = TestScheduler()..animating = true;
    final source = PageSource(
      publication,
      schedule: scheduler.schedule,
      work: held.run,
    )..settings = readerPage;
    addTearDown(source.dispose);
    // Release even if an assertion fails, so no worker promise is left pending.
    addTearDown(() {
      if (!held.release.isCompleted) held.release.complete();
    });
    final place = (await scheduler.until(
      source.findPlace(0, (dom) => placeAt(dom, 0, .5)),
    ))!;
    final page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    final part = source.sectionOf(page);
    expect(part.whole, isFalse);
    expect(part.chapters.at(place), 'Large chapter');
    held.release.complete();
    final whole = await scheduler.until(source.section(0));
    expect(whole.whole, isTrue);
    expect(whole.chapters.at(place), 'Large chapter');
    expect(part.chapters.at(place), 'Large chapter');
    source.checkInvariants();
  });

  test(
    'section titles survive eviction, settings changes and reopening',
    () async {
      final publication = _Publication(
        book([for (var i = 0; i < 8; i++) paragraphs(2)]),
        [
          for (var i = 0; i < 8; i++)
            ContentsEntry('Chapter label $i', 'text/s$i.xhtml'),
        ],
      );
      final scheduler = TestScheduler()..animating = true;
      PageSource open() =>
          PageSource(publication, schedule: scheduler.schedule)
            ..settings = readerPage;
      final source = open();
      addTearDown(source.dispose);
      final first = await scheduler.until(source.section(0));
      final place = EpubPlace(0, first.dom.texts.first.order, 0);
      expect(first.chapters.at(place), 'Chapter label 0');
      for (var i = 1; i < 8; i++) {
        final section = await scheduler.until(source.section(i));
        expect(
          section.chapters.at(EpubPlace(i, section.dom.texts.first.order, 0)),
          'Chapter label $i',
        );
      }
      final again = await scheduler.until(source.section(0));
      expect(
        again,
        isNot(same(first)),
        reason: 'The bounded section cache evicted section zero.',
      );
      expect(again.chapters.at(place), 'Chapter label 0');
      source.settings = smallPage;
      final resized = await scheduler.until(source.section(0));
      expect(resized, isNot(same(again)));
      expect(resized.chapters.at(place), 'Chapter label 0');
      source.settings = readerPage;
      expect(await scheduler.until(source.section(0)), same(again));
      source.checkInvariants();
      source.dispose();
      final reopened = open();
      addTearDown(reopened.dispose);
      final restored = await scheduler.until(reopened.section(0));
      expect(restored.chapters.at(place), 'Chapter label 0');
      reopened.checkInvariants();
    },
  );
}
