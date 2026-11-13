// The page source lays out the pages of an open book between frames, from
// the shown place outward, and keeps a bounded cache. A test scheduler runs
// its steps one at a time, so the tests count steps and choose when an
// animation runs.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bookfin/reader/document.dart' show ContentsEntry;
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers.dart';

/// A page small enough that a settings change moves every break.
const smallPage = PageSettings(
  width: 320,
  height: 260,
  fontSize: 18,
  night: false,
);

/// Runs the page source's steps only when a test says so, with the order of
/// Flutter's default scheduling strategy: urgent steps first, and idle steps
/// only while no animation runs.
class TestScheduler {
  final _urgent = Queue<void Function()>();
  final _idle = Queue<void Function()>();

  /// Whether an animation runs, which holds idle steps back.
  bool animating = false;

  /// Whether each step that ran was urgent, in order.
  final ran = <bool>[];

  /// Runs after every step.
  void Function()? afterStep;

  /// The number of idle steps that wait.
  int get idleWaiting => _idle.length;

  void schedule(void Function() step, {required bool urgent}) =>
      (urgent ? _urgent : _idle).add(step);

  /// Runs the next step that the strategy allows. Returns whether one ran.
  bool runOne() {
    final urgent = _urgent.isNotEmpty;
    if (!urgent && (animating || _idle.isEmpty)) return false;
    (urgent ? _urgent : _idle).removeFirst()();
    ran.add(urgent);
    afterStep?.call();
    return true;
  }

  /// Runs steps, and lets workers and decoders finish, until [future]
  /// completes. Returns its value.
  Future<T> until<T>(Future<T> future) async {
    var done = false;
    late T value;
    Object? error;
    StackTrace? trace;
    unawaited(
      future.then(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object caught, StackTrace stack) {
          error = caught;
          trace = stack;
          done = true;
        },
      ),
    );
    while (!done) {
      if (!runOne()) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await Future<void>.delayed(Duration.zero);
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value;
  }

  /// Runs every step that can run, until none has been queued for [quiet].
  Future<void> settle({
    Duration quiet = const Duration(milliseconds: 400),
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < quiet) {
      if (runOne()) clock.reset();
      await Future<void>.delayed(Duration.zero);
      if (_urgent.isEmpty && (animating || _idle.isEmpty)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
  }
}

/// An EPUB of one spine section for each of [bodies], styled by [css], with
/// [files] beside them, admitted as the reader admits a book. Its package
/// names [language] as its `dc:language`, or no language.
Publication book(
  List<String> bodies, {
  String css = '',
  Map<String, List<int>> files = const {},
  String? language,
}) {
  String type(String path) => switch (path.split('.').last) {
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'svg' => 'image/svg+xml',
    'woff' => 'font/woff',
    _ => 'application/octet-stream',
  };
  final entries = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
      '</rootfiles></container>',
    ),
    'OPS/book.opf': utf8.encode(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '${language == null ? '<metadata/>' : '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:language>$language</dc:language></metadata>'}'
      '<manifest>'
      '<item id="css" href="css/book.css" media-type="text/css"/>'
      '${[for (var i = 0; i < bodies.length; i++) '<item id="s$i" href="text/s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
      '${[for (final (i, path) in files.keys.indexed) '<item id="f$i" href="$path" media-type="${type(path)}"/>'].join()}'
      '</manifest><spine>'
      '${[for (var i = 0; i < bodies.length; i++) '<itemref idref="s$i"/>'].join()}'
      '</spine></package>',
    ),
    'OPS/css/book.css': utf8.encode(css),
    for (final (i, body) in bodies.indexed)
      'OPS/text/s$i.xhtml': utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Part</title>'
        '<link rel="stylesheet" href="../css/book.css"/></head>'
        '<body>$body</body></html>',
      ),
    for (final MapEntry(:key, :value) in files.entries) 'OPS/$key': value,
  };
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.addFile(ArchiveFile(key, value.length, value));
  }
  return Publication.admit(ZipEncoder().encodeBytes(archive));
}

/// [count] paragraphs of [sentences] sentences each.
String paragraphs(int count, {int sentences = 6, String label = 'Part'}) =>
    [for (var i = 0; i < count; i++) '<p>${prose(sentences, '$label $i')}</p>']
        .join();

/// The place [offset] code units into the text node [fraction] of the way
/// through [section]'s text nodes.
EpubPlace placeIn(PreparedSection section, double fraction, [int offset = 0]) {
  final texts = section.dom.texts;
  final text = texts[((texts.length - 1) * fraction).floor()];
  return EpubPlace(section.index, text.order, offset);
}

/// Runs the page source's worker calls in worker isolates, and holds back
/// each whole prepared section of spine index [section] that one gives
/// until [release] completes.
class HeldPrepares {
  HeldPrepares([this.section = 0]);
  final int section;
  final release = Completer<void>();

  Future<R> run<R>(FutureOr<R> Function() computation) async {
    final result = await Isolate.run(computation);
    if (result is PreparedSection && result.index == section) {
      await release.future;
    }
    return result;
  }
}

/// The place in the middle of the visible text of section 0, [dom]. It is
/// a top-level function, so that a worker can run it.
EpubPlace? middleOfFirst(DomSection dom) => placeAt(dom, 0, .5);

/// The first page that a run of [section] from [start] cuts, as a reader
/// sees it, and the page after it.
List<List<Object?>> wholePagesFrom(PreparedSection section, PageStart start) {
  final run = LayoutRun(section, from: start)
    ..step(const Duration(days: 1), want: 2);
  final shown = keys(run.pages.take(2));
  for (final page in run.pages) {
    page.dispose();
  }
  run.dispose();
  return shown;
}

/// What identifies a page's content: its start, its end and its line
/// starts.
List<Object?> content(LaidPage page) => [
  page.start,
  page.startPlace,
  page.endPlace,
  page.lineStarts,
];

/// [inner], which records the path of each file that the reader asks it
/// for. It gives only what the page source reads. With [fonts], it gives
/// each font file only after [fonts] completes.
class WatchedPublication implements Publication {
  WatchedPublication(this.inner, {this.fonts});
  final Publication inner;
  final Future<void>? fonts;

  /// The path of each file that [bytesOf] gave, in order.
  final asked = <String>[];

  @override
  Future<Uint8List?> bytesOf(String path) async {
    asked.add(path);
    if (path.endsWith('.woff')) await fonts;
    return inner.bytesOf(path);
  }

  @override
  Map<String, List<String>> get sectionFaces => inner.sectionFaces;

  @override
  String get identity => inner.identity;
  @override
  List<String> get spine => inner.spine;
  @override
  Map<String, Uint8List> get textFiles => inner.textFiles;
  @override
  Map<String, String> get bookStyles => inner.bookStyles;
  @override
  Map<String, String> stylesForSection(String path) =>
      inner.stylesForSection(path);
  @override
  Map<String, (int, int)> get imageSizes => inner.imageSizes;
  @override
  String? get language => inner.language;
  @override
  double get mainTextSize => inner.mainTextSize;

  @override
  String get packagePath => inner.packagePath;
  @override
  List<ContentsEntry> get contents => inner.contents;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;

  PageSource open(
    Publication publication, {
    Duration budget = const Duration(milliseconds: 4),
    PageSettings settings = readerPage,
    WorkerCall? work,
  }) => source = PageSource(
    publication,
    schedule: scheduler.schedule,
    budget: budget,
    work: work,
  )..settings = settings;

  setUp(() => scheduler = TestScheduler());
  tearDown(() => source.dispose());

  test(
    'an excerpt cannot restore a section whose page settings were dropped',
    () async {
      open(book(['<aside id="n"><p>The note.</p></aside>']));
      final section = await scheduler.until(source.section(0));
      source.settings = smallPage;
      source.settings = const PageSettings(
        width: 500,
        height: 700,
        fontSize: 22,
        night: false,
      );

      await expectLater(
        source.excerpt(section, section.dom.elementById('n')!, width: 240),
        throwsA(isA<PageRequestStopped>()),
      );
      source.checkInvariants();
    },
  );

  test(
    'dropping page settings stops an excerpt already between layout steps',
    () async {
      open(
        book(['<aside id="n"><p>${prose(100)}</p></aside>']),
        budget: Duration.zero,
      );
      final section = await scheduler.until(source.section(0));
      final pending = source.excerpt(
        section,
        section.dom.elementById('n')!,
        width: 240,
      );
      // Dispose a wrongly returned page too, so the red test leaks nothing.
      final stopped = expectLater(
        pending.then((page) {
          page?.dispose();
          return page;
        }),
        throwsA(isA<PageRequestStopped>()),
      );
      source.settings = smallPage;
      source.settings = const PageSettings(
        width: 500,
        height: 700,
        fontSize: 22,
        night: false,
      );

      await stopped;
      source.checkInvariants();
    },
  );

  test(
    'disposing the page source stops an excerpt between its layout steps',
    () async {
      open(
        book(['<aside id="n"><p>${prose(100)}</p></aside>']),
        budget: Duration.zero,
      );
      final section = await scheduler.until(source.section(0));
      final pending = source.excerpt(
        section,
        section.dom.elementById('n')!,
        width: 240,
      );
      final stopped = expectLater(pending, throwsA(isA<PageRequestStopped>()));
      source.dispose();
      await stopped;
    },
  );

  test(
    'a returned excerpt remains readable after its page source is disposed',
    () async {
      open(book(['<aside id="n"><p>The note remains readable.</p></aside>']));
      final section = await scheduler.until(source.section(0));
      final page = (await source.excerpt(
        section,
        section.dom.elementById('n')!,
        width: 240,
      ))!;
      addTearDown(page.dispose);
      final expected = content(page);
      source.dispose();

      expect(content(page), expected);
      expect(page.startPlace, isNotNull);
    },
  );

  test('opening deep in a 400,000-character section gives the anchored page '
      'after the prepare, one step for the line and the steps of one page, '
      'long before the main run ends', () async {
    open(book([paragraphs(500, sentences: 12)]));
    final section = await scheduler.until(source.section(0));
    expect(section.dom.visibleLength, greaterThan(400000));
    final place = placeIn(section, .9, 30);

    final before = scheduler.ran.length;
    final page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    final opening = scheduler.ran.length - before;

    expect(page.start, lineStart(section, place));
    expect(opening, lessThanOrEqualTo(3));
    expect(source.isTrue(page), isFalse);

    // The true page of the place needs the main run to pass it.
    source.show(page);
    final truePage = await scheduler.until(
      source.pageAt(place, anchored: false, urgent: true),
    );
    expect(source.isTrue(truePage), isTrue);
    expect(scheduler.ran.length - before, greaterThan(opening * 10));
  });

  group('a part of a large section', () {
    test('a jump deep into a large section shows its page before the whole '
        'section is prepared, and it is the whole section\'s page', () async {
      final held = HeldPrepares();
      open(book([paragraphs(500, sentences: 12)]), work: held.run);

      final place = await scheduler.until(source.findPlace(0, middleOfFirst));
      final page = await scheduler.until(
        source.pageAt(place!, anchored: true, urgent: true),
      );
      var prepared = false;
      unawaited(source.section(0).then((_) => prepared = true));
      await scheduler.settle(quiet: const Duration(milliseconds: 50));

      expect(prepared, isFalse);
      held.release.complete();
      final whole = await scheduler.until(source.section(0));
      expect(page.start, lineStart(whole, place));
      expect(pageKey(page), wholePagesFrom(whole, page.start).first);
    });

    test('the page after a page from a part comes from the part too, and '
        'once the section is prepared, both are the whole section\'s pages '
        'and the shown one gets its true number', () async {
      final held = HeldPrepares();
      open(book([paragraphs(500, sentences: 12)]), work: held.run);
      final place = await scheduler.until(source.findPlace(0, middleOfFirst));
      final page = await scheduler.until(
        source.pageAt(place!, anchored: true, urgent: true),
      );
      final next = await scheduler.until(source.after(page));
      source.show(page);

      held.release.complete();
      await scheduler.until(source.mainRun(page));
      final whole = await scheduler.until(source.section(0));

      expect([
        pageKey(page),
        pageKey(next!),
      ], wholePagesFrom(whole, page.start));
      expect(source.numberOf(page), isNotNull);
      source.checkInvariants();
    });

    test(
      'turning forward from a page of a part goes on in the part, and '
      'the page after the part waits quietly for the whole section',
      () async {
        final held = HeldPrepares();
        open(book([paragraphs(500, sentences: 12)]), work: held.run);
        final place = await scheduler.until(source.findPlace(0, middleOfFirst));
        var page = await scheduler.until(
          source.pageAt(place!, anchored: true, urgent: true),
        );
        final pages = [page];
        LaidPage? waiting;
        var asked = 0;
        while (waiting == null) {
          final next = source.after(page);
          asked++;
          LaidPage? laid;
          unawaited(next.then((found) => laid = found));
          // A wait that never ends means busy steps; settle returns once none
          // runs for the quiet time.
          await scheduler.settle(quiet: const Duration(milliseconds: 50));
          if (laid == null) {
            held.release.complete();
            waiting = await scheduler.until(next);
          } else {
            pages.add(page = laid!);
          }
        }
        final whole = await scheduler.until(source.section(0));
        final run = LayoutRun(whole, from: pages.first.start)
          ..step(const Duration(days: 1), want: asked + 1);

        expect(pages.length, greaterThan(1));
        expect(keys([...pages, waiting]), keys(run.pages.take(asked + 1)));
        for (final laid in run.pages) {
          laid.dispose();
        }
        run.dispose();
      },
    );

    test('a place inside one paragraph longer than a part gets the whole '
        'section from the same worker, without waiting for another '
        'prepare', () async {
      final held = HeldPrepares();
      // Each sentence is a text node of its own, so a part's end cuts the
      // paragraph.
      final lines = [
        for (var i = 0; i < 6000; i++) '<span>${prose(1, 'Line $i')}</span> ',
      ].join();
      open(book(['<p>$lines</p>']), work: held.run);

      final place = await scheduler.until(source.findPlace(0, middleOfFirst));
      final page = await scheduler.until(
        source.pageAt(place!, anchored: true, urgent: true),
      );

      final whole = source.sectionOf(page);
      expect(whole.whole, isTrue);
      expect(page.start, lineStart(whole, place));
      expect(identical(await source.section(0), whole), isTrue);
    });

    test('a place in a small section waits for its whole prepare, with no '
        'part', () async {
      final held = HeldPrepares();
      open(book([paragraphs(12)]), work: held.run);
      EpubPlace? place;
      unawaited(
        source.findPlace(0, middleOfFirst).then((found) => place = found),
      );
      await scheduler.settle(quiet: const Duration(milliseconds: 50));

      expect(place, isNull);
      held.release.complete();
      await scheduler.until(source.section(0));
      await scheduler.until(
        Future.doWhile(() async {
          await Future<void>.delayed(Duration.zero);
          return place == null;
        }),
      );
      final whole = await source.section(0);
      expect(place, placeAt(whole.dom, 0, .5));
    });
  });

  test('opening a place deep in a long table that no run measured measures '
      'one row of it in each step, not all of them in one', () async {
    open(
      book([
        '<table>${[for (var i = 0; i < 60; i++) '<tr><td>Speaker $i</td><td>${prose(1, 'Speech $i')}</td></tr>'].join()}</table>',
      ]),
      budget: Duration.zero,
    );
    final section = await scheduler.until(source.section(0));
    final place = placeIn(section, .9);

    final before = scheduler.ran.length;
    final page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );

    expect(scheduler.ran.length - before, greaterThanOrEqualTo(60));
    expect(page.start, lineStart(section, place));
  });

  test('pageAt that is not anchored waits for the true page that holds the '
      'place', () async {
    open(book([paragraphs(60)]));
    final section = await scheduler.until(source.section(0));
    final place = placeIn(section, .7, 25);
    final whole = layoutSection(section);
    final expected = whole.pages[whole.pageAt(place)];

    final page = await scheduler.until(source.pageAt(place, anchored: false));

    expect(source.isTrue(page), isTrue);
    expect(content(page), content(expected));
    whole.dispose();
  });

  test('urgent steps run before idle steps, and idle steps wait while an '
      'animation runs', () async {
    open(book([paragraphs(60), paragraphs(20)]));
    final section = await scheduler.until(source.section(0));
    final place = placeIn(section, .5);
    final page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    final from = scheduler.ran.length;

    scheduler.animating = true;
    source.show(page);
    await scheduler.settle();
    final duringAnimation = scheduler.ran.sublist(from);
    expect(duringAnimation, isNotEmpty);
    expect(duringAnimation, everyElement(isTrue));
    expect(scheduler.idleWaiting, greaterThan(0));

    scheduler.animating = false;
    await scheduler.settle();
    final afterAnimation = scheduler.ran.sublist(from + duringAnimation.length);
    expect(afterAnimation, contains(isFalse));
    // Once idle steps start, no urgent work is left for this page.
    expect(afterAnimation.skipWhile((urgent) => urgent), everyElement(isFalse));
  });

  test(
    'a page dropped from the cache and asked for again is the same page',
    () async {
      open(book([paragraphs(80)]));
      final section = await scheduler.until(source.section(0));
      final place = placeIn(section, .3, 10);
      final first = await scheduler.until(
        source.pageAt(place, anchored: false),
      );
      final remembered = content(first);

      var page = first;
      for (var turn = 0; turn < 30; turn++) {
        page = (await scheduler.until(source.after(page)))!;
      }
      expect(() => first.pieces, throwsStateError);

      final again = await scheduler.until(
        source.pageAt(place, anchored: false),
      );
      expect(again, isNot(same(first)));
      expect(content(again), remembered);
    },
  );

  test('after a settings change pages come for the new settings, and a change '
      'back reuses the prepared sections of the settings before', () async {
    open(book([paragraphs(30)]));
    final cream = await scheduler.until(source.section(0));
    final place = placeIn(cream, .5, 5);
    final first = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    source.show(first);

    source.settings = smallPage;
    final small = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    expect(small.settings, smallPage);
    expect((await scheduler.until(source.section(0))).settings, smallPage);
    source.show(small);

    source.settings = readerPage;
    final back = source.section(0);
    expect(await scheduler.until(back), same(cream));
    final page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    expect(page.settings, readerPage);
  });

  test('after crosses into the next section, and before crosses into the '
      "previous section's last true page", () async {
    open(book([paragraphs(12), paragraphs(12), paragraphs(3)]));
    final section = await scheduler.until(source.section(0));
    var page = await scheduler.until(
      source.pageAt(placeIn(section, 0), anchored: false),
    );
    expect(await scheduler.until(source.before(page)), isNull);
    final walked = <LaidPage>[page];
    while (page.section == 0) {
      page = (await scheduler.until(source.after(page)))!;
      walked.add(page);
    }
    final lastOfFirst = walked[walked.length - 2];
    expect(lastOfFirst.last, isTrue);
    expect(page.start, const PageStart(0, 0));
    expect(source.isTrue(page), isTrue);

    final back = (await scheduler.until(source.before(page)))!;
    expect(back.section, 0);
    expect(back.last, isTrue);
    expect(source.isTrue(back), isTrue);
    expect(content(back), content(lastOfFirst));

    while (!page.last || page.section < 2) {
      page = (await scheduler.until(source.after(page)))!;
    }
    expect(await scheduler.until(source.after(page)), isNull);
  });

  test('a scripted scrub over a whole book keeps the invariants after every '
      'step', () async {
    final publication = book([
      paragraphs(4),
      paragraphs(90),
      paragraphs(2, label: 'Brief'),
      paragraphs(40),
      paragraphs(25),
    ]);
    open(publication);
    scheduler.afterStep = source.checkInvariants;
    final sections = publication.spine.length;

    final start = await scheduler.until(source.section(0));
    var page = await scheduler.until(
      source.pageAt(placeIn(start, 0), anchored: true, urgent: true),
    );
    source.show(page);
    for (var turn = 0; turn < 12; turn++) {
      page = (await scheduler.until(source.after(page)))!;
      source.show(page);
      source.checkInvariants();
    }

    // A drag over the deck asks for the true pages across the book, and
    // abandons every third one.
    var stopped = 0;
    for (var index = 0; index < sections; index++) {
      final section = await scheduler.until(source.section(index));
      for (final fraction in [0.0, .25, .5, .75, 1.0]) {
        final abandon = Completer<void>();
        final request = source.pageAt(
          placeIn(section, fraction, 3),
          anchored: false,
          urgent: true,
          abandon: abandon.future,
        );
        if ((index * 5 + fraction * 4).round() % 3 == 0) {
          abandon.complete();
          await expectLater(
            scheduler.until(request),
            throwsA(isA<PageRequestStopped>()),
          );
          stopped++;
        } else {
          final preview = await scheduler.until(request);
          expect(source.isTrue(preview), isTrue);
          await scheduler.until(source.picture(preview, scale: .5));
        }
        source.checkInvariants();
      }
    }
    expect(stopped, greaterThan(0));

    source.settings = smallPage;
    final place = page.startPlace!;
    page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    source.show(page);
    for (var turn = 0; turn < 8; turn++) {
      final previous = await scheduler.until(source.before(page));
      if (previous == null) break;
      page = previous;
      source.show(page);
      source.checkInvariants();
    }
    source.settings = readerPage;
    page = await scheduler.until(
      source.pageAt(place, anchored: true, urgent: true),
    );
    source.show(page);
    await scheduler.settle();
    source.checkInvariants();
  });

  /// A book of one section whose paragraph of [words] names Outfit, a
  /// font of the book, as its family. With [faces], the book embeds Outfit
  /// with an `@font-face` rule and its font file. Outfit draws these
  /// letters about 9% narrower than the reader font, so its lines break
  /// elsewhere.
  Publication outfitBook(String words, {bool faces = true}) => book(
    ['<p>${'$words ' * 600}</p>'],
    css:
        '${faces ? '@font-face{font-family:Outfit;src:url(../fonts/outfit.woff)}' : ''}'
        'p{font-family:Outfit,serif}',
    files: {
      'fonts/outfit.woff': File('test/reader/epub/fixtures/outfit-ascii.woff')
          .readAsBytesSync(),
    },
  );

  test('a book that embeds its own font lays out in the reader font', () async {
    open(outfitBook('mim mu'));
    final section = await scheduler.until(source.section(0));

    final page = await scheduler.until(
      source.pageAt(placeIn(section, 0), anchored: true, urgent: true),
    );

    expect({for (final style in page.styles) style.family}, {readerFontFamily});
    final plain = outfitBook('mim mu', faces: false);
    final reader = layoutSection(
      prepareSections([
        SectionSource(
          index: 0,
          path: plain.spine.single,
          xhtml: utf8.decode(plain.textFiles[plain.spine.single]!),
          styleSheets: plain.bookStyles,
        ),
      ], readerPage).single,
    );
    addTearDown(reader.dispose);
    expect(page.lineStarts, reader.pages.first.lineStarts);
  });

  test('a book whose own font only repeats letters that the reader font has '
      'reads no font file', () async {
    // Words of their own, so that no other test opened this book.
    final publication = WatchedPublication(outfitBook('mum im'));
    open(publication);
    final section = await scheduler.until(source.section(0));

    source.show(
      await scheduler.until(
        source.pageAt(placeIn(section, 0), anchored: true, urgent: true),
      ),
    );
    await scheduler.settle();

    expect(publication.asked, isNot(contains(endsWith('.woff'))));
  });

  test('only the section that needs a book font waits for it, and its runs '
      'name that font', () async {
    final fonts = Completer<void>();
    final publication = WatchedPublication(
      book(
        ['<p>${prose(8)}</p>', '<p>A star \u2605 here. ${prose(8)}</p>'],
        css:
            '@font-face{font-family:Star;src:url(../fonts/star.woff)}'
            'p{font-family:Star,serif}',
        files: {
          'fonts/star.woff': File('test/reader/epub/fixtures/outfit-star.woff')
              .readAsBytesSync(),
        },
      ),
      fonts: fonts.future,
    );
    open(publication);

    final plain = await scheduler.until(source.section(0));
    await scheduler.until(
      source.pageAt(placeIn(plain, 0), anchored: true, urgent: true),
    );
    expect(publication.asked, isNot(contains(endsWith('.woff'))));
    expect([for (final style in plain.styles) style.face], everyElement(null));

    PreparedSection? starred;
    unawaited(source.section(1).then((section) => starred = section));
    await scheduler.settle(quiet: const Duration(milliseconds: 50));
    expect(publication.asked, contains(endsWith('star.woff')));
    expect(starred, isNull);

    fonts.complete();
    final section = await scheduler.until(source.section(1));
    expect({
      for (final style in section.styles) style.face,
    }, contains(startsWith('bookfin-')));
  });

  test('a draft draws outlines for images not decoded yet, and the picture '
      'draws them decoded', () async {
    final red = img.Image(width: 200, height: 200)
      ..clear(img.ColorRgb8(220, 20, 20));
    open(
      book(
        [
          '<p>Map.</p><img src="../images/map.png" style="display:block;width:200px"/>',
        ],
        files: {'images/map.png': img.encodePng(red)},
      ),
    );
    final section = await scheduler.until(source.section(0));
    final page = await scheduler.until(
      source.pageAt(placeIn(section, 0), anchored: true, urgent: true),
    );
    final image = page.decorations.whereType<ImageDecoration>().single;
    final centre = image.rect.center.translate(0, -page.top);

    Future<ui.Color> colorAt(ui.Picture picture) async {
      final raster = await picture.toImage(
        readerPage.width.round(),
        readerPage.height.round(),
      );
      final bytes = (await raster.toByteData())!;
      raster.dispose();
      final at =
          (centre.dy.round() * readerPage.width.round() + centre.dx.round()) *
          4;
      return ui.Color.fromARGB(
        bytes.getUint8(at + 3),
        bytes.getUint8(at),
        bytes.getUint8(at + 1),
        bytes.getUint8(at + 2),
      );
    }

    expect(await colorAt(source.draft(page)), readerPage.paper);
    final drawn = await colorAt(
      await scheduler.until(source.picture(page, scale: 2)),
    );
    expect(drawn.r, greaterThan(.8));
    expect(drawn.g, lessThan(.2));
  });

  group('the order of work around the shown page', () {
    /// Shows the anchored page at [fraction] of section [index].
    Future<LaidPage> showAt(int index, double fraction) async {
      final section = await scheduler.until(source.section(index));
      final page = await scheduler.until(
        source.pageAt(placeIn(section, fraction), anchored: true, urgent: true),
      );
      source.show(page);
      return page;
    }

    /// The sections of a book of [count] sections in the order in which
    /// their main runs end from now on, after each step.
    List<int> laidOutOrder(int count) {
      final order = <int>[];
      final before = {
        for (var index = 0; index < count; index++)
          if (source.laidOut(index)) index,
      };
      scheduler.afterStep = () {
        for (var index = 0; index < count; index++) {
          if (!before.contains(index) &&
              !order.contains(index) &&
              source.laidOut(index)) {
            order.add(index);
          }
        }
      };
      return order;
    }

    test("a turn into the next section waits only for that section's "
        "prepare, not for the previous section's", () async {
      final held = HeldPrepares();
      addTearDown(() {
        if (!held.release.isCompleted) held.release.complete();
      });
      open(
        book([paragraphs(4), paragraphs(12), paragraphs(2, label: 'Brief')]),
        work: held.run,
      );
      final shown = await scheduler.until(source.section(1));
      final last = await scheduler.until(
        source.pageAt(placeIn(shown, 1), anchored: true, urgent: true),
      );
      expect(last.last, isTrue);
      source.show(last);

      final ended = <String>[];
      final turn = source.after(last).then((page) {
        ended.add('turn');
        return page;
      });
      final previous = source.section(0).then((_) => ended.add('previous'));
      final next = await scheduler.until(turn);
      expect(next!.section, 2);
      expect(ended, ['turn']);
      held.release.complete();
      await scheduler.until(previous);
      expect(ended, ['turn', 'previous']);
    });

    test('after the shown section, the sections after it are laid out in '
        'order to the right and the sections before it in order to the '
        'left', () async {
      open(book([for (var i = 0; i < 7; i++) paragraphs(6, label: 'S$i')]));
      final order = laidOutOrder(7);
      await showAt(3, .5);
      await scheduler.settle();

      expect(order.first, 3);
      expect(order.where((index) => index > 3), [4, 5, 6]);
      expect(order.where((index) => index < 3), [2, 1, 0]);
    });

    test('the sections after the shown one do not wait for a large section '
        'before it', () async {
      open(
        book([
          paragraphs(2, label: 'Opening'),
          paragraphs(500, sentences: 12),
          paragraphs(10),
          for (var i = 0; i < 3; i++) paragraphs(2, label: 'Brief $i'),
        ]),
      );
      final order = laidOutOrder(6);
      await showAt(2, .5);
      await scheduler.settle();

      expect(order.first, 2);
      expect(order.indexOf(5), lessThan(order.indexOf(1)));
      expect(order.indexOf(1), lessThan(order.indexOf(0)));
    });

    test(
      'the two directions take turns, so the sections after the shown '
      'one do not wait for the main run of a large section before it',
      () async {
        // A step lays out one paragraph, so the large section needs hundreds.
        open(
          book([
            paragraphs(400),
            paragraphs(6),
            for (var i = 0; i < 6; i++) paragraphs(12, label: 'After $i'),
          ]),
          budget: Duration.zero,
        );
        await scheduler.until(source.section(0));
        final order = laidOutOrder(8);
        await showAt(1, .5);
        await scheduler.settle();

        expect(order.indexOf(7), lessThan(order.indexOf(0)));
      },
    );

    test('the whole book is laid out when the reader stays, and the '
        'sections next to the shown one stay ready for a turn', () async {
      const count = 10;
      open(book([for (var i = 0; i < count; i++) paragraphs(30)]));
      scheduler.afterStep = source.checkInvariants;
      await showAt(5, .5);
      await scheduler.settle();

      expect([
        for (var index = 0; index < count; index++) source.laidOut(index),
      ], everyElement(isTrue));
      source.checkInvariants();

      final section = await scheduler.until(source.section(5));
      final first = await scheduler.until(
        source.pageAt(placeIn(section, 0), anchored: false),
      );
      var last = await scheduler.until(
        source.pageAt(placeIn(section, 1), anchored: false),
      );
      while (!last.last) {
        last = (await scheduler.until(source.after(last)))!;
      }
      final before = scheduler.ran.length;
      final back = await scheduler.until(source.before(first));
      final forward = await scheduler.until(source.after(last));

      expect(back!.section, 4);
      expect(forward!.section, 6);
      expect(scheduler.ran.length - before, 0);
    });

    test('a jump into a table of a section that was laid out and let go '
        'does not measure the whole table again', () async {
      open(
        book([
          [
            '<table>',
            for (var i = 0; i < 120; i++)
              '<tr><td>Row $i</td><td>${prose(i % 3 + 1, 'Cell $i')}</td></tr>',
            '</table>',
          ].join('\n'),
          for (var i = 0; i < 9; i++) paragraphs(30),
        ]),
      );
      await showAt(9, .5);
      await scheduler.settle();
      expect(source.laidOut(0), isTrue);
      final before = LayoutRun.measuredCells;

      await showAt(0, .5);

      // The rows of the pages around the jump are measured again, to check
      // the widths that the section's main run found. The table has 240
      // cells.
      expect(LayoutRun.measuredCells - before, lessThan(120));
    });

    test('a jump restarts the order from the jumped-to page', () async {
      const count = 9;
      open(book([for (var i = 0; i < count; i++) paragraphs(8)]));
      final page = await showAt(1, .5);
      await scheduler.until(source.mainRun(page, end: true));

      await showAt(7, .5);
      final order = laidOutOrder(count);
      await scheduler.settle();

      expect(order.first, 7);
      expect(order.where((index) => index > 7), [8]);
      final left = order.where((index) => index < 7).toList();
      expect(left, isNotEmpty);
      expect(left, [...left]..sort((a, b) => b.compareTo(a)));
      expect([
        for (var index = 0; index < count; index++) source.laidOut(index),
      ], everyElement(isTrue));
    });

    test('the work waits while idle steps are held, as during an animation '
        'or in the background, and goes on after', () async {
      const count = 5;
      open(book([for (var i = 0; i < count; i++) paragraphs(6)]));
      scheduler.animating = true;
      await showAt(2, .5);
      await scheduler.settle();
      // The shown page's neighbors are urgent, and in a short section they
      // can reach its end. No other section is laid out.
      expect([
        for (var index = 0; index < count; index++)
          if (index != 2) source.laidOut(index),
      ], everyElement(isFalse));

      scheduler.animating = false;
      await scheduler.settle();
      expect([
        for (var index = 0; index < count; index++) source.laidOut(index),
      ], everyElement(isTrue));
    });

    test('closing the reader stops the work without errors', () async {
      const count = 8;
      open(book([for (var i = 0; i < count; i++) paragraphs(20)]));
      await showAt(4, .5);
      for (var step = 0; step < 6; step++) {
        scheduler.runOne();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      source.dispose();
      final ran = scheduler.ran.length;
      await scheduler.settle();
      // The steps that were scheduled before the close do nothing.
      expect(scheduler.ran.length - ran, lessThanOrEqualTo(2));
      expect(scheduler.idleWaiting, 0);
    });

    test('after a settings change the whole book is laid out for the new '
        'settings, and a change back finds the layout of the settings '
        'before', () async {
      const count = 5;
      open(book([for (var i = 0; i < count; i++) paragraphs(6)]));
      final page = await showAt(2, .5);
      await scheduler.settle();

      source.settings = smallPage;
      expect(source.laidOut(0), isFalse);
      final small = await scheduler.until(
        source.pageAt(page.startPlace!, anchored: true, urgent: true),
      );
      source.show(small);
      await scheduler.settle();
      expect([
        for (var index = 0; index < count; index++) source.laidOut(index),
      ], everyElement(isTrue));

      source.settings = readerPage;
      expect([
        for (var index = 0; index < count; index++) source.laidOut(index),
      ], everyElement(isTrue));
    });
  });

  test('the host benchmark shows no step longer than the budget plus the '
      'longest paragraph', () async {
    const budget = Duration(milliseconds: 4);
    final publication = book([
      for (var i = 0; i < 6; i++)
        paragraphs(i.isEven ? 200 : 40, sentences: 10 + i),
    ]);
    final watch = Stopwatch();
    final steps = <Duration>[];
    final schedule = scheduler.schedule;
    source = PageSource(
      publication,
      budget: budget,
      schedule: (step, {required urgent}) => schedule(() {
        watch
          ..reset()
          ..start();
        step();
        steps.add(watch.elapsed);
      }, urgent: urgent),
    )..settings = readerPage;

    // The longest paragraph: a run stepped with no budget lays out one
    // flow item a step.
    var longest = Duration.zero;
    for (var index = 0; index < publication.spine.length; index++) {
      final section = await scheduler.until(source.section(index));
      final run = LayoutRun(section);
      while (!run.done) {
        watch
          ..reset()
          ..start();
        run.step(Duration.zero);
        if (watch.elapsed > longest) longest = watch.elapsed;
      }
      for (final page in run.pages) {
        page.dispose();
      }
      run.dispose();
    }

    final first = await scheduler.until(source.section(0));
    var page = await scheduler.until(
      source.pageAt(placeIn(first, .5), anchored: true, urgent: true),
    );
    source.show(page);
    for (var turn = 0; turn < 40; turn++) {
      page = (await scheduler.until(source.after(page)))!;
      source.show(page);
    }
    await scheduler.settle();
    steps.sort();
    final slowest = steps.last;
    // ignore: avoid_print
    print(
      'page source steps: ${steps.length}, median '
      '${steps[steps.length ~/ 2].inMicroseconds} us, slowest '
      '${slowest.inMicroseconds} us; longest paragraph '
      '${longest.inMicroseconds} us; budget ${budget.inMicroseconds} us',
    );
    expect(slowest, lessThanOrEqualTo(budget + longest));
  }, skip: Platform.environment['BOOKFIN_PAGE_SOURCE_BENCHMARK'] != '1');
}
