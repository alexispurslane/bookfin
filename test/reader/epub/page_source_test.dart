// The page source lays out the pages of an open book between frames, from
// the shown place outward, and keeps a bounded cache. A test scheduler runs
// its steps one at a time, so the tests count steps and choose when an
// animation runs.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_epub_viewer/publication.dart';
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
/// [files] beside them, admitted as the reader admits a book.
Publication book(
  List<String> bodies, {
  String css = '',
  Map<String, List<int>> files = const {},
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
      '<metadata/><manifest>'
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

/// What identifies a page's content: its start, its end and its line
/// starts.
List<Object?> content(LaidPage page) => [
  page.start,
  page.startPlace,
  page.endPlace,
  page.lineStarts,
];

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;

  PageSource open(
    Publication publication, {
    Duration budget = const Duration(milliseconds: 4),
    PageSettings settings = readerPage,
  }) => source = PageSource(
    publication,
    schedule: scheduler.schedule,
    budget: budget,
  )..settings = settings;

  setUp(() => scheduler = TestScheduler());
  tearDown(() => source.dispose());

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

  test('embedded fonts are registered before the first paragraph that uses '
      'them lays out', () async {
    final woff = File('test/reader/epub/fixtures/outfit-ascii.woff')
        .readAsBytesSync();
    // Outfit draws these letters about 9% narrower than the reader font,
    // so its lines break elsewhere.
    final body = '<p>${'mim mu ' * 600}</p>';
    final publication = book(
      [body],
      css:
          '@font-face{font-family:Outfit;src:url(../fonts/outfit.woff)}'
          'p{font-family:Outfit,serif}',
      files: {'fonts/outfit.woff': woff},
    );
    open(publication);
    final section = await scheduler.until(source.section(0));
    expect(section.fonts, isNotEmpty);

    final page = await scheduler.until(
      source.pageAt(placeIn(section, 0), anchored: true, urgent: true),
    );

    final prefix = 'bookfin-${publication.identity.substring(0, 12)}';
    await BookFonts.load(
      section.fonts,
      (path) => publication.resources[path],
      prefix,
    );
    final reference = layoutSection(section);
    final fallback = layoutSection(
      prepareSections([
        SectionSource(
          index: 0,
          path: publication.spine.single,
          xhtml: utf8.decode(publication.resources[publication.spine.single]!),
          fontPrefix: 'bookfin-ffffffffffff',
          styleSheets: publication.bookStyles,
        ),
      ], readerPage).single,
    );
    expect(page.lineStarts, reference.pages.first.lineStarts);
    expect(page.lineStarts, isNot(fallback.pages.first.lineStarts));
    reference.dispose();
    fallback.dispose();
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
