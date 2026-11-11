// An on-demand run over the corpus books of tool/reader/epub_corpus.json
// that prepares every section and writes a dump of what prepare made and
// how long it took. It is not part of Bookfin's normal test run, because
// its times come from a shared machine.
//
// In the dev shell, from the repository root, with the books in
// .cache/epub-corpus/books (see corpus_test.dart):
//
//   BOOKFIN_EPUB_CORPUS_PREPARE=before flutter test \
//     test/reader/epub/corpus_prepare_test.dart
//
// The value names the run. It writes .cache/epub-corpus/prepare/<name>.json:
// for each book, its main text size and its shown main text size in each
// page settings value, and for each section and page settings value a hash
// of the prepared section (its DOM, flow items, run styles and faces), or
// the error that prepare threw. For each section at the reader's page, it
// also writes the fastest of three prepares in milliseconds. Two runs
// prepared the same sections when their hashes are equal.
// tool/reader/compare_corpus_prepare.py compares two runs.
//
// For each section of at least 30,000 bytes, it also prepares the parts of
// the section (preparePart) around the places in its middle and near its
// end, in each page settings value. Each part's prepared flow items must
// equal the whole section's, and the first two pages from the part's line
// start must equal those from the whole section, unless the part's line
// search needs the whole section. A section that preparePart gives whole,
// because a part could not hold the place's item, must equal the section
// that prepareSections gives. It writes the outcome of each part, and
// at the reader's page the fastest of three part prepares in milliseconds.
//
// Add --plain-name with a book id to run some books only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/check.dart';
import 'corpus/list.dart';
import 'flow_dump.dart';
import 'helpers.dart' show keys, loadReaderFont;

final _name = Platform.environment['BOOKFIN_EPUB_CORPUS_PREPARE'];

/// The page settings that each section is prepared for: the corpus run's,
/// and night pages that size the main text, which read a book's
/// `prefers-color-scheme` rules and its own type sizes.
const _settings = [
  ...corpusSettings,
  PageSettings(
    width: 412,
    height: 671,
    fontSize: 20,
    night: true,
    sizesMainText: true,
  ),
];

/// How many times each section is prepared at the reader's page for its
/// time. The fastest counts, so that a pause of the shared machine does not.
const _times = 3;

/// The smallest section in bytes whose parts the run checks.
const _partBytes = 30000;

/// The places of the parts that the run checks, as fractions of a
/// section's visible text.
const _partPlaces = [.5, .97];

void main() {
  final name = _name;
  if (name == null || name.isEmpty) {
    test(
      'the corpus prepare',
      () {},
      skip: 'set BOOKFIN_EPUB_CORPUS_PREPARE to a run name to run',
    );
    return;
  }
  setUpAll(loadReaderFont);
  final results = <String, Object>{};
  final file = File('.cache/epub-corpus/prepare/$name.json');
  for (final book in corpusList()) {
    test(book.id, () async {
      final bytes = book.url == null
          ? showcaseBooks()[book.id]!
          : await book.file.readAsBytes();
      final opened = await _open(book, bytes);
      final publication = opened.publication;
      final samples = [
        for (final index in mainTextSamples([
          for (final path in publication.spine)
            publication.textFiles[path]!.length,
        ]))
          opened.source(index),
      ];
      final mainText = measureMainTextSize(samples);
      final hashes = <String, Map<String, String>>{};
      final shown = <String, double>{};
      final times = <String, double>{};
      final parts = <String, Map<String, Map<String, Object>>>{};
      for (final settings in _settings) {
        final key = _settingsKey(settings);
        shown[key] = shownMainTextSize(samples, settings);
        final sections = hashes[key] = {};
        final checked = parts[key] = {};
        for (var index = 0; index < opened.sections; index++) {
          final source = _withMainText(opened.source(index), mainText);
          final timed = identical(settings, _settings.first);
          var fastest = double.infinity;
          String hash;
          PreparedSection? whole;
          try {
            late PreparedSection prepared;
            for (var time = 0; time < (timed ? _times : 1); time++) {
              final watch = Stopwatch()..start();
              prepared = prepareSections([source], settings).single;
              final took = watch.elapsedMicroseconds / 1000;
              if (took < fastest) fastest = took;
            }
            hash = _hash(dumpPrepared(prepared));
            whole = prepared;
          } on Object catch (error) {
            hash = 'error: ${error.runtimeType}: $error';
          }
          // Outside the catch, so that a part that differs fails the test.
          if (whole != null &&
              source.xhtml.length >= _partBytes &&
              whole.dom.visibleLength > 0) {
            checked['$index'] = {
              for (final fraction in _partPlaces)
                '$fraction': _checkPart(
                  source,
                  settings,
                  whole,
                  fraction,
                  times: timed ? _times : 0,
                ),
            };
          }
          sections['$index'] = hash;
          if (timed) times['$index'] = fastest;
        }
      }
      results[book.id] = {
        'mainTextSize': mainText,
        'shownMainTextSize': shown,
        'sections': hashes,
        'prepareMs': times,
        'parts': parts,
      };
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(results));
    }, timeout: Timeout.none);
  }
}

/// Prepares the part of [source] around the place [fraction] of the way
/// through its visible text, and compares it with [whole], the section
/// prepared whole. Returns the outcome: whether its flow items and its
/// first two pages are the whole section's, or whether its line search
/// needs the whole section, with the fastest of [times] part prepares in
/// milliseconds. It fails the test when the part differs.
Map<String, Object> _checkPart(
  SectionSource source,
  PageSettings settings,
  PreparedSection whole,
  double fraction, {
  required int times,
}) {
  EpubPlace? find(DomSection dom) => placeAt(dom, source.index, fraction);
  var fastest = double.infinity;
  for (var time = 0; time < times; time++) {
    final watch = Stopwatch()..start();
    preparePart(source, settings, find);
    final took = watch.elapsedMicroseconds / 1000;
    if (took < fastest) fastest = took;
  }
  final (:place, section: part) = preparePart(source, settings, find);
  final where = '${source.path} at $fraction in ${_settingsKey(settings)}';
  if (part!.whole) {
    expect(
      _hash(dumpPrepared(part)),
      _hash(dumpPrepared(whole)),
      reason: 'the whole section of $where',
    );
    return {'outcome': 'whole', if (times > 0) 'ms': fastest};
  }
  for (var index = 0; index < part.flow.length; index++) {
    final item = part.flow[index];
    if (item is SkippedItem) continue;
    expect(
      dumpItem(item, part.styles),
      dumpItem(whole.flow[index], whole.styles),
      reason: 'flow item $index of $where',
    );
  }
  final search = LineSearch(part, place!)..step(const Duration(days: 1));
  final String outcome;
  if (search.starved) {
    outcome = 'needs the whole section';
  } else {
    final line = search.found!;
    expect(line, lineStart(whole, place), reason: 'the line start of $where');
    expect(
      _pagesFrom(part, line),
      _pagesFrom(whole, line),
      reason: 'the pages of $where',
    );
    outcome = 'same';
  }
  return {
    'outcome': outcome,
    'firstPrepared': part.firstPrepared,
    'items': part.flow.length,
    'reachesEnd': part.reachesEnd,
    if (times > 0) 'ms': fastest,
  };
}

/// The first two pages that a run of [section] from [start] cuts, or
/// fewer when it ends or needs the whole section first.
List<List<Object?>> _pagesFrom(PreparedSection section, PageStart start) {
  final run = LayoutRun(section, from: start);
  while (run.pages.length < 2 && !run.done && !run.starved) {
    run.step(const Duration(days: 1), want: 2 - run.pages.length);
  }
  final shown = keys(run.pages.take(2));
  for (final page in run.pages) {
    page.dispose();
  }
  run.dispose();
  return shown;
}

String _settingsKey(PageSettings settings) =>
    '${settingsName(settings)}'
    '${settings.night ? ' night' : ''}'
    '${settings.sizesMainText ? ' main text' : ''}';

/// [source] with the book's main text size, as the page source gives it.
SectionSource _withMainText(SectionSource source, double mainText) =>
    SectionSource(
      index: source.index,
      path: source.path,
      xhtml: source.xhtml,
      fontPrefix: source.fontPrefix,
      styleSheets: source.styleSheets,
      imageSizes: source.imageSizes,
      language: source.language,
      mainTextSize: mainText,
    );

String _hash(Object? dump) =>
    sha1.convert(utf8.encode(jsonEncode(dump))).toString();

/// Admits [bytes], after it converts a Kindle file as Bookfin does.
Future<CorpusBook> _open(CorpusEntry book, Uint8List bytes) async =>
    book.format == 'azw3'
    ? CorpusBook(
        (await importMobi(
          book.file,
          sha256.convert(bytes).toString(),
        )).publication,
      )
    : CorpusBook.open(bytes);
