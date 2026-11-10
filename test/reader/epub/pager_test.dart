// The pager owns the shown place and the shown page of an open EPUB. It
// carries out the reader session's navigation, reports each new place, draws
// scrub deck pages and runs searches. A test scheduler runs the page
// source's layout steps, and the pager's invariants are checked after every
// step.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/foundation/hop.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/search.dart';
import 'package:bookfin/reader/epub/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/showcase_media.dart' as media;
import 'helpers.dart';
import 'page_source_test.dart'
    show TestScheduler, book, content, paragraphs, smallPage;

/// The reader's page with a larger text size.
const largerText = PageSettings(
  width: 412,
  height: 671,
  fontSize: 26,
  night: false,
);

/// The showcase books of tool/showcase_media.dart, admitted as Bookfin
/// admits them.
final showcase = {
  'frost': (media.firstFrost, 'First Frost'),
  'salt': (media.saltAndLantern, 'Salt and Lantern'),
  'winter': (media.winterLedger, 'The Winter Ledger'),
};

Publication showcaseBook(String name) {
  final (chapters, title) = showcase[name]!;
  return Publication.admit(
    media.epub(name, title, 'Bookfin Showcase', chapters),
  );
}

/// A book of three sections. The first links to an element in the second.
Publication linkedBook() => book([
  '<h1>Start</h1><p>Before the link. <a href="s1.xhtml#target">Follow the '
      'lantern</a> after the link.</p>${paragraphs(6)}',
  '${paragraphs(8, label: 'Middle')}<p id="target">The target paragraph '
      'waits here.</p>${paragraphs(4, label: 'Late')}',
  paragraphs(3, label: 'End'),
]);

/// A book of two sections. The first has a note reference to an endnote
/// in the second, and a plain link to a paragraph before the endnotes.
Publication noteBook() => book([
  '<p>Before the note.<a id="ref-1" epub:type="noteref" '
      'href="s1.xhtml#note-1">1</a> After the note. <a href="s1.xhtml#plain">'
      'A plain link</a> ends the paragraph.</p>${paragraphs(6)}',
  '<p id="plain">The plain target.</p>${paragraphs(8, label: 'Late')}'
      '<ol epub:type="endnotes"><li id="note-1" epub:type="endnote"><p>The '
      'lantern note explains the harbour.</p><p>Its second paragraph ends '
      'it. <a href="s0.xhtml#ref-1" epub:type="backlink">Back</a></p></li>'
      '</ol>',
]);

/// What a screen reader reads of [page], block by block.
List<String> readOf(LaidPage page) => [
  for (final block in pageBlocks(page))
    block.spans.map((span) => span.label).join(' '),
];

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;
  EpubPager? opened;
  final reported = <EpubAddress>[];
  final warnings = <String>[];
  final turns = <int?>[];

  EpubPager pager() => opened!;

  EpubPager open(
    Publication publication, {
    ReaderAddress? initial,
    IsolateHop? hop,
  }) {
    opened?.dispose();
    reported.clear();
    warnings.clear();
    turns.clear();
    source = PageSource(publication, schedule: scheduler.schedule);
    final made = EpubPager(
      EpubDocument(publication),
      initial: initial,
      onPlace: reported.add,
      onWarning: warnings.add,
      onShow: turns.add,
      source: source,
      hop: hop ?? _inline,
    );
    scheduler.afterStep = made.checkInvariants;
    return opened = made;
  }

  /// Runs steps until [future] completes, then checks the invariants.
  Future<T> until<T>(Future<T> future) async {
    final value = await scheduler.until(future);
    pager().checkInvariants();
    return value;
  }

  /// The next shown page that is not the page shown now.
  Future<ShownPage> nextShown() {
    final before = pager().shown.value?.page;
    final shown = Completer<ShownPage>();
    void listener() {
      final value = pager().shown.value;
      if (value != null &&
          !identical(value.page, before) &&
          !shown.isCompleted) {
        shown.complete(value);
      }
    }

    pager().shown.addListener(listener);
    return shown.future.whenComplete(
      () => pager().shown.removeListener(listener),
    );
  }

  /// Presents [settings], and waits for the page that it shows.
  Future<ShownPage> present([PageSettings settings = readerPage]) {
    final shown = nextShown();
    pager().present(settings);
    return until(shown);
  }

  ShownPage shown() => pager().shown.value!;

  Future<PreparedSection> section(int index) =>
      scheduler.until(source.section(index));

  setUp(() => scheduler = TestScheduler());
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  test('opening without a saved place shows the first page of the book and '
      'reports it', () async {
    open(linkedBook());

    final first = await present();

    expect(first.page.section, 0);
    expect(first.page.start, const PageStart(0, 0));
    expect(reported, hasLength(1));
    final dom = (await section(0)).dom;
    expect(
      reported.single.location.toJson(),
      pageLocation(
        '/6/2',
        'OPS/text/s0.xhtml',
        dom,
        first.page.startPlace!,
        first.page.endPlace!,
        'Start',
      ).toJson(),
    );
    expect(warnings, isEmpty);
  });

  test(
    'a jump supersedes a page turn asked before it that has not shown: '
    'the turned page never shows, and the jump reports the only place',
    () async {
      open(linkedBook());
      await present();
      reported.clear();
      final shownSections = <int>[];
      void listener() => shownSections.add(shown().page.section);
      pager().shown.addListener(listener);
      addTearDown(() => pager().shown.removeListener(listener));

      final turn = pager().move(true);
      final jump = pager().seek(1, .5);
      await until(Future.wait([turn, jump]));

      expect(shownSections, everyElement(1));
      expect(reported.single.location.resource, endsWith('s1.xhtml'));
    },
  );

  test('each new page reports the visible characters of the page that the '
      'person turned forward from, and any other move reports none', () async {
    open(linkedBook());
    final first = (await present()).page;
    expect(turns, [null], reason: 'Opening the book turns no page.');

    await until(pager().move(true));
    expect(first.endVisible - first.startVisible, greaterThan(100));
    expect(turns.last, first.endVisible - first.startVisible);

    await until(pager().move(false));
    expect(turns.last, isNull, reason: 'A turn back reads no page.');
    await until(pager().seek(1, .5));
    expect(turns.last, isNull, reason: 'A jump reads no page.');
    await present(largerText);
    expect(turns.last, isNull, reason: 'New page settings read no page.');
    expect(turns, hasLength(5));
  });

  test('present notifies later, never during the call, and the same '
      'settings again change nothing', () async {
    open(linkedBook());
    var notified = 0;
    pager().shown.addListener(() => notified++);

    final first = nextShown();
    pager().present(readerPage);
    expect(notified, 0);
    final page = (await until(first)).page;
    await scheduler.settle();
    final settled = notified;

    pager().present(readerPage);
    expect(notified, settled);
    await scheduler.settle();
    expect(notified, settled);
    expect(shown().page, same(page));
    expect(reported, hasLength(1));
  });

  test('present refuses page settings without a page area or a text size', () {
    open(linkedBook());
    for (final settings in const [
      PageSettings(width: 0, height: 671, fontSize: 20, night: false),
      PageSettings(width: 412, height: 0, fontSize: 20, night: false),
      PageSettings(width: 412, height: 671, fontSize: 0, night: false),
      PageSettings(
        width: double.infinity,
        height: 671,
        fontSize: 20,
        night: false,
      ),
    ]) {
      expect(() => pager().present(settings), throwsArgumentError);
    }
    expect(pager().shown.value, isNull);
  });

  test('opening at a saved place shows a page whose first line holds it and '
      'reports the identical address object', () async {
    final publication = showcaseBook('frost');
    open(publication);
    await present();
    for (var turn = 0; turn < 5; turn++) {
      await until(pager().move(true));
    }
    final left = shown().page;
    final leftContent = content(left);
    final saved = EpubAddress(
      ReadingLocation.fromJson(reported.last.location.toJson()),
    );

    open(publication, initial: saved);
    final opened = await present();

    expect(reported, hasLength(1));
    expect(reported.single, same(saved));
    final prepared = await section(opened.page.section);
    final place = placeOf(
      prepared.dom,
      opened.page.section,
      saved.location.cfi,
    )!;
    expect(opened.page.start, lineStart(prepared, place));
    expect(content(opened.page), leftContent);
    expect(warnings, isEmpty);
  });

  test('a place that epub.js saved before a page\'s first visible character '
      'opens on that page and is reported as the identical address '
      'object, so opening never rewrites it', () async {
    // epub.js saved the start of a Gutenberg paragraph's text node, the
    // line break before its first word. The pager saves the page's first
    // visible character instead.
    final publication = book([
      '${paragraphs(8)}<p>\nWe felt a speech coming.</p>${paragraphs(4)}',
    ]);
    open(publication);
    await present();
    final dom = (await section(0)).dom;
    final text = dom.texts.firstWhere((text) => text.text.startsWith('\nWe'));
    final old = EpubPlace(0, text.order, 0);
    final saved = EpubAddress(
      ReadingLocation(
        cfiOf('/6/2', dom, old),
        'OPS/text/s0.xhtml',
        quoteAt(dom, old),
        progress: progressAt(dom, old),
      ),
    );

    open(publication, initial: saved);
    final opened = await present();

    expect(reported, hasLength(1));
    expect(reported.single, same(saved));
    final prepared = await section(0);
    expect(opened.page.start, lineStart(prepared, old));
    expect(
      pageLocation(
        '/6/2',
        'OPS/text/s0.xhtml',
        dom,
        opened.page.startPlace!,
        opened.page.endPlace!,
        'Start',
      ).cfi,
      cfiOf('/6/2', dom, EpubPlace(0, text.order, 1)),
      reason: 'the page itself saves its first visible character',
    );
    expect(warnings, isEmpty);
  });

  test('a saved place with a wrong quote opens at the start with the warning '
      'and reports nothing until a move', () async {
    final publication = linkedBook();
    final saved = EpubAddress(
      const ReadingLocation(
        'epubcfi(/6/4!/4/2/1:0)',
        'OPS/text/s1.xhtml',
        'Text that this book does not have',
        progress: .1,
      ),
    );
    open(publication, initial: saved);

    final first = await present();

    expect(first.page.section, 0);
    expect(first.page.start, const PageStart(0, 0));
    expect(warnings, [
      'The saved place does not match this text. Reading starts at the '
          'beginning.',
    ]);
    expect(reported, isEmpty);

    await until(pager().move(true));
    expect(reported, hasLength(1));
    expect(reported.single.location.resource, 'OPS/text/s0.xhtml');
  });

  test('turns go forward and back within a section and across sections, and '
      'do nothing at both ends of the book', () async {
    open(book([paragraphs(12), paragraphs(1, label: 'Brief'), paragraphs(9)]));
    await present();

    await until(pager().move(false));
    expect(shown().page.section, 0);
    expect(shown().page.start, const PageStart(0, 0));
    expect(reported, hasLength(1));

    final forward = [content(shown().page)];
    final sections = [shown().page.section];
    while (true) {
      final before = shown().page;
      await until(pager().move(true));
      if (identical(shown().page, before)) break;
      forward.add(content(shown().page));
      sections.add(shown().page.section);
      expect(reported, hasLength(forward.length));
      expect(
        reported.last.location.resource,
        'OPS/text/s${shown().page.section}.xhtml',
      );
    }
    expect(sections.toSet(), {0, 1, 2});
    expect(sections, orderedEquals([...sections]..sort()));
    expect(sections.where((index) => index == 0).length, greaterThan(2));
    expect(shown().page.last, isTrue);
    expect(reported, hasLength(forward.length));

    final backward = [content(shown().page)];
    while (true) {
      final before = shown().page;
      await until(pager().move(false));
      if (identical(shown().page, before)) break;
      backward.add(content(shown().page));
    }
    expect(backward.reversed.toList(), forward);
    expect(reported, hasLength(forward.length * 2 - 1));
  });

  test('a new text size keeps the shown place and reports nothing, and the '
      'text shown over later turns covers each section in order with no text '
      'skipped', () async {
    for (final name in showcase.keys) {
      for (final forward in [true, false]) {
        final publication = showcaseBook(name);
        open(publication);
        await present();
        for (var turn = 0; turn < 3; turn++) {
          await until(pager().move(true));
        }
        final place = shown().page.startPlace!;
        reported.clear();

        final larger = await present(largerText);

        expect(larger.page.settings, largerText, reason: name);
        final prepared = await section(larger.page.section);
        expect(larger.page.start, lineStart(prepared, place), reason: name);
        await scheduler.settle();
        expect(reported, isEmpty, reason: name);

        final totals = [
          for (var index = 0; index < publication.spine.length; index++)
            (await section(index)).dom.visibleLength,
        ];
        var page = larger.page;
        while (true) {
          await until(pager().move(forward));
          final next = shown().page;
          if (identical(next, page)) break;
          final reason = '$name ${forward ? 'forward' : 'back'} ${next.start}';
          final (earlier, later) = forward ? (page, next) : (next, page);
          if (next.section == page.section) {
            expect(
              later.startVisible,
              lessThanOrEqualTo(earlier.endVisible),
              reason: reason,
            );
            expect(
              later.endVisible,
              greaterThan(earlier.endVisible),
              reason: reason,
            );
          } else {
            expect(later.section, earlier.section + 1, reason: reason);
            expect(earlier.endVisible, totals[earlier.section], reason: reason);
            expect(later.startVisible, 0, reason: reason);
          }
          page = next;
        }
        if (forward) {
          expect(page.section, publication.spine.length - 1, reason: name);
          expect(page.endVisible, totals.last, reason: name);
        } else {
          expect(page.section, 0, reason: name);
          expect(page.startVisible, 0, reason: name);
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('seek lands on the page that holds placeAt, and reports it', () async {
    final publication = linkedBook();
    open(publication);
    await present();

    await until(pager().seek(1, .5));

    final prepared = await section(1);
    final place = placeAt(prepared.dom, 1, .5);
    final page = shown().page;
    expect(page.section, 1);
    expect(_holdsLine(page, lineStart(prepared, place)), isTrue);
    expect(reported, hasLength(2));
    expect(reported.last.location.resource, 'OPS/text/s1.xhtml');
    expect(reported.last.location.progress, lessThanOrEqualTo(.5));

    await expectLater(until(pager().seek(3, .5)), throwsRangeError);
    await expectLater(until(pager().seek(1, 1.5)), throwsArgumentError);
    expect(shown().page, same(page));
    expect(reported, hasLength(2));
  });

  test('contents entries land on their destination, and unknown targets '
      'throw', () async {
    open(linkedBook());
    await present();
    final prepared = await section(1);
    final target = destination(prepared.dom, 1, 'target')!;

    await until(pager().contents('text/s1.xhtml#target'));
    expect(shown().page.section, 1);
    expect(_holdsLine(shown().page, lineStart(prepared, target)), isTrue);
    expect(reported, hasLength(2));

    await until(pager().contents('text/s2.xhtml'));
    expect(shown().page.section, 2);
    expect(shown().page.start, const PageStart(0, 0));
    expect(reported, hasLength(3));

    final page = shown().page;
    for (final href in [
      'text/s1.xhtml#missing',
      'text/nowhere.xhtml',
      'https://example.com/text/s1.xhtml',
      'text/s1.xhtml?query=1',
    ]) {
      await expectLater(
        until(pager().contents(href)),
        throwsA(anything),
        reason: href,
      );
    }
    expect(shown().page, same(page));
    expect(reported, hasLength(3));
  });

  test('linkAt gives the destination of the link under a point, relative to '
      'the package document, and contents follows it', () async {
    open(linkedBook());
    final first = await present();
    final dom = (await section(0)).dom;
    final link = dom.texts.firstWhere(
      (text) => text.text == 'Follow the lantern',
    );
    final plain = dom.texts.firstWhere(
      (text) => text.text.startsWith('Before the link'),
    );

    final onLink = _pointOf(first.page, EpubPlace(0, link.order, 4));
    final onText = _pointOf(first.page, EpubPlace(0, plain.order, 2));
    expect(pager().linkAt(onLink), (
      href: 'text/s1.xhtml#target',
      noteref: false,
    ));
    expect(pager().linkAt(onText), isNull);
    expect(pager().linkAt(const ui.Offset(406, 668)), isNull);

    await until(pager().contents(pager().linkAt(onLink)!.href));
    final prepared = await section(1);
    expect(
      _holdsLine(
        shown().page,
        lineStart(prepared, destination(prepared.dom, 1, 'target')!),
      ),
      isTrue,
    );
  });

  test('linkAt finds a link in a table cell', () async {
    open(
      book([
        '<p>Before the table.</p><table><tr><td>Plain cell</td>'
            '<td><a href="s1.xhtml#target">Linked cell</a></td></tr></table>',
        '<p id="target">The target.</p>',
      ]),
    );
    final first = await present();
    final dom = (await section(0)).dom;
    final link = dom.texts.firstWhere((text) => text.text == 'Linked cell');
    final plain = dom.texts.firstWhere((text) => text.text == 'Plain cell');

    expect(pager().linkAt(_pointOf(first.page, EpubPlace(0, link.order, 3))), (
      href: 'text/s1.xhtml#target',
      noteref: false,
    ));
    expect(
      pager().linkAt(_pointOf(first.page, EpubPlace(0, plain.order, 3))),
      isNull,
    );
  });

  test('linkAt says whether the link under a point is a note '
      'reference', () async {
    open(noteBook());
    final first = await present();
    final dom = (await section(0)).dom;
    final reference = dom.texts.firstWhere((text) => text.text == '1');
    final plain = dom.texts.firstWhere((text) => text.text == 'A plain link');

    expect(
      pager().linkAt(_pointOf(first.page, EpubPlace(0, reference.order, 0))),
      (href: 'text/s1.xhtml#note-1', noteref: true),
    );
    expect(pager().linkAt(_pointOf(first.page, EpubPlace(0, plain.order, 3))), (
      href: 'text/s1.xhtml#plain',
      noteref: false,
    ));
  });

  test('note lays out the note of a note reference with the book\'s own '
      'text, at the width asked for, and moves no place', () async {
    open(noteBook());
    final first = await present();
    final end = pager().shownEnd;
    reported.clear();

    final note = (await until(
      pager().note((href: 'text/s1.xhtml#note-1', noteref: true), width: 300),
    ))!;
    addTearDown(note.dispose);

    expect(readOf(note.page), [
      'The lantern note explains the harbour.',
      'Its second paragraph ends it.',
    ]);
    expect(note.page.settings.width, 300);
    expect(note.page.height, greaterThan(0));
    expect(shown().page, same(first.page));
    expect(pager().shownEnd, end);
    expect(reported, isEmpty);
  });

  test('note finds the note of a link to an endnote even when the link is '
      'not marked as a note reference', () async {
    open(noteBook());
    await present();

    final note = (await until(
      pager().note((href: 'text/s1.xhtml#note-1', noteref: false), width: 412),
    ))!;
    addTearDown(note.dispose);

    expect(readOf(note.page).first, 'The lantern note explains the harbour.');
  });

  test('a superscript note reference of a showcase book with endnotes, '
      'marked as Standard Ebooks marks one, shows its endnote', () async {
    open(
      Publication.admit(
        media.epub(
          'frost',
          'First Frost',
          'Bookfin Showcase',
          media.firstFrost,
          endnotes: ['The first note.', 'The second note.'],
        ),
      ),
    );
    final first = await present();
    // The superscript draws as a small paragraph of its own in its line.
    final links = {
      for (var y = 0.0; y < first.page.height; y += 2)
        for (var x = 0.0; x < first.page.settings.width; x += 2)
          ?pager().linkAt(ui.Offset(x, y)),
    };
    expect(links, {
      (href: 'endnotes.xhtml#note-1', noteref: true),
      (href: 'endnotes.xhtml#note-2', noteref: true),
    });

    final link = links.last;
    final note = (await until(pager().note(link, width: 412)))!;
    addTearDown(note.dispose);

    expect(link, (href: 'endnotes.xhtml#note-2', noteref: true));
    expect(readOf(note.page), ['The second note.']);
  });

  /// The note of the reference in [book]'s first section, laid out 412
  /// pixels wide, read block by block.
  Future<List<String>> noteRead(Publication book) async {
    open(book);
    await present();
    final note = (await until(
      pager().note((href: 'text/s1.xhtml#n', noteref: true), width: 412),
    ))!;
    addTearDown(note.dispose);
    return readOf(note.page);
  }

  /// A book whose first section has a note reference, ref-1, to the note
  /// n in the second section, whose paragraphs are [note].
  Publication backBook(String note) => book([
    '<p>Text<a id="ref-1" epub:type="noteref" href="s1.xhtml#n">1</a>.</p>',
    '<p id="other">Other text.</p><aside id="n" epub:type="footnote">'
        '$note</aside>',
  ]);

  test('a note leaves out a back link that the book marks with the role '
      'doc-backlink', () async {
    expect(
      await noteRead(
        backBook(
          '<p>The note. <a href="s0.xhtml#ref-1" role="doc-backlink">'
          '\u21a9</a></p>',
        ),
      ),
      ['The note.'],
    );
  });

  test('a note leaves out a link back to its note reference, and keeps its '
      'other links', () async {
    expect(
      await noteRead(
        backBook(
          '<p>See <a href="s1.xhtml#other">the other text</a> too. '
          '<a href="s0.xhtml#ref-1">Return</a></p>',
        ),
      ),
      ['See the other text too.'],
    );
  });

  test('a note leaves out a back link drawn as a superscript, and keeps the '
      'note\'s own superscripts', () async {
    expect(
      await noteRead(
        backBook(
          '<p>The note<sup>2</sup>.<a href="s0.xhtml#ref-1" '
          'role="doc-backlink"><sup>back</sup></a></p>',
        ),
      ),
      ['The note2.'],
    );
  });

  test('a note leaves out a paragraph that holds only its back link', () async {
    expect(
      await noteRead(
        backBook(
          '<p>The note.</p><p><a href="s0.xhtml#ref-1" '
          'epub:type="backlink">Back to the text</a></p>',
        ),
      ),
      ['The note.'],
    );
  });

  test('note has nothing for a link that is no note reference, so the link '
      'jumps', () async {
    open(noteBook());
    await present();

    expect(
      await until(
        pager().note((href: 'text/s1.xhtml#plain', noteref: false), width: 412),
      ),
      isNull,
    );
  });

  test('note has nothing for a note that the book\'s style hides, so the '
      'link jumps', () async {
    open(
      book([
        '<p>Text<a epub:type="noteref" href="#n">1</a>.</p>'
            '<aside id="n" epub:type="footnote"><p>Hidden.</p></aside>',
      ], css: 'aside { display: none }'),
    );
    await present();

    expect(
      await until(
        pager().note((href: 'text/s0.xhtml#n', noteref: true), width: 412),
      ),
      isNull,
    );
  });

  test('display of a search hit lands on its match, and a place whose quote '
      'does not match throws', () async {
    open(linkedBook());
    await present();
    final report = await until(pager().search('target paragraph', 1));
    expect(report.hits, hasLength(1));
    final hit = report.hits.single.address as EpubAddress;

    await until(pager().display(hit));

    final prepared = await section(1);
    final match = placeOf(prepared.dom, 1, hit.location.cfi)!;
    expect(_holdsLine(shown().page, lineStart(prepared, match)), isTrue);
    expect(reported, hasLength(2));

    final page = shown().page;
    final wrong = EpubAddress(
      ReadingLocation(
        hit.location.cfi,
        hit.location.resource,
        'Some other words',
      ),
    );
    await expectLater(until(pager().display(wrong)), throwsA(anything));
    expect(shown().page, same(page));
    expect(reported, hasLength(2));
  });

  test('preview draws the true page of a place, and each previous and next '
      'place is held by exactly one page', () async {
    final publication = book([
      paragraphs(9),
      paragraphs(1, label: 'Brief'),
      paragraphs(14),
    ]);
    open(publication);
    final shownPage = (await present()).page;
    final previews = <PagePreview>[];
    final abandon = Completer<void>().future;

    var preview = await until(
      pager().preview((part: 0, progress: 0), 200, abandon),
    );
    previews.add(preview);
    expect(preview.image.width, 200);
    expect(
      preview.image.height,
      (200 / readerPage.width * readerPage.height).round(),
    );
    expect(preview.previous, isNull);
    for (var next = preview.next; next != null; next = preview.next) {
      expect(preview.holds(next), isFalse);
      final following = await until(pager().preview(next, 200, abandon));
      expect(following.holds(next), isTrue);
      final back = following.previous!;
      expect(following.holds(back), isFalse);
      expect(preview.holds(back), isTrue);
      previews.add(following);
      preview = following;
    }
    expect(preview.part, 2);
    expect(preview.end, 1);

    for (var index = 0; index < publication.spine.length; index++) {
      final prepared = await section(index);
      final whole = layoutSection(prepared);
      expect(
        previews.where((page) => page.part == index).length,
        whole.pages.length,
        reason: 'section $index',
      );
      for (final (at, page) in whole.pages.indexed) {
        final drawn = previews
            .where((preview) => preview.part == index)
            .toList()[at];
        expect(
          drawn.start,
          page.startVisible == 0
              ? 0
              : page.startVisible / prepared.dom.visibleLength,
          reason: 'section $index page $at',
        );
      }
      whole.dispose();
    }
    expect(shown().page, same(shownPage));
    expect(reported, hasLength(1));
    for (final page in previews) {
      page.image.dispose();
    }
  });

  test('preview stops when it is abandoned', () async {
    open(book([paragraphs(120, sentences: 10)]));
    await present();
    final abandon = Completer<void>();
    final drawn = pager().preview((part: 0, progress: .9), 200, abandon.future);
    abandon.complete();
    await expectLater(until(drawn), throwsA(isA<PageRequestStopped>()));
  });

  test('search returns the hits of the book search in book order', () async {
    for (final name in showcase.keys) {
      final publication = showcaseBook(name);
      open(publication);
      for (final query in ['the', 'and', 'It was']) {
        final report = await until(pager().search(query, 1));
        final expected = await searchBook(
          _sections(publication),
          query,
          publication.contents,
          publication.packagePath,
          isCurrent: () => true,
          hop: _inline,
        );
        expect(report.error, expected.error, reason: '$name $query');
        expect(
          [
            for (final hit in report.hits) [hit.address.toJson(), hit.excerpt],
          ],
          [
            for (final hit in expected.hits)
              [hit.address.toJson(), hit.excerpt],
          ],
          reason: '$name $query',
        );
      }
    }
  });

  test('a cancel stops the search between batches, and a cancel of another '
      'request does not', () async {
    final publication = book([
      for (var index = 0; index < 20; index++) '<p>Lantern $index.</p>',
    ]);
    var batches = 0;
    var cancel = 0;
    Future<R> counting<M, R>(FutureOr<R> Function(M) work, M input) async {
      batches++;
      pager().cancelSearch(cancel);
      return work(input);
    }

    open(publication, hop: counting);
    cancel = 7;
    final report = await until(pager().search('lantern', 7));
    expect(batches, 1);
    expect(report.hits, isEmpty);
    expect(report.error, isNull);

    batches = 0;
    cancel = 8;
    final full = await until(pager().search('lantern', 9));
    expect(batches, 3);
    expect(full.hits, hasLength(20));
  });

  test('the first page has page number 1 at once, the section\'s page '
      'count once its main run ends, and the book\'s once the whole book is '
      'laid out', () async {
    open(book([paragraphs(60), paragraphs(4)]));
    final first = await present();

    expect(pager().pageNumber.value, (number: 1, count: null));

    await until(source.mainRun(first.page, end: true));
    final whole = layoutSection(await section(0));
    final count = whole.pages.length;
    whole.dispose();
    if (!source.laidOut(1)) {
      expect(pager().pageNumber.value, (number: 1, count: count));
    }

    await scheduler.settle();
    final next = layoutSection(await section(1));
    expect(pager().pageNumber.value, (
      number: 1,
      count: count + next.pages.length,
    ));
    next.dispose();
    expect(shown().page, same(first.page));
  });

  test('a page deep in a section has no number until the main run passes it, '
      'and then its place among the true pages', () async {
    open(book([paragraphs(120, sentences: 10)]));
    await present();
    await until(pager().seek(0, .8));
    expect(pager().pageNumber.value, isNull);

    await scheduler.settle();
    final prepared = await section(0);
    final whole = layoutSection(prepared);
    final at = whole.pageAt(placeAt(prepared.dom, 0, .8));
    expect(pager().pageNumber.value, (
      number: at + 1,
      count: whole.pages.length,
    ));

    await until(pager().move(true));
    expect(pager().pageNumber.value, (
      number: at + 2,
      count: whole.pages.length,
    ));
    whole.dispose();
  });

  test('the page number follows turns into the next section and a new text '
      'size', () async {
    open(book([paragraphs(3), paragraphs(30)]));
    await present();
    await scheduler.settle();
    while (shown().page.section == 0) {
      await until(pager().move(true));
    }
    // The whole book is laid out, so the number counts its first section.
    var before = layoutSection(await section(0));
    expect(pager().pageNumber.value?.number, before.pages.length + 1);
    before.dispose();

    await present(largerText);
    expect(shown().page.settings, largerText);
    expect(
      pager().pageNumber.value?.number,
      1,
      reason: 'New settings count the chapter until the book is laid out.',
    );
    await scheduler.settle();
    before = layoutSection(await section(0));
    final whole = layoutSection(await section(1));
    expect(pager().pageNumber.value, (
      number: before.pages.length + 1,
      count: before.pages.length + whole.pages.length,
    ));
    before.dispose();
    whole.dispose();
  });

  test('after a text size change and back, the place stays and the page of '
      'the first settings comes back', () async {
    open(showcaseBook('salt'));
    await present();
    await until(pager().move(true));
    await until(pager().move(true));
    final page = shown().page;
    reported.clear();

    final small = await present(smallPage);
    expect(small.page.settings, smallPage);
    final back = await present(readerPage);

    expect(content(back.page), content(page));
    await scheduler.settle();
    expect(reported, isEmpty);
  });

  test('the host benchmark draws each deck page in a section in under '
      '20 ms', () async {
    open(book([for (var index = 0; index < 6; index++) paragraphs(60)]));
    await present();
    final abandon = Completer<void>().future;
    final watch = Stopwatch();
    final inSection = <Duration>[];
    final newSection = <Duration>[];
    var preview = await until(
      pager().preview((part: 0, progress: 0), 400, abandon),
    );
    for (var next = preview.next; next != null; next = preview.next) {
      final part = preview.part;
      preview.image.dispose();
      watch
        ..reset()
        ..start();
      preview = await scheduler.until(pager().preview(next, 400, abandon));
      (preview.part == part ? inSection : newSection).add(watch.elapsed);
    }
    preview.image.dispose();
    String times(List<Duration> times) {
      times.sort();
      return '${times.length} pages, median '
          '${times[times.length ~/ 2].inMicroseconds} us, p90 '
          '${times[times.length * 9 ~/ 10].inMicroseconds} us, slowest '
          '${times.last.inMicroseconds} us';
    }

    // ignore: avoid_print
    print(
      'deck pages in a section: ${times(inSection)}; '
      'first pages of a new section: ${times(newSection)}',
    );
    expect(inSection.last, lessThan(const Duration(milliseconds: 20)));
  }, skip: Platform.environment['BOOKFIN_PAGER_BENCHMARK'] != '1');
}

/// A hop that runs the work at once, on this isolate.
Future<R> _inline<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);

/// Whether [page] shows the line that starts at [line].
bool _holdsLine(LaidPage page, PageStart line) =>
    page.start == line ||
    (page.start.compareTo(line) < 0 &&
        line.compareTo(page.slices.last.at) <= 0);

/// The point of the shown [page] at the character at [place].
ui.Offset _pointOf(LaidPage page, EpubPlace place) {
  for (final piece in page.pieces) {
    for (var unit = 0; unit < piece.map.length; unit++) {
      if (piece.map.textPlaceAt(unit) != place) continue;
      final box = piece.paragraph.getBoxesForRange(unit, unit + 1).first;
      return ui.Offset(
        piece.x + (box.left + box.right) / 2,
        piece.y - page.top + (box.top + box.bottom) / 2,
      );
    }
  }
  throw StateError('$place is not on the page.');
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
