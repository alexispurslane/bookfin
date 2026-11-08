// Tool code: the on-demand fidelity comparison of the renderer with
// epub.js. It is not part of Bookfin's normal test run.
//
// It runs in these steps (see docs/research/native-epub-fidelity.md):
//
// 1. BOOKFIN_EPUB_TRIAL_PLAN=1 flutter test test/reader/epub/trial/fidelity_test.dart
//    writes .cache/epub-trial/fidelity-20/plan.json: the sections to compare,
//    the renderer's CFI of each page start, the pages to draw and the search
//    phrases. It covers the downloaded books in .cache/epub-trial/books and
//    the showcase books of tool/showcase_media.dart. It also writes each
//    book's admitted publication, with the book's own style sheets, into
//    .cache/epub-trial/admitted for Chromium.
// 2. node packages/flutter_epub_viewer/engine/trial/compare.cjs
//    .cache/epub-trial/fidelity-20/plan.json .cache/epub-trial/admitted
//    .cache/epub-trial/fidelity-20/chromium
//    renders the same sections with epub.js in Chromium.
// 3. BOOKFIN_EPUB_TRIAL_FIDELITY=1 flutter test test/reader/epub/trial/fidelity_test.dart
//    compares both and writes .cache/epub-trial/results/fidelity-20.json
//    and side-by-side images in .cache/epub-trial/fidelity-20/side-by-side.
//
// BOOKFIN_EPUB_TRIAL_FONT_SIZE=23 runs the same steps at 23 pixels, in
// .cache/epub-trial/fidelity-23.
//
// After steps 1 and 2 at both sizes,
// BOOKFIN_EPUB_TRIAL_FIXTURES=1 flutter test test/reader/epub/trial/fidelity_test.dart
// writes what epub.js measured and saved into test/reader/epub/fixtures:
// epubjs-places.json for the showcase books, and chromium-layout.json and
// epubjs-corpus-places.json for the downloaded books.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers.dart';
import 'book.dart';

final _plan = Platform.environment['BOOKFIN_EPUB_TRIAL_PLAN'] == '1';
final _compare = Platform.environment['BOOKFIN_EPUB_TRIAL_FIDELITY'] == '1';
final _fixtures = Platform.environment['BOOKFIN_EPUB_TRIAL_FIXTURES'] == '1';
// BOOKFIN_EPUB_TRIAL_FONT_SIZE picks another text size than the reader's
// default 20 pixels. Each size has its own directory.
final _fontSize =
    double.tryParse(
      Platform.environment['BOOKFIN_EPUB_TRIAL_FONT_SIZE'] ?? '',
    ) ??
    20;
final _directory = '.cache/epub-trial/fidelity-${_fontSize.round()}';
const _cfiPages = 40;

/// The phrases that each book is searched for: a word that also comes
/// capitalized, two words that the text can break between lines, and a
/// rare word.
const _phrases = ['morning', 'the door', 'lantern'];

/// The books to compare, by trial name: each downloaded book with the
/// SHA-256 of its file, and each showcase book without one.
Map<String, (Uint8List, String?)> _books() => {
  for (final file in trialBooks())
    if (!bookName(file).startsWith('showcase-'))
      bookName(file): (
        file.readAsBytesSync(),
        sha256.convert(file.readAsBytesSync()).toString(),
      ),
  for (final MapEntry(:key, :value) in showcaseBooks().entries)
    key: (value, null),
};
final _settings = PageSettings(
  width: readerPage.width,
  height: readerPage.height,
  fontSize: _fontSize,
  night: false,
);

/// The sections of [book] to compare: its two longest, and the first one
/// with an image and some text.
List<int> _chosen(TrialBook book) {
  final lengths = <int, int>{};
  int? illustrated;
  for (var index = 0; index < book.sections; index++) {
    final xhtml = book.source(index).xhtml;
    final dom = DomSection.parse(xhtml);
    lengths[index] = dom.visibleLength;
    if (illustrated == null &&
        dom.visibleLength > 300 &&
        xhtml.contains('<img')) {
      illustrated = index;
    }
  }
  final longest = lengths.keys.toList()
    ..sort((a, b) => lengths[b]!.compareTo(lengths[a]!));
  return {...longest.take(2), ?illustrated}.toList()..sort();
}

ChapterLayout _layout(TrialBook book, int index) =>
    layoutSection(prepareSections([book.source(index)], _settings).single);

/// Writes the admitted publication of [bytes] into [root], with the book's
/// own style sheets, because the sanitizer empties every Standard Ebooks
/// sheet. bookfin-trial.txt lists the package path and the spine.
void _unpack(Uint8List bytes, Directory root) {
  final publication = Publication.admit(bytes);
  final archive = ZipDecoder().decodeBytes(bytes);
  if (root.existsSync()) root.deleteSync(recursive: true);
  for (final entry in publication.resources.entries) {
    final original = publication.mediaTypes[entry.key] == 'text/css'
        ? archive.findFile(entry.key)?.readBytes()
        : null;
    File('${root.path}/${entry.key}')
      ..createSync(recursive: true)
      ..writeAsBytesSync(original ?? Uint8List.fromList(entry.value));
  }
  File('${root.path}/bookfin-trial.txt').writeAsStringSync(
    [publication.packagePath, ...publication.spine].join('\n'),
  );
}

void main() {
  setUpAll(loadReaderFont);

  test(
    'writes the fidelity plan',
    () async {
      final plan = <Object>[];
      for (final MapEntry(key: name, value: (bytes, digest))
          in _books().entries) {
        _unpack(bytes, Directory('.cache/epub-trial/admitted/$name'));
        final book = TrialBook.open(bytes);
        final sections = <Object>[];
        // A showcase book is short, so every section and page counts.
        final showcase = digest == null;
        for (final index
            in showcase
                ? List.generate(book.sections, (index) => index)
                : _chosen(book)) {
          final chapter = _layout(book, index);
          final dom = chapter.section.dom;
          final pages = chapter.pages.length;
          sections.add({
            'index': index,
            'resource': book.publication.spine[index],
            'cfiPages': showcase ? pages + 10 : _cfiPages,
            'screenshots': {0, 1, pages ~/ 2}.where((p) => p < pages).toList(),
            'nativeCfis': [
              for (final page in chapter.pages.take(_cfiPages))
                if (page.startPlace case final start?)
                  cfiOf(book.spine(index), dom, wordStart(dom, start)),
            ],
          });
        }
        plan.add({
          'book': name,
          'sha256': ?digest,
          'identity': book.publication.identity,
          'packagePath': book.publication.packagePath,
          'fontSize': _fontSize,
          'phrases': _phrases,
          'sections': sections,
        });
      }
      Directory(_directory).createSync(recursive: true);
      File('$_directory/plan.json').writeAsStringSync(jsonEncode(plan));
    },
    skip: !_plan,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'compares the renderer with epub.js',
    () async {
      final chromium = _chromium(_directory)['books'] as List<dynamic>;
      final books = _books();
      final report = <Object>[];
      Directory('$_directory/side-by-side').createSync(recursive: true);
      for (final entry in chromium.cast<Map<String, dynamic>>()) {
        final book = TrialBook.open(books[entry['book']]!.$1);
        for (final section in (entry['sections'] as List).cast<Map>()) {
          final index = section['index'] as int;
          final chapter = _layout(book, index);
          final dom = chapter.section.dom;
          final theirs = [
            for (final page in section['lines'] as List)
              (page as List).cast<int>(),
          ];
          final ours = [for (final page in chapter.pages) page.lineStarts];
          final theirLines = {for (final page in theirs) ...page};
          final ourLines = {for (final page in ours) ...page};
          final theirStarts = [
            for (final page in theirs)
              if (page.isNotEmpty) page.first,
          ];
          final ourStarts = {
            for (final page in ours)
              if (page.isNotEmpty) page.first,
          };
          var samePageLines = 0;
          var comparedPages = 0;
          for (
            var page = 0;
            page < math.min(ours.length, theirs.length);
            page++
          ) {
            if (theirs[page].isEmpty) continue;
            comparedPages++;
            if (_sameList(ours[page], theirs[page])) samePageLines++;
          }
          // The CFI of each page start, as epub.js wrote it.
          final cfis = (section['cfis'] as List).cast<String>();
          var sameCfi = 0;
          var opensSamePage = 0;
          var opensSameText = 0;
          for (var page = 0; page < cfis.length; page++) {
            final start = page < chapter.pages.length
                ? chapter.pages[page].startPlace
                : null;
            if (start != null &&
                cfiOf(book.spine(index), dom, wordStart(dom, start)) ==
                    cfis[page]) {
              sameCfi++;
            }
            final place = placeOf(dom, index, cfis[page]);
            if (place == null) continue;
            if (chapter.pageAt(place) == page) opensSamePage++;
            // Where the place lands: its visible character is on the page
            // that the renderer shows for it.
            final visible = dom.visibleBefore(place);
            final shown = chapter.pages[chapter.pageAt(place)];
            final next = chapter.pageAt(place) + 1 < chapter.pages.length
                ? chapter.pages[chapter.pageAt(place) + 1].startVisible
                : dom.visibleLength + 1;
            if (visible >= shown.startVisible && visible < next) {
              opensSameText++;
            }
          }
          // The places that the renderer wrote, read by epub.js.
          var quoteMatches = 0;
          var progressMatches = 0;
          final resolved = (section['resolved'] as List).cast<Map>();
          for (final saved in resolved) {
            final place = placeOf(dom, index, saved['cfi'] as String);
            if (place == null || saved['error'] != null) continue;
            if (saved['quote'] == quoteAt(dom, place)) quoteMatches++;
            if ((saved['progress'] as num).toDouble() ==
                progressAt(dom, place)) {
              progressMatches++;
            }
          }
          final images = (section['images'] as Map).cast<String, String>();
          for (final MapEntry(key: page, value: name) in images.entries) {
            await _sideBySide(book, chapter, int.parse(page), name);
          }
          report.add({
            'book': entry['book'],
            'section': index,
            'characters': dom.visibleLength,
            'pagesEpubjs': section['pageCount'],
            'pagesTrial': chapter.pages.length,
            'linesEpubjs': theirLines.length,
            'linesTrial': ourLines.length,
            'sameLineStarts': theirLines.intersection(ourLines).length,
            'pageStartsEpubjs': theirStarts.length,
            'samePageStarts': theirStarts.where(ourStarts.contains).length,
            'pagesWithSameLines': samePageLines,
            'comparedPages': comparedPages,
            'epubjsCfis': cfis.length,
            'sameCfiStrings': sameCfi,
            'epubjsCfiOpensSamePage': opensSamePage,
            'epubjsCfiOpensItsText': opensSameText,
            'trialCfis': resolved.length,
            'trialCfiQuoteMatches': quoteMatches,
            'trialCfiProgressMatches': progressMatches,
            'firstDifferentPage': _firstDifference(
              [for (final page in theirs) page.firstOrNull],
              [for (final page in ours) page.firstOrNull],
            ),
            'epubjsShowMs': section['showMs'],
            'epubjsShowAgainMs': section['showAgainMs'],
            'epubjsPreviewMs': section['previewMs'],
          });
        }
      }
      Directory('.cache/epub-trial/results').createSync(recursive: true);
      File('.cache/epub-trial/results/fidelity-${_fontSize.round()}.json')
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    },
    skip: !_compare,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('writes what epub.js measured and saved as fixtures', () {
    final runs = {
      for (final size in [20, 23])
        size: _chromium('.cache/epub-trial/fidelity-$size'),
    };
    final plans = {
      for (final size in runs.keys)
        size: {
          for (final entry in jsonDecode(
            File('.cache/epub-trial/fidelity-$size/plan.json')
                .readAsStringSync(),
          ) as List)
            (entry as Map)['book'] as String: entry,
        },
    };
    final chromium = {for (final run in runs.values) run['chromium']};
    if (chromium.length != 1) {
      throw StateError('The two runs used different browsers: $chromium');
    }
    final header = {
      'recorded': DateTime.now().toUtc().toIso8601String().substring(0, 10),
      'chromium': chromium.single,
      'page': {'width': readerPage.width, 'height': readerPage.height},
    };
    final showcase = <String, Object>{};
    final corpus = <String, Object>{};
    final layout = <String, Object>{};
    for (final entry in (runs[20]!['books'] as List).cast<Map>()) {
      final name = entry['book'] as String;
      final plan = plans[20]![name]!;
      final digest = plan['sha256'] as String?;
      final sections = <String, Map<String, Object?>>{};
      final lines = <String, Map<String, Object>>{};
      for (final MapEntry(key: size, value: run) in runs.entries) {
        final measured = (run['books'] as List).cast<Map>().singleWhere(
          (book) => book['book'] == name,
        );
        final planned = {
          for (final section in plans[size]![name]!['sections'] as List)
            (section as Map)['index']: section['resource'],
        };
        for (final section in (measured['sections'] as List).cast<Map>()) {
          final index = section['index'].toString();
          final pages = (section['saved'] as List).cast<Map>();
          for (final (number, page) in pages.indexed) {
            if (page['page'] != number + 1) {
              throw StateError(
                '$name $index: page ${number + 1} reports '
                'page ${page['page']}',
              );
            }
          }
          (sections[index] ??= {
            'resource': planned[section['index']],
          })['$size'] = [
            for (final page in pages)
              {
                'start': page['start'],
                'cfi': page['cfi'],
                'quote': page['quote'],
                'progress': page['progress'],
              },
          ];
          (lines[index] ??= {})['$size'] = section['lines'] as List;
        }
      }
      final record = {
        'name': name,
        if (digest == null) 'identity': plan['identity'],
        'packagePath': plan['packagePath'],
        'sections': sections,
        'contents': entry['contents'],
        'search': entry['search'],
      };
      if (digest == null) {
        showcase[name] = record;
      } else {
        corpus[digest] = record;
        layout[digest] = {'name': name, 'sections': lines};
      }
    }
    final fixtures = Directory('test/reader/epub/fixtures');
    File('${fixtures.path}/epubjs-places.json')
        .writeAsStringSync(_encode({...header, 'books': showcase}));
    File('${fixtures.path}/epubjs-corpus-places.json')
        .writeAsStringSync(_encode({...header, 'books': corpus}));
    File('${fixtures.path}/chromium-layout.json')
        .writeAsStringSync(_encode({...header, 'books': layout}));
  }, skip: !_fixtures);
}

/// What compare.cjs wrote into [directory]/chromium.
Map<String, dynamic> _chromium(String directory) =>
    jsonDecode(File('$directory/chromium/chromium.json').readAsStringSync())
        as Map<String, dynamic>;

/// [value] as JSON with one record or one list of numbers per line, so
/// that a diff of a fixture shows which places moved.
String _encode(Object? value, [String indent = '']) {
  final inner = '$indent ';
  bool flat(Object? item) =>
      item is! Map && item is! List ||
      item is List && item.every((element) => element is num) ||
      item is Map &&
          item.values.every((element) => element is! Map && element is! List);
  if (flat(value)) return jsonEncode(value);
  if (value is List) {
    return '[\n${[for (final item in value) '$inner${_encode(item, inner)}'].join(',\n')}\n$indent]';
  }
  final map = value! as Map;
  return '{\n${[for (final MapEntry(:key, value: item) in map.entries) '$inner${jsonEncode(key)}: ${_encode(item, inner)}'].join(',\n')}\n$indent}';
}

/// The first page whose start differs, with both starts and the page
/// starts around it, or null when all agree.
Map<String, Object?>? _firstDifference(List<int?> theirs, List<int?> ours) {
  for (var page = 0; page < math.max(theirs.length, ours.length); page++) {
    final a = page < theirs.length ? theirs[page] : null;
    final b = page < ours.length ? ours[page] : null;
    if (a != b) {
      return {
        'page': page,
        'epubjs': theirs.sublist(
          math.max(0, page - 1),
          math.min(theirs.length, page + 3),
        ),
        'trial': ours.sublist(
          math.max(0, page - 1),
          math.min(ours.length, page + 3),
        ),
      };
    }
  }
  return null;
}

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Writes epub.js's page [name] and the renderer's page [page] of
/// [chapter], a section of [book], side by side, both at twice the layout
/// size.
Future<void> _sideBySide(
  TrialBook book,
  ChapterLayout chapter,
  int page,
  String name,
) async {
  if (page >= chapter.pages.length) return;
  const scale = 2.0;
  final images = await decodeImages(
    [chapter.pages[page]],
    book.resource,
    scale: scale,
  );
  final picture = drawPage(chapter.pages[page], images);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..scale(scale)
    ..drawPicture(picture);
  final scaled = recorder.endRecording();
  final width = (_settings.width * scale).round();
  final height = (_settings.height * scale).round();
  final rendered = await scaled.toImage(width, height);
  final bytes = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  scaled.dispose();
  picture.dispose();
  for (final image in images.values) {
    image.dispose();
  }
  final ours = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes!.buffer,
    numChannels: 4,
  );
  final theirs = img.decodePng(
    File('$_directory/chromium/$name').readAsBytesSync(),
  )!;
  const band = 48;
  const gap = 24;
  final canvas = img.Image(width: width * 2 + gap, height: height + band)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, theirs, dstX: 0, dstY: band);
  img.compositeImage(canvas, ours, dstX: width + gap, dstY: band);
  final black = img.ColorRgb8(0, 0, 0);
  img.drawString(
    canvas,
    'epub.js in Chromium',
    font: img.arial24,
    x: 12,
    y: 10,
    color: black,
  );
  img.drawString(
    canvas,
    'Flutter renderer',
    font: img.arial24,
    x: width + gap + 12,
    y: 10,
    color: black,
  );
  File('$_directory/side-by-side/${name.replaceAll('.png', '.jpg')}')
      .writeAsBytesSync(img.encodeJpg(canvas, quality: 82));
}
