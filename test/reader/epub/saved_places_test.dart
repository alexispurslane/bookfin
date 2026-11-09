// The places that the WebView reader saved with epub.js, held against the
// native renderer. epub.js recorded them in headless Chromium (ticket
// tc-pshi): each page start at 20 and 23 pixels, each contents entry and
// the hits of three search phrases. A person who saved one of these places
// must find it again after epub.js is gone.
//
// The showcase books of tool/showcase_media.dart run always. The
// downloaded books run on demand, when files with the recorded SHA-256 are
// in .cache/epub-trial/books:
//
//   BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/saved_places_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'epubjs_fixtures.dart';
import 'helpers.dart';

void main() {
  setUpAll(loadReaderFont);

  group('the showcase books', () {
    final books = fixture('epubjs-places.json')['books'] as Map;
    final made = showcaseBooks();
    for (final MapEntry(key: name as String, value: record as Map)
        in books.entries) {
      final publication = Publication.admit(made[name]!);

      test('$name is still the book whose places epub.js saved', () {
        expect(publication.identity, record['identity']);
      });

      _placeTests(name, () => publication, record);
    }
  });

  group('the downloaded books', () {
    if (!trialRun) {
      test(
        'open the places that epub.js saved',
        () {},
        skip: 'set BOOKFIN_EPUB_TRIAL=1 to run',
      );
      return;
    }
    final books = fixture('epubjs-corpus-places.json')['books'] as Map;
    final files = downloadedBooks();
    for (final MapEntry(key: digest, value: record as Map) in books.entries) {
      final bytes = files[digest];
      final name = record['name'] as String;
      if (bytes == null) {
        test(
          '$name opens the places that epub.js saved',
          () {},
          skip: 'the book with SHA-256 $digest is not downloaded',
        );
        continue;
      }
      late final publication = Publication.admit(asRecorded(bytes));
      _placeTests(name, () => publication, record);
      _hyphenatedPlaceTests(name, () => Publication.admit(bytes), record);
    }
  });
}

/// The tests of the places in [record], which epub.js saved for the book
/// [name], against [publication].
void _placeTests(
  String name,
  Publication Function() publication,
  Map<dynamic, dynamic> record,
) {
  final sections = (record['sections'] as Map).cast<String, Map>();

  test('every page start that epub.js saved in $name opens on a page whose '
      'first line holds its quote', () async {
    final book = _Book(publication());
    for (final size in recordedSizes) {
      final source = immediateSource(book.publication)..settings = pageAt(size);
      var count = 0;
      try {
        for (final MapEntry(key: key, value: section) in sections.entries) {
          final index = int.parse(key);
          final dom = (await source.section(index)).dom;
          for (final page in (section['$size'] as List).cast<Map>()) {
            final cfi = page['cfi'] as String;
            final where = '$name $size px section $index $cfi';
            final place = placeOf(dom, index, cfi);
            expect(place, isNotNull, reason: '$where names no place');
            expect(
              quoteMatches(dom, place!, page['quote'] as String),
              isTrue,
              reason: '$where: the text there is not the saved quote',
            );
            final shown = await source.pageAt(place, anchored: true);
            _expectFirstLineHolds(shown, dom, place, where);
            count++;
          }
        }
      } finally {
        source.dispose();
      }
      _report(name, '$size px page starts opened', count, count);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test(
    'a page of $name that starts on the character where an epub.js page '
    'started saves that character, and the saved place opens the page',
    () async {
      final book = _Book(publication());
      for (final size in recordedSizes) {
        final source = immediateSource(book.publication)
          ..settings = pageAt(size);
        var starts = 0;
        var same = 0;
        var sameCfi = 0;
        try {
          for (final MapEntry(key: key, value: section) in sections.entries) {
            final index = int.parse(key);
            final resource = section['resource'] as String;
            final layout = layoutSection(await source.section(index));
            final dom = layout.section.dom;
            final native = {
              for (final (number, page) in layout.pages.indexed)
                if (page.startPlace case final start?
                    when dom.textAt(start) != null)
                  page.startVisible: (number, page),
            };
            for (final saved in (section['$size'] as List).cast<Map>()) {
              if (saved['start'] == null) continue;
              starts++;
              final (number, page) = native[saved['start']] ?? (-1, null);
              if (page == null) continue;
              same++;
              final start = page.startPlace!;
              final where =
                  '$name $size px section $index page ${saved['start']}';
              final location = pageLocation(
                book.spine(index),
                resource,
                dom,
                start,
                page.endPlace ?? start,
                book.chapter(dom, start, resource),
              );
              final place = placeOf(dom, index, location.cfi)!;
              expect(dom.visibleBefore(place), saved['start'], reason: where);
              expect(location.quote.trimLeft(), location.quote, reason: where);
              expect(layout.pageAt(place), number, reason: where);
              if (location.cfi == saved['cfi']) sameCfi++;
            }
            layout.dispose();
          }
        } finally {
          source.dispose();
        }
        _report(name, '$size px pages that start where epub.js', same, starts);
        _report(name, '$size px of them saved as epub.js saved', sameCfi, same);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('every contents entry of $name opens where epub.js opened it, on a page '
      'whose first line holds it', () async {
    final book = _Book(publication());
    final source = immediateSource(book.publication)..settings = readerPage;
    final misplaced = <String>[];
    var count = 0;
    try {
      for (final entry in (record['contents'] as List).cast<Map>()) {
        count++;
        final where = '$name contents entry ${entry['href']}';
        final target = book.target(entry['href'] as String);
        if (entry['error'] != null) {
          // epub.js refused the entry; Bookfin opens nothing for it.
          if (target case (final index, final fragment)) {
            final dom = (await source.section(index)).dom;
            expect(destination(dom, index, fragment), isNull, reason: where);
          }
          continue;
        }
        final (index, fragment) = target!;
        final resource = book.publication.spine[index];
        expect(resource, entry['resource'], reason: where);
        final dom = (await source.section(index)).dom;
        final place = destination(dom, index, fragment)!;
        final location = hitLocation(
          book.spine(index),
          resource,
          dom,
          place,
          book.chapter(dom, place, resource),
        );
        expect(location.toJson(), {
          'cfi': entry['cfi'],
          'resource': resource,
          'quote': entry['quote'],
        }, reason: where);
        final shown = await source.pageAt(place, anchored: true);
        if (_notOnFirstLine(shown, dom, place) case final why?) {
          misplaced.add('$where $why');
        }
      }
    } finally {
      source.dispose();
    }
    _report(
      name,
      'contents entries on the first line',
      count - misplaced.length,
      count,
    );
    expect(misplaced, isEmpty);
  });

  test('every search hit that epub.js found in $name opens on a page that '
      'shows it, and saves the place that epub.js saved', () async {
    final book = _Book(publication());
    final source = immediateSource(book.publication)..settings = readerPage;
    var count = 0;
    try {
      for (final search in (record['search'] as List).cast<Map>()) {
        for (final hit in (search['hits'] as List).cast<Map>()) {
          final resource = hit['resource'] as String;
          final index = book.publication.spine.indexOf(resource);
          final cfi = hit['cfi'] as String;
          final where = '$name "${search['query']}" $cfi';
          final dom = (await source.section(index)).dom;
          final place = placeOf(dom, index, cfi);
          expect(place, isNotNull, reason: '$where names no place');
          final location = hitLocation(
            book.spine(index),
            resource,
            dom,
            place!,
            book.chapter(dom, place, resource),
          );
          expect(location.toJson(), {
            'cfi': cfi,
            'resource': resource,
            'quote': hit['quote'],
          }, reason: where);
          final shown = await source.pageAt(place, anchored: true);
          expect(_notShown(shown, dom, place), isNull, reason: where);
          count++;
        }
      }
    } finally {
      source.dispose();
    }
    _report(name, 'search hits opened', count, count);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// The tests of the page starts in [record], which epub.js saved for the
/// book [name] without hyphenation, against [publication] as the reader
/// shows it, hyphenated where its style sheets ask. Its pages are cut
/// elsewhere, so a saved page start can fall inside a page.
void _hyphenatedPlaceTests(
  String name,
  Publication Function() publication,
  Map<dynamic, dynamic> record,
) {
  final sections = (record['sections'] as Map).cast<String, Map>();

  test('every page start that epub.js saved in $name keeps its quote and '
      'opens on a page that shows it when the book hyphenates', () async {
    final book = _Book(publication());
    for (final size in recordedSizes) {
      final source = immediateSource(book.publication)..settings = pageAt(size);
      var count = 0;
      try {
        for (final MapEntry(key: key, value: section) in sections.entries) {
          final index = int.parse(key);
          final dom = (await source.section(index)).dom;
          for (final page in (section['$size'] as List).cast<Map>()) {
            final cfi = page['cfi'] as String;
            final where = '$name $size px section $index $cfi';
            final place = placeOf(dom, index, cfi);
            expect(place, isNotNull, reason: '$where names no place');
            expect(
              quoteMatches(dom, place!, page['quote'] as String),
              isTrue,
              reason: '$where: the text there is not the saved quote',
            );
            final shown = await source.pageAt(place, anchored: true);
            expect(_notShown(shown, dom, place), isNull, reason: where);
            count++;
          }
        }
      } finally {
        source.dispose();
      }
      _report(name, '$size px page starts shown, hyphenated', count, count);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Expects that the first line of [page] holds [place], a place in [dom]:
/// its visible character is at or after the line's first one, and before
/// the next line's first one.
void _expectFirstLineHolds(
  LaidPage page,
  DomSection dom,
  EpubPlace place,
  String where,
) {
  final lines = page.lineStarts;
  final visible = dom.visibleBefore(place);
  expect(lines, isNotEmpty, reason: '$where opens a page without text');
  expect(
    visible,
    inInclusiveRange(
      lines.first,
      (lines.length > 1 ? lines[1] : page.endVisible) - 1,
    ),
    reason:
        '$where opens a page whose first line runs from character '
        '${lines.first} to ${lines.length > 1 ? lines[1] : page.endVisible}',
  );
}

/// Why [page] does not show [place], a place in [dom], or null when it
/// shows it: its visible character is on the page. A section's first page
/// shows the section from its start, even text before its first line that
/// the reader hides, such as the heading of a Standard Ebooks imprint. A
/// page without text, such as a title page image, shows only the place at
/// its start.
///
/// The design asks this of search hits ("Testing, Behavior tests").
String? _notShown(LaidPage page, DomSection dom, EpubPlace place) {
  final visible = dom.visibleBefore(place);
  final from = page.start == const PageStart(0, 0) ? 0 : page.startVisible;
  final to = page.lineStarts.isEmpty ? page.endVisible : page.endVisible - 1;
  if (visible >= from && visible <= to) return null;
  return 'is character $visible, on a page that shows characters $from to '
      '$to';
}

/// Why the first line of [page] does not hold [place], a place in [dom], or
/// null when it holds it: its visible character is at or after the line's
/// first one, and before the next line's first one. On a section's first
/// page, the first line also holds the text before it that the reader
/// hides, as [_notShown] allows. A page without text holds only the place
/// at its start.
///
/// A contents entry in a node of only white space counts as its next
/// visible character (t9-ousp).
String? _notOnFirstLine(LaidPage page, DomSection dom, EpubPlace place) {
  final visible = dom.visibleBefore(place);
  final lines = page.lineStarts;
  final from = lines.isEmpty || page.start == const PageStart(0, 0)
      ? page.start == const PageStart(0, 0)
            ? 0
            : page.startVisible
      : lines.first;
  final to = lines.length > 1
      ? lines[1] - 1
      : lines.isEmpty
      ? page.endVisible
      : page.endVisible - 1;
  if (visible >= from && visible <= to) return null;
  return 'is character $visible, on a page whose first line holds characters '
      '$from to $to';
}

/// Writes how many of [total] places of [book] passed a check, so that an
/// on-demand run can be read off the test output.
void _report(String book, String what, int passed, int total) =>
    stdout.writeln('$book: $what: $passed of $total');

/// The publication of a recorded book, with what its places need.
class _Book {
  _Book(this.publication)
    : _opf = utf8.decode(publication.resources[publication.packagePath]!);

  final Publication publication;
  final String _opf;

  /// The spine step of the CFIs of section [index].
  String spine(int index) => spineStep(_opf, index);

  /// The chapter label of [place] in [dom], the section at [resource].
  String chapter(DomSection dom, EpubPlace place, String resource) =>
      chapterTitle(
        dom,
        place,
        publication.contents,
        publication.packagePath,
        resource,
      );

  /// The spine index and decoded fragment that [href], relative to the
  /// package document as reader.js `resolveDestination` reads it, points
  /// at, or null when it points outside the spine.
  (int, String?)? target(String href) {
    final uri = Uri(
      scheme: 'https',
      host: 'book',
      path: '/${publication.packagePath}',
    ).resolve(href);
    final index = publication.spine.indexOf(uri.pathSegments.join('/'));
    if (index < 0) return null;
    return (
      index,
      uri.fragment.isEmpty ? null : Uri.decodeComponent(uri.fragment),
    );
  }
}
