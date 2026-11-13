// The on-demand survey of ticket boo-ystu: what a disk cache of layout
// results would hold, how large it is, how long it takes to read, and how
// much layout time it saves. docs/research/epub-layout-cache.md describes
// the results. It is not part of Bookfin's normal test run.
//
// In the dev shell, from the repository root, after the corpus fetch
// (python3 -I tool/reader/fetch_epub_corpus.py):
//
//   BOOKFIN_LAYOUT_CACHE=1 flutter test test/research/epub_layout_cache_test.dart
//
// Each run writes .cache/layout-cache-survey/run-<n>.json: the numbers of
// each book, and every true page start of every section. A run compares
// its page starts with those of the run before it, which is the check of
// determinism across processes. BOOKFIN_LAYOUT_CACHE_BOOKS takes a list of
// book ids, separated by commas, to survey some books only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../reader/epub/corpus/book.dart';
import '../reader/epub/corpus/list.dart';
import '../reader/epub/helpers.dart';

final _enabled = Platform.environment['BOOKFIN_LAYOUT_CACHE'] == '1';
final _only = Platform.environment['BOOKFIN_LAYOUT_CACHE_BOOKS']
    ?.split(',')
    .where((id) => id.isNotEmpty)
    .toSet();
final _directory = Directory('.cache/layout-cache-survey');

/// The settings of the survey: the WebView reader's default page, and a
/// small phone page with large text.
const _settings = [
  readerPage,
  PageSettings(width: 360, height: 640, fontSize: 26, night: false),
];

final _watch = Stopwatch()..start();
double _now() => _watch.elapsedMicroseconds / 1000;

void main() {
  if (!_enabled) {
    test('the layout cache survey', () {}, skip: 'set BOOKFIN_LAYOUT_CACHE=1');
    return;
  }
  setUpAll(loadReaderFont);
  final books = [
    for (final book in corpusList())
      if (_only == null || _only!.contains(book.id)) book,
  ];
  final previous = _previousRun();
  final results = <String, Object?>{};
  final starts = <String, Object?>{};
  final run = _nextRun();

  for (final book in books) {
    test(book.id, () async {
      final bytes = book.url == null
          ? showcaseBooks()[book.id]!
          : await book.file.readAsBytes();
      final corpus = book.format == 'azw3'
          ? CorpusBook(
              (await importMobi(
                VerifiedFile(book.file.uri, sha256.convert(bytes).toString()),
              )).publication,
            )
          : CorpusBook.open(bytes);
      final found = await _survey(corpus);
      results[book.id] = found.numbers;
      starts[book.id] = found.starts;
      if (previous?[book.id] case final Object before) {
        found.numbers['crossProcessMismatches'] = _mismatches(
          before,
          found.starts,
        );
      }
      await _write(run, results, starts);
    }, timeout: Timeout.none);
  }
}

/// The page starts of the last run, by book, or null when none ran.
Map<String, Object?>? _previousRun() {
  final runs = _runs();
  if (runs.isEmpty) return null;
  final json = jsonDecode(
    File('${_directory.path}/run-${runs.last}.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return json['starts'] as Map<String, Object?>;
}

List<int> _runs() {
  if (!_directory.existsSync()) return [];
  return [
    for (final entry in _directory.listSync())
      if (RegExp(r'run-(\d+)\.json$').firstMatch(entry.path) case final match?)
        int.parse(match.group(1)!),
  ]..sort();
}

int _nextRun() => (_runs().lastOrNull ?? 0) + 1;

Future<void> _write(
  int run,
  Map<String, Object?> results,
  Map<String, Object?> starts,
) async {
  await _directory.create(recursive: true);
  await File('${_directory.path}/run-$run.json')
      .writeAsString(jsonEncode({'books': results, 'starts': starts}));
}

/// The sections whose page starts differ between [before] and [after]:
/// settings name, section index.
List<String> _mismatches(Object before, Map<String, Object?> after) {
  final old = before as Map<String, dynamic>;
  return [
    for (final MapEntry(key: name, value: sections) in after.entries)
      for (final (index, section) in (sections! as List).indexed)
        if (jsonEncode((old[name] as List?)?[index]) != jsonEncode(section))
          '$name $index',
  ];
}

String _name(PageSettings settings) =>
    '${settings.width.round()}x${settings.height.round()}'
    '@${settings.fontSize.round()}';

/// What the survey found in one book.
class _Found {
  final numbers = <String, Object?>{};

  /// Every true page start of every section, by settings name: a list of
  /// sections, each a flat list of item, line and part numbers.
  final starts = <String, Object?>{};
}

Future<_Found> _survey(CorpusBook book) async {
  final found = _Found();
  final numbers = found.numbers;
  numbers['sections'] = book.sections;
  for (final settings in _settings) {
    final name = _name(settings);
    final full = settings == readerPage;
    final sections = <Map<String, Object?>>[];
    final allStarts = <List<PageStart>>[];
    for (var index = 0; index < book.sections; index++) {
      final source = book.source(index);
      final section = <String, Object?>{'index': index};
      sections.add(section);
      section['xhtmlBytes'] = utf8.encode(source.xhtml).length;

      // Prepare, and its first two stages alone.
      var begin = _now();
      final dom = DomSection.parse(source.xhtml);
      section['parseMs'] = _now() - begin;
      begin = _now();
      styleSection(source, dom, settings);
      section['styleMs'] = _now() - begin;
      begin = _now();
      final prepared = prepareSections([source], settings).single;
      section['prepareMs'] = _now() - begin;
      section['characters'] = prepared.dom.visibleLength;

      // The main run, timed to each page that it publishes.
      final main = LayoutRun(prepared);
      final publishedAt = <double>[];
      begin = _now();
      while (!main.done) {
        main.step(Duration.zero);
        while (publishedAt.length < main.pages.length) {
          publishedAt.add(_now() - begin);
        }
      }
      section['layoutMs'] = publishedAt.last;
      final starts = [for (final page in main.pages) page.start];
      allStarts.add(starts);
      section['pages'] = starts.length;

      if (full) {
        _standIn(book, source, settings, main, publishedAt, section);
        _nightStarts(source, settings, starts, section);
        _preparedSize(prepared, section);
      }
      for (final page in main.pages) {
        page.dispose();
      }
      main.dispose();
    }
    found.starts[name] = [
      for (final starts in allStarts)
        [
          for (final start in starts) ...[start.item, start.line, start.part],
        ],
    ];
    numbers[name] = {'sections': sections, ..._encodings(allStarts)};
  }
  return found;
}

/// Lays out each true page again from its start alone, in a section
/// prepared again (so no table is measured yet), as a page source with
/// cached page starts would. Records whether each page and its following
/// start equal the main run's, and the times of a jump to the middle page.
void _standIn(
  CorpusBook book,
  SectionSource source,
  PageSettings settings,
  LayoutRun main,
  List<double> publishedAt,
  Map<String, Object?> section,
) {
  final fresh = prepareSections([source], settings).single;
  final measurements = LayoutMeasurements();
  final pages = main.pages;
  final middle = pages.length ~/ 2;

  // The jump to the middle page's first place, in the fresh section: the
  // line search that the page source does today, then one page from the
  // true start that a cache would give, or from the line's start, as the
  // anchored run does today.
  final place = pages[middle].startPlace;
  if (place != null) {
    var begin = _now();
    final line = lineStart(fresh, place, measurements: measurements);
    section['jumpLineSearchMs'] = _now() - begin;
    begin = _now();
    final fromCache = LayoutRun(
      fresh,
      measurements: measurements,
      from: pages[middle].start,
    )..step(const Duration(days: 1), want: 1);
    section['jumpPageFromCachedStartMs'] = _now() - begin;
    section['jumpLineIsTrueStart'] = line == pages[middle].start;
    begin = _now();
    final anchored = LayoutRun(fresh, measurements: measurements, from: line)
      ..step(const Duration(days: 1), want: 1);
    section['jumpAnchoredPageMs'] = _now() - begin;
    for (final run in [fromCache, anchored]) {
      for (final page in run.pages) {
        page.dispose();
      }
      run.dispose();
    }
    // Today, the true page and its number wait for the main run to pass
    // the middle page.
    section['mainRunToMiddleMs'] = publishedAt[middle];
  }

  final times = <double>[];
  var differ = 0;
  var keyDiffer = 0;
  for (var at = 0; at < pages.length; at++) {
    final begin = _now();
    final run = LayoutRun(
      fresh,
      measurements: measurements,
      from: pages[at].start,
    )..step(const Duration(days: 1), want: 1);
    times.add(_now() - begin);
    final page = run.pages.first;
    final next = at + 1 < pages.length ? pages[at + 1].start : null;
    // One step can cut more than one page, so the start after this page
    // is the next published page's start, or the run's next start.
    final after = run.pages.length > 1 ? run.pages[1].start : run.next;
    final sameKey =
        jsonEncode(pageKey(page).map((each) => '$each').toList()) ==
        jsonEncode(pageKey(pages[at]).map((each) => '$each').toList());
    final sameNext = next == null ? page.last : !page.last && after == next;
    if (!sameKey || !sameNext) differ++;
    if (!sameKey) keyDiffer++;
    for (final laid in run.pages) {
      laid.dispose();
    }
    run.dispose();
  }
  times.sort();
  section['standInPagesDiffer'] = differ;
  section['standInKeysDiffer'] = keyDiffer;
  section['pageFromStartMedianMs'] = times[times.length ~/ 2];
  section['pageFromStartMaxMs'] = times.last;
  section['pageFromStartTotalMs'] = times.fold<double>(0, (a, b) => a + b);
}

/// Whether the night colors cut the same pages.
void _nightStarts(
  SectionSource source,
  PageSettings settings,
  List<PageStart> starts,
  Map<String, Object?> section,
) {
  final night = PageSettings(
    width: settings.width,
    height: settings.height,
    fontSize: settings.fontSize,
    night: true,
  );
  final prepared = prepareSections([source], night).single;
  final run = LayoutRun(prepared)..step(const Duration(days: 1));
  final nightStarts = [for (final page in run.pages) page.start];
  section['nightSameStarts'] = _sameStarts(starts, nightStarts);
  for (final page in run.pages) {
    page.dispose();
  }
  run.dispose();
}

bool _sameStarts(List<PageStart> a, List<PageStart> b) =>
    a.length == b.length &&
    [for (var at = 0; at < a.length; at++) a[at] == b[at]].every((x) => x);

/// A lower bound of the size of a binary encoding of [prepared]: its DOM
/// text, the text of its runs with their hyphenation points, one byte for
/// each DOM offset of a run's code unit, eight bytes for each DOM node and
/// twelve for each flow item, and the attributes.
void _preparedSize(PreparedSection prepared, Map<String, Object?> section) {
  var domText = 0;
  var nodes = 0;
  var attributes = 0;
  void walk(DomElement element) {
    nodes++;
    for (final MapEntry(:key, :value) in element.attributes.entries) {
      attributes += key.length + value.length + 2;
    }
    for (final child in element.children) {
      switch (child) {
        case DomElement():
          walk(child);
        case DomText(:final text):
          nodes++;
          domText += utf8.encode(text).length;
      }
    }
  }

  walk(prepared.dom.root);
  var items = 0;
  var runText = 0;
  var offsets = 0;
  void runs(StyledText text) {
    for (final run in text.runs) {
      switch (run) {
        case TextRun(:final text, offsets: final units):
          runText += utf8.encode(text).length;
          offsets += units.length;
        case RaisedRun(:final text):
          runs(text);
        default:
      }
    }
  }

  void flow(List<FlowItem> list) {
    for (final item in list) {
      items++;
      switch (item) {
        case ParagraphItem(:final text):
          runs(text);
        case TableItem(:final rows):
          for (final row in rows) {
            for (final cell in row) {
              flow(cell.flow);
            }
          }
        default:
      }
    }
  }

  flow(prepared.flow);
  section['flowItems'] = items;
  section['domNodes'] = nodes;
  section['preparedBytesEstimate'] =
      domText + runText + offsets + 8 * nodes + 12 * items + attributes;
}

/// The size of every true page start of a book in two encodings, and the
/// time to encode and decode each.
Map<String, Object?> _encodings(List<List<PageStart>> sections) {
  var begin = _now();
  final binary = _encodeStarts(sections);
  final binaryEncodeMs = _now() - begin;
  begin = _now();
  final decoded = _decodeStarts(binary);
  final binaryDecodeMs = _now() - begin;
  for (var at = 0; at < sections.length; at++) {
    if (!_sameStarts(sections[at], decoded[at])) {
      throw StateError('The binary starts do not decode to themselves.');
    }
  }
  begin = _now();
  final json = utf8.encode(
    jsonEncode([
      for (final starts in sections)
        [
          for (final start in starts) [start.item, start.line, start.part],
        ],
    ]),
  );
  final jsonEncodeMs = _now() - begin;
  begin = _now();
  jsonDecode(utf8.decode(json));
  final jsonDecodeMs = _now() - begin;
  return {
    'pages': sections.fold<int>(0, (total, starts) => total + starts.length),
    'binaryBytes': binary.length,
    'binaryEncodeMs': binaryEncodeMs,
    'binaryDecodeMs': binaryDecodeMs,
    'jsonBytes': json.length,
    'jsonEncodeMs': jsonEncodeMs,
    'jsonDecodeMs': jsonDecodeMs,
  };
}

/// Each section's count, then each start: the item's distance from the
/// previous start's item, the line (its distance from the previous line
/// in the same item), and the part, all as unsigned variable-length
/// integers.
Uint8List _encodeStarts(List<List<PageStart>> sections) {
  final out = BytesBuilder();
  void put(int value) {
    while (value >= 0x80) {
      out.addByte((value & 0x7f) | 0x80);
      value >>= 7;
    }
    out.addByte(value);
  }

  put(sections.length);
  for (final starts in sections) {
    put(starts.length);
    var item = 0;
    var line = 0;
    for (final start in starts) {
      put(start.item - item);
      put(start.item == item ? start.line - line : start.line);
      put(start.part);
      item = start.item;
      line = start.line;
    }
  }
  return out.takeBytes();
}

List<List<PageStart>> _decodeStarts(Uint8List bytes) {
  var at = 0;
  int take() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  final count = take();
  return [
    for (var section = 0; section < count; section++)
      () {
        final length = take();
        var item = 0;
        var line = 0;
        return [
          for (var index = 0; index < length; index++)
            () {
              final itemStep = take();
              final lineValue = take();
              final part = take();
              line = itemStep == 0 ? line + lineValue : lineValue;
              item += itemStep;
              return PageStart(item, line, part);
            }(),
        ];
      }(),
  ];
}
