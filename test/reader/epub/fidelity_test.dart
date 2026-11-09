// The native layout held against what epub.js laid out in Chromium: the
// line starts and page starts of each compared section of the downloaded
// books, at 20 and 23 pixels, in fixtures/chromium-layout.json (ticket
// tc-pshi). It needs no Chromium, so it outlives epub.js. It runs on
// demand, when files with the recorded SHA-256 are in
// .cache/epub-trial/books:
//
//   BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/fidelity_test.dart
//
// It writes the numbers to .cache/epub-trial/results/fidelity-native.json.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'epubjs_fixtures.dart';
import 'helpers.dart';

void main() {
  setUpAll(loadReaderFont);

  test(
    'body text breaks lines and pages where epub.js broke them',
    () async {
      final books = fixture('chromium-layout.json')['books'] as Map;
      final files = downloadedBooks();
      final totals = <(int, String), _Agreement>{};
      final report = <Object>[];
      for (final MapEntry(key: digest, value: record as Map) in books.entries) {
        final bytes = files[digest];
        final name = record['name'] as String;
        if (bytes == null) {
          stdout.writeln('$name is not downloaded; skipped');
          continue;
        }
        final publication = Publication.admit(asRecorded(bytes));
        for (final size in recordedSizes) {
          final source = immediateSource(publication)..settings = pageAt(size);
          try {
            final sections = (record['sections'] as Map).cast<String, Map>();
            for (final MapEntry(key: key, value: section) in sections.entries) {
              final index = int.parse(key);
              final layout = layoutSection(await source.section(index));
              final ours = [for (final page in layout.pages) page.lineStarts];
              layout.dispose();
              final theirs = [
                for (final page in section['$size'] as List)
                  (page as List).cast<int>(),
              ];
              final agreement = _Agreement.of(ours, theirs);
              final group = _group(name, publication.spine[index]);
              (totals[(size, group)] ??= _Agreement()).add(agreement);
              report.add({
                'book': name,
                'section': index,
                'size': size,
                'group': group,
                ...agreement.toJson(),
              });
            }
          } finally {
            source.dispose();
          }
        }
      }
      if (totals.isEmpty) {
        markTestSkipped('No book of chromium-layout.json is downloaded.');
        return;
      }
      for (final MapEntry(key: (size, group), value: total) in totals.entries) {
        stdout.writeln('$size px $group: $total');
      }
      Directory('.cache/epub-trial/results').createSync(recursive: true);
      File('.cache/epub-trial/results/fidelity-native.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'totals': [
            for (final MapEntry(key: (size, group), value: total)
                in totals.entries)
              {'size': size, 'group': group, ...total.toJson()},
          ],
          'sections': report,
        }),
      );
      final body = totals[(20, _body)]!;
      expect(body.lineShare, greaterThanOrEqualTo(0.999), reason: '$body');
      expect(body.pageShare, greaterThanOrEqualTo(0.98), reason: '$body');
    },
    skip: trialRun ? false : 'set BOOKFIN_EPUB_TRIAL=1 to run',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

const _body = 'body text';

/// The group of the section at [resource] of the book [name]. The groups
/// are those of the trial (docs/research/native-epub.md, "Fidelity"), and
/// only body text has a target. In the imprint, epub.js counts empty
/// columns as pages. A Christmas Carol has its contents in tables and a
/// license that sets `all: initial`, so Chromium draws it in Times.
String _group(String name, String resource) {
  if (resource.endsWith('/imprint.xhtml')) return 'Standard Ebooks imprint';
  if (name == 'pg-46-christmas-carol') {
    return 'A Christmas Carol (contents table, Gutenberg license)';
  }
  return _body;
}

/// How far the native line and page starts of some sections agree with
/// epub.js's.
class _Agreement {
  _Agreement();

  /// The agreement of one section, whose native pages hold the line starts
  /// [ours] and whose epub.js pages held [theirs], as visible character
  /// indices.
  factory _Agreement.of(List<List<int>> ours, List<List<int>> theirs) {
    final ourLines = {for (final page in ours) ...page};
    final theirLines = {for (final page in theirs) ...page};
    final ourStarts = {
      for (final page in ours)
        if (page.isNotEmpty) page.first,
    };
    final theirStarts = [
      for (final page in theirs)
        if (page.isNotEmpty) page.first,
    ];
    return _Agreement()
      ..sections = 1
      ..lines = theirLines.length
      ..sameLines = theirLines.intersection(ourLines).length
      ..pages = theirStarts.length
      ..samePages = theirStarts.where(ourStarts.contains).length
      ..samePageCount = ours.length == theirs.length ? 1 : 0;
  }

  int sections = 0;

  /// epub.js's line starts, and how many of them start a native line.
  int lines = 0;
  int sameLines = 0;

  /// epub.js's page starts, and how many of them start a native page.
  int pages = 0;
  int samePages = 0;

  /// The sections whose page count is the same in both.
  int samePageCount = 0;

  double get lineShare => lines == 0 ? 1 : sameLines / lines;
  double get pageShare => pages == 0 ? 1 : samePages / pages;

  void add(_Agreement other) {
    sections += other.sections;
    lines += other.lines;
    sameLines += other.sameLines;
    pages += other.pages;
    samePages += other.samePages;
    samePageCount += other.samePageCount;
  }

  Map<String, int> toJson() => {
    'sections': sections,
    'lineStarts': lines,
    'sameLineStarts': sameLines,
    'pageStarts': pages,
    'samePageStarts': samePages,
    'samePageCount': samePageCount,
  };

  @override
  String toString() =>
      '$sections sections, line starts $sameLines of $lines, page starts '
      '$samePages of $pages, same page count in $samePageCount';
}
