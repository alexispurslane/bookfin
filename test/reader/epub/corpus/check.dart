// Tool code for the on-demand corpus run (BOOKFIN_EPUB_CORPUS=1). It is
// not part of Bookfin and nothing in lib/ uses it.
//
// The checks that the corpus run makes on each book. Each check catches
// its own exceptions, so that one broken section does not hide the others.
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'book.dart';
import 'support.dart';

/// The page settings of the corpus run: the reader's default page, and a
/// smaller page with larger text.
const corpusSettings = [
  readerPage,
  PageSettings(width: 360, height: 640, fontSize: 26, night: false),
];

/// The name of [settings] in the results, such as 412x671@20.
String settingsName(PageSettings settings) =>
    '${settings.width.round()}x${settings.height.round()}'
    '@${settings.fontSize.round()}';

/// An exception that a check caught: the check, and where it happened.
class CaughtException {
  CaughtException(
    this.check,
    this.error,
    this.stack, {
    this.section,
    this.settings,
  });

  /// admit, support, prepare, fonts, layout, places, page starts or draw.
  final String check;
  final Object error;
  final StackTrace stack;
  final int? section;
  final PageSettings? settings;

  Map<String, Object?> toJson() => {
    'check': check,
    if (section != null) 'section': section,
    if (settings case final settings?) 'settings': settingsName(settings),
    'error': '$error',
    'stack': '$stack'.split('\n').take(8).join('\n'),
  };
}

/// A paragraph or a table whose layout took longer than the threshold.
class SlowItem {
  SlowItem(this.section, this.item, this.kind, this.milliseconds, this.text);
  final int section;

  /// The flow item's index in its section, and paragraph or table.
  final int item;
  final String kind;
  final double milliseconds;

  /// The start of the item's text.
  final String text;

  Map<String, Object> toJson() => {
    'section': section,
    'item': item,
    'kind': kind,
    'ms': _round(milliseconds),
    'text': text,
  };
}

/// What the checks found at one page settings value.
class SettingsReport {
  SettingsReport(this.settings);
  final PageSettings settings;

  /// The pages that start at a place, and how many of them the CFI of their
  /// start opens again: on the same page, with the same CFI, and with the
  /// same quote.
  int pageStarts = 0;
  int samePage = 0;
  int sameCfi = 0;
  int sameQuote = 0;

  /// The page starts whose CFI does not open their own page.
  final brokenPlaces = <String>[];

  /// The pages that show no line of text and no image.
  final blankPages = <String>[];

  /// The runs from a page start, the pages that they cut, and the runs
  /// that cut other pages than the main run.
  int runs = 0;
  int pagesCompared = 0;
  final runFailures = <String>[];

  /// The sections with more page starts than the run limit, whose runs
  /// start from evenly spaced page starts.
  int sampledSections = 0;

  int pages = 0;
  int visibleCharacters = 0;

  /// Milliseconds to prepare every section, and to lay out every section
  /// in its main run.
  double prepareMs = 0;
  double layoutMs = 0;

  /// Milliseconds to draw each drawn page and turn it into an image.
  final drawMs = <double>[];

  final slow = <SlowItem>[];

  /// Layout milliseconds per 10,000 visible characters.
  double get layoutMsPer10k =>
      visibleCharacters == 0 ? 0 : layoutMs / visibleCharacters * 10000;

  Map<String, Object> toJson() => {
    'pages': pages,
    'visibleCharacters': visibleCharacters,
    'pageStarts': pageStarts,
    'samePage': samePage,
    'sameCfi': sameCfi,
    'sameQuote': sameQuote,
    'brokenPlaces': brokenPlaces,
    'blankPages': blankPages,
    'runs': runs,
    'pagesCompared': pagesCompared,
    'runFailures': runFailures,
    'sampledSections': sampledSections,
    'prepareMs': _round(prepareMs),
    'layoutMs': _round(layoutMs),
    'layoutMsPer10k': _round(layoutMsPer10k),
    'drawnPages': drawMs.length,
    'drawMaxMs': _round(drawMs.fold(0.0, (a, b) => a > b ? a : b)),
    'slow': [for (final item in slow) item.toJson()],
  };
}

/// What the checks found in one book.
class BookReport {
  BookReport(this.id);
  final String id;
  int sections = 0;
  final exceptions = <CaughtException>[];
  SupportReport? support;

  /// The report at each page settings value, in the order of the run.
  final settings = <SettingsReport>[];

  /// Whether the book has no exception, no broken place, no blank page and
  /// no run that cut other pages.
  bool get passed =>
      exceptions.isEmpty &&
      settings.every(
        (report) =>
            report.brokenPlaces.isEmpty &&
            report.blankPages.isEmpty &&
            report.runFailures.isEmpty,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'sections': sections,
    'passed': passed,
    'exceptions': [for (final caught in exceptions) caught.toJson()],
    if (support case final support?) ...{
      'unsupported': _sections(support.unsupported),
      'approximations': _sections(support.approximated),
    },
    'settings': {
      for (final report in settings)
        settingsName(report.settings): report.toJson(),
    },
  };
}

Map<String, List<int>> _sections(Map<String, Set<int>> features) => {
  for (final MapEntry(:key, :value) in features.entries)
    key: value.toList()..sort(),
};

double _round(double value) => (value * 100).round() / 100;

/// Runs every check on the book that [open] admits, at each of [settings].
/// A flow item whose layout takes longer than [slow] is listed. Each run
/// from a page start is compared over the [compared] pages that it cuts
/// first, from at most [runsPerSection] page starts of each section. [clock]
/// gives the time for the measurements.
Future<BookReport> checkBook(
  String id,
  Future<CorpusBook> Function() open, {
  List<PageSettings> settings = corpusSettings,
  Duration slow = const Duration(milliseconds: 8),
  int compared = 5,
  int runsPerSection = 100,
  Duration Function()? clock,
}) async {
  if (runsPerSection < 2) {
    throw RangeError.value(
      runsPerSection,
      'runsPerSection',
      'must be 2 or more',
    );
  }
  final now = clock ?? _monotonic;
  final report = BookReport(id);
  final CorpusBook book;
  try {
    book = await open();
    book.publication.checkInvariants();
  } catch (error, stack) {
    report.exceptions.add(CaughtException('admit', error, stack));
    return report;
  }
  report.sections = book.sections;
  try {
    report.support = checkSupport(book);
  } catch (error, stack) {
    report.exceptions.add(CaughtException('support', error, stack));
  }
  for (final page in settings) {
    final found = SettingsReport(page);
    report.settings.add(found);
    for (var index = 0; index < book.sections; index++) {
      void caught(String check, Object error, StackTrace stack) =>
          report.exceptions.add(
            CaughtException(
              check,
              error,
              stack,
              section: index,
              settings: page,
            ),
          );
      final PreparedSection section;
      try {
        final begin = now();
        section = prepareSections([book.source(index)], page).single;
        found.prepareMs += _ms(now() - begin);
      } catch (error, stack) {
        caught('prepare', error, stack);
        continue;
      }
      found.visibleCharacters += section.dom.visibleLength;
      if (section.fonts.isNotEmpty) {
        try {
          await BookFonts.load(section.fonts, book.resource, book.fontPrefix);
        } catch (error, stack) {
          caught('fonts', error, stack);
        }
      }
      final ChapterLayout chapter;
      try {
        chapter = _layOut(section, found, slow, now);
      } catch (error, stack) {
        caught('layout', error, stack);
        continue;
      }
      found.pages += chapter.pages.length;
      try {
        _checkPlaces(book, chapter, found);
      } catch (error, stack) {
        caught('places', error, stack);
      }
      try {
        _checkRuns(chapter, found, compared, runsPerSection);
      } catch (error, stack) {
        caught('page starts', error, stack);
      }
      try {
        await _draw(book, chapter, found, now);
      } catch (error, stack) {
        caught('draw', error, stack);
      }
      chapter.dispose();
    }
  }
  return report;
}

final _watch = Stopwatch()..start();
Duration _monotonic() => _watch.elapsed;

double _ms(Duration duration) => duration.inMicroseconds / 1000;

/// Lays out [section] in a main run that steps one flow item at a time,
/// and times each step. Returns the section laid out in one step, after it
/// checks that both runs cut the same pages.
ChapterLayout _layOut(
  PreparedSection section,
  SettingsReport found,
  Duration slow,
  Duration Function() now,
) {
  final stepped = LayoutRun(section);
  try {
    while (!stepped.done) {
      final item = stepped.reached;
      final begin = now();
      // A step with no budget lays out exactly one flow item.
      stepped.step(Duration.zero);
      final took = now() - begin;
      found.layoutMs += _ms(took);
      if (took > slow) {
        switch (section.flow[item]) {
          case ParagraphItem(:final text):
            found.slow.add(
              SlowItem(
                section.index,
                item,
                'paragraph',
                _ms(took),
                _text(text),
              ),
            );
          case TableItem(:final rows):
            found.slow.add(
              SlowItem(
                section.index,
                item,
                'table',
                _ms(took),
                _cellText(rows),
              ),
            );
          default:
        }
      }
    }
    stepped.checkInvariants();
    final chapter = layoutSection(section);
    if (!_same(keys(stepped.pages), keys(chapter.pages))) {
      found.runFailures.add(
        'section ${section.index}: the stepped run cut other pages',
      );
    }
    return chapter;
  } finally {
    for (final page in stepped.pages) {
      page.dispose();
    }
    stepped.dispose();
  }
}

/// The CFI round trip: the CFI of each page start opens the same page. A
/// page with no line and no image is blank.
void _checkPlaces(
  CorpusBook book,
  ChapterLayout chapter,
  SettingsReport found,
) {
  final index = chapter.section.index;
  final dom = chapter.section.dom;
  for (var page = 0; page < chapter.pages.length; page++) {
    final laid = chapter.pages[page];
    if (laid.pieces.isEmpty &&
        !laid.decorations.any((shown) => shown is ImageDecoration)) {
      found.blankPages.add('section $index page $page');
    }
    final start = laid.startPlace;
    if (start == null) continue;
    found.pageStarts++;
    final place = wordStart(dom, start);
    final cfi = cfiOf(book.spine(index), dom, place);
    final back = placeOf(dom, index, cfi);
    if (spineIndexOf(cfi) != index || back == null) {
      found.brokenPlaces.add('$cfi: section $index page $page opens nothing');
      continue;
    }
    final opened = chapter.pageAt(back);
    if (opened == page) {
      found.samePage++;
    } else {
      found.brokenPlaces.add(
        '$cfi: section $index page $page opens page $opened',
      );
    }
    if (cfiOf(book.spine(index), dom, back) == cfi) found.sameCfi++;
    if (quoteAt(dom, back) == quoteAt(dom, place)) found.sameQuote++;
  }
}

/// A run from a page start cuts the same [compared] pages as the main run
/// after it. The runs start from every page start of the section, or from
/// [limit] evenly spaced ones that include the last page, when it has more.
/// A run that starts inside a table or a long paragraph lays it out again,
/// so the limit keeps a book such as Roget's Thesaurus, one 1.7-million-
/// character table, within minutes.
void _checkRuns(
  ChapterLayout chapter,
  SettingsReport found,
  int compared,
  int limit,
) {
  final main = chapter.pages;
  final starts = main.length - 1;
  if (starts > limit) found.sampledSections++;
  final pages = starts <= limit
      ? [for (var page = 1; page < main.length; page++) page]
      : {
          for (var at = 0; at < limit; at++)
            1 + at * (starts - 1) ~/ (limit - 1),
        }.toList();
  for (final page in pages) {
    final run = LayoutRun(chapter.section, from: main[page].start)
      ..step(const Duration(days: 1), want: compared);
    found.runs++;
    found.pagesCompared += run.pages.length;
    final expected = main.skip(page).take(run.pages.length);
    if (!_same(keys(run.pages), keys(expected))) {
      found.runFailures.add('section ${chapter.section.index}: page $page');
    }
    for (final laid in run.pages) {
      laid.dispose();
    }
    run.dispose();
  }
}

/// Draws the first, middle and last pages of [chapter] at the Pixel 8's
/// 2.625 image pixels per layout pixel, with their images.
Future<void> _draw(
  CorpusBook book,
  ChapterLayout chapter,
  SettingsReport found,
  Duration Function() now,
) async {
  const scale = 2.625;
  final settings = chapter.settings;
  final drawn = {
    0,
    chapter.pages.length ~/ 2,
    chapter.pages.length - 1,
  }.where((page) => page >= 0).map((page) => chapter.pages[page]).toList();
  final images = await decodeImages(drawn, book.resource, scale: scale);
  try {
    for (final page in drawn) {
      final begin = now();
      final picture = drawPage(page, images);
      final image = await picture.toImage(
        (settings.width * scale).round(),
        (settings.height * scale).round(),
      );
      found.drawMs.add(_ms(now() - begin));
      image.dispose();
      picture.dispose();
    }
  } finally {
    for (final image in images.values) {
      image.dispose();
    }
  }
}

bool _same(List<List<Object?>> a, List<List<Object?>> b) =>
    equals(b).matches(a, {});

/// The first 80 characters of [text].
String _text(StyledText text) {
  final all = StringBuffer();
  void add(StyledText text) {
    for (final run in text.runs) {
      switch (run) {
        case TextRun(:final text):
          all.write(text);
        case RaisedRun(:final text):
          add(text);
        default:
      }
      if (all.length >= 80) return;
    }
  }

  add(text);
  final found = all.toString().trim();
  return found.length > 80 ? found.substring(0, 80) : found;
}

/// The text of the first paragraph of the first cell of [rows] that has
/// one.
String _cellText(List<List<TableCell>> rows) {
  for (final row in rows) {
    for (final cell in row) {
      for (final item in cell.flow) {
        if (item is ParagraphItem) return _text(item.text);
      }
    }
  }
  return '';
}
