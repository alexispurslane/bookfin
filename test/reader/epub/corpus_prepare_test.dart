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
// Add --plain-name with a book id to run some books only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/epub/css.dart' show Length;
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/check.dart';
import 'corpus/list.dart';
import 'helpers.dart';

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
            publication.resources[path]!.length,
        ]))
          opened.source(index),
      ];
      final mainText = measureMainTextSize(samples);
      final hashes = <String, Map<String, String>>{};
      final shown = <String, double>{};
      final times = <String, double>{};
      for (final settings in _settings) {
        final key = _settingsKey(settings);
        shown[key] = shownMainTextSize(samples, settings);
        final sections = hashes[key] = {};
        for (var index = 0; index < opened.sections; index++) {
          final source = _withMainText(opened.source(index), mainText);
          final timed = identical(settings, _settings.first);
          var fastest = double.infinity;
          String hash;
          try {
            late PreparedSection prepared;
            for (var time = 0; time < (timed ? _times : 1); time++) {
              final watch = Stopwatch()..start();
              prepared = prepareSections([source], settings).single;
              final took = watch.elapsedMicroseconds / 1000;
              if (took < fastest) fastest = took;
            }
            hash = _hash(dumpPrepared(prepared));
          } on Object catch (error) {
            hash = 'error: ${error.runtimeType}: $error';
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
      };
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(results));
    }, timeout: Timeout.none);
  }
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

/// Everything that [section] holds, in plain JSON values: its DOM, its
/// flow items, its run styles and its faces. Two prepared sections are the
/// same when their dumps are equal.
Object? dumpPrepared(PreparedSection section) => {
  'index': section.index,
  'dom': [_dumpNode(section.dom.root), section.dom.body.order],
  'visible': section.dom.visibleLength,
  'flow': [for (final item in section.flow) _dumpItem(item)],
  'styles': [for (final style in section.styles) _dumpStyle(style)],
  'fonts': [
    for (final face in section.fonts)
      [face.family, face.path, face.weight, face.italic],
  ],
};

Object? _dumpNode(DomNode node) => switch (node) {
  DomText() => [node.order, node.textIndex, node.visibleBefore, node.text],
  DomElement() => [
    node.order,
    node.elementIndex,
    node.name,
    [
      for (final key in node.attributes.keys.toList()..sort())
        [key, node.attributes[key]],
    ],
    [for (final child in node.children) _dumpNode(child)],
    [for (final element in node.elements) element.order],
  ],
};

Object? _dumpItem(FlowItem item) => switch (item) {
  BlockStart() => [
    'start',
    item.node,
    _dumpPlacement(item.placement),
    '${item.marginTop}',
    '${item.marginBottom}',
    [for (final side in item.padding) '$side'],
    [for (final side in item.border) '$side'],
    [item.marker?.text, item.marker?.style],
    item.shrinkToFit,
    item.avoidBreakBefore,
    item.avoidBreakAfter,
    item.avoidBreakInside,
  ],
  BlockEnd() => ['end'],
  ParagraphItem() => [
    'paragraph',
    _dumpText(item.text),
    _dumpLength(item.indent),
    item.orphans,
    item.widows,
  ],
  ImageItem() => [
    'image',
    item.node,
    _dumpImage(item.image),
    _dumpSizing(item.sizing),
    '${item.marginLeft}',
    item.centered,
    '${item.marginTop}',
    '${item.marginBottom}',
  ],
  TableItem() => [
    'table',
    [
      for (final row in item.rows)
        [
          for (final cell in row)
            [
              [for (final each in cell.flow) _dumpItem(each)],
              cell.colspan,
              [for (final side in cell.padding) '$side'],
              [for (final side in cell.border) '$side'],
              '${cell.align}',
            ],
        ],
    ],
    '${item.width}',
    ['${item.spacing.$1}', '${item.spacing.$2}'],
  ],
};

Object? _dumpPlacement(BoxPlacement placement) => [
  '${placement.marginLeft}',
  '${placement.marginRight}',
  '${placement.horizontal}',
  '${placement.used}',
  placement.autoLeft,
  placement.autoRight,
  placement.parentAlign?.name,
];

Object? _dumpText(StyledText text) => [
  text.style,
  text.align.name,
  [for (final run in text.runs) _dumpRun(run)],
];

Object? _dumpRun(InlineRun run) => switch (run) {
  TextRun() => ['text', run.text, run.style, run.node, run.offsets.toList()],
  BreakRun() => ['break', run.node],
  ImageRun() => [
    'image',
    run.node,
    _dumpImage(run.image),
    _dumpSizing(run.sizing),
  ],
  RaisedRun() => ['raised', run.node, _dumpText(run.text), '${run.shift}'],
};

Object? _dumpImage(DrawnImage image) => [
  image.path,
  '${image.invert}',
  image.alt,
];

Object? _dumpSizing(ImageSizing sizing) => [
  '${sizing.intrinsicWidth}',
  '${sizing.intrinsicHeight}',
  _dumpLength(sizing.width),
  _dumpLength(sizing.height),
  '${sizing.attributeWidth}',
  '${sizing.attributeHeight}',
  _dumpLength(sizing.maxWidth),
  '${sizing.maxHeight}',
];

Object? _dumpLength(Length length) => ['${length.value}', length.unit.name];

Object? _dumpStyle(RunStyle style) => [
  style.family,
  '${style.size}',
  style.weight,
  style.italic,
  '${style.letterSpacing}',
  '${style.wordSpacing}',
  '${style.lineHeight}',
  style.underline,
  style.lineThrough,
  style.smallCaps,
  style.oldstyleFigures,
];

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
