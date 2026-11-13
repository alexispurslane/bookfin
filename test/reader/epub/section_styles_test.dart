import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/admitted_books.dart';
import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'flow_dump.dart';
import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, WatchedPublication;

/// A book whose sections link different sheets, with unused sheets that
/// must not travel to a preparation worker.
Uint8List styledBook({
  int paragraphs = 1,
  int unused = 40,
  Map<String, String> extraSheets = const {},
}) {
  final sheets = <String, String>{
    'one.css':
        '@import "nested/deep.css" (prefers-color-scheme: dark);'
        '@import "shared.css" (min-width: 600px);'
        '@import "missing.css"; @import "https://invalid.test/a.css";'
        'p {font-size: 19px} .order {font-style: normal}',
    'nested/deep.css': '@import "../shared.css"; p {font-weight: bold}',
    'shared.css': '@import "end.css"; p {text-indent: 7px}',
    'end.css': '@import "one.css"; p {letter-spacing: 1px}',
    'two.css': 'p {font-size: 23px}',
    'three.css': 'p {font-size: 23px}',
    'four.css': 'p {font-size: 9px}',
    'inline.css': '.order {font-style: italic}',
    for (var i = 0; i < unused; i++) 'unused$i.css': 'p {font-size: 80px}',
    ...extraSheets,
  };
  final entries = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    ),
    'OPS/book.opf': utf8.encode(
      '<package version="3.0"><metadata/><manifest>'
      '${[for (var i = 0; i < 4; i++) '<item id="s$i" href="s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
      '${[for (final (i, path) in sheets.keys.indexed) '<item id="c$i" href="css/$path" media-type="text/css"/>'].join()}'
      '</manifest><spine><itemref idref="s0"/><itemref idref="s1"/><itemref idref="s2"/><itemref idref="s3"/></spine></package>',
    ),
    for (final (i, sheet) in ['one', 'two', 'three', 'four'].indexed)
      'OPS/s$i.xhtml': utf8.encode(
        '<html><head><title>Section $i</title>'
        '<link rel="stylesheet" href="css/$sheet.css"/>'
        '${i == 0 ? '<style>@import "css/inline.css"; p {margin-top: 3px}</style>' : ''}'
        '</head><body><h1>Section $i</h1>'
        '${List.filled(i == 3 ? 1 : paragraphs, '<p class="order">A river follows the road past the forest and the village.</p>').join()}'
        '<p style="font-size: 13px">End.</p></body></html>',
      ),
    for (final entry in sheets.entries)
      'OPS/css/${entry.key}': utf8.encode(entry.value),
  };
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

SectionSource input(Publication book, int index, {bool all = false}) {
  final path = book.spine[index];
  return SectionSource(
    index: index,
    path: path,
    xhtml: utf8.decode(book.textFiles[path]!),
    styleSheets: all ? book.bookStyles : book.stylesForSection(path),
    imageSizes: book.imageSizes,
    language: book.language,
    mainTextSize: book.mainTextSize,
    contents: book.contents,
    packagePath: book.packagePath,
  );
}

const firstPaths = {
  'OPS/css/one.css',
  'OPS/css/nested/deep.css',
  'OPS/css/shared.css',
  'OPS/css/end.css',
  'OPS/css/inline.css',
};

/// Reports the actual map received by a worker when preparation reads it.
/// It wraps the real Publication query, without selecting paths itself.
class _ObservedStyles extends MapBase<String, String> {
  _ObservedStyles(this.inner, this.report);
  final Map<String, String> inner;
  final SendPort report;
  bool reported = false;

  @override
  String? operator [](Object? key) {
    if (!reported) {
      reported = true;
      report.send((Isolate.current.debugName, inner.keys.toList()));
    }
    return inner[key];
  }

  @override
  Iterable<String> get keys => inner.keys;
  @override
  void operator []=(String key, String value) =>
      throw UnsupportedError('read only');
  @override
  void clear() => throw UnsupportedError('read only');
  @override
  String? remove(Object? key) => throw UnsupportedError('read only');
}

class _ObservedPublication extends WatchedPublication {
  _ObservedPublication(super.inner, this.report);
  final SendPort report;

  // A worker that captures the publication instead of detached section
  // inputs fails to send it. Finalizers cannot cross an isolate boundary.
  final callerOnly = Finalizer<Object>((_) {});

  @override
  Map<String, String> get bookStyles =>
      _ObservedStyles(inner.bookStyles, report);
  @override
  Map<String, String> stylesForSection(String path) =>
      _ObservedStyles(inner.stylesForSection(path), report);
}

EpubPlace? _middle(DomSection dom) =>
    EpubPlace(0, dom.texts[dom.texts.length ~/ 2].order, 0);

void main() {
  setUpAll(loadReaderFont);

  test('import collection bounds repeated routes and ignores unavailable or late references', () {
    final reads = <String, int>{};
    final imports = StyleSheet.imports(
      '@import "branch.css"; @import "branch.css" (min-width: 600px);'
      '@import "missing.css"; @import url("https://invalid.test/a.css");'
      'p {font-size: 19px} @import "late.css";',
      path: 'OPS/css/root.css',
      read: (path) {
        reads.update(path, (count) => count + 1, ifAbsent: () => 1);
        return switch (path) {
          'OPS/css/branch.css' =>
            '@import "root.css"; @import "leaf%20one.css#ignored";',
          'OPS/css/leaf one.css' => 'p {font-size: 22px}',
          _ => null,
        };
      },
    );
    expect(imports, {'OPS/css/branch.css', 'OPS/css/leaf one.css'});
    expect(reads, {
      'OPS/css/branch.css': 1,
      'OPS/css/leaf one.css': 1,
      'OPS/css/missing.css': 1,
    });
  });

  test('inline-only sections need no external CSS and duplicate links keep cascade order', () {
    final source = SectionSource(
      index: 0,
      path: 'OPS/one.xhtml',
      xhtml:
          '<html><head><link rel="stylesheet" href="a.css"/>'
          '<style>p {font-style: italic}</style>'
          '<link rel="stylesheet" href="a.css"/>'
          '<link rel="stylesheet" href="missing.css"/>'
          '</head><body><p>River.</p></body></html>',
      styleSheets: {
        'OPS/a.css': 'p {font-style: normal}',
        'OPS/unused.css': 'p {font-size: 80px}',
      },
    );
    expect(sectionStylePaths(source), ['OPS/a.css']);
    final dom = DomSection.parse(source.xhtml);
    expect(
      styleSection(source, dom, readerPage)[dom.body.elements.single]!.italic,
      isFalse,
    );
    expect(
      sectionStylePaths(
        const SectionSource(
          index: 0,
          path: 'OPS/one.xhtml',
          xhtml: '<html><head><style>p {font-style: italic}</style></head><body><p>River.</p></body></html>',
        ),
      ),
      isEmpty,
    );
  });

  test('a section carries only reachable CSS, including conditional and inline imports', () {
    final book = Publication.admit(styledBook());
    expect(book.stylesForSection(book.spine[0]).keys.toSet(), firstPaths);
    expect(book.stylesForSection(book.spine[1]).keys, ['OPS/css/two.css']);
    book.checkInvariants();
  });

  test('section CSS keeps prepared styling, main text size and chapter labels across settings', () {
    final book = Publication.admit(styledBook(paragraphs: 3));
    for (final width in [320.0, 800.0]) {
      for (final night in [false, true]) {
        final settings = PageSettings(
          width: width,
          height: 671,
          fontSize: 18,
          night: night,
        );
        final selected = prepareSections([input(book, 0)], settings).single;
        final full = prepareSections([
          input(book, 0, all: true),
        ], settings).single;
        expect(dumpPrepared(selected), dumpPrepared(full));
        expect(
          selected.chapters.at(EpubPlace(0, selected.dom.texts.last.order, 0)),
          'Section 0',
        );
        expect(shownMainTextSize([input(book, 0)], settings), 19);
        expect(selected.styles.any((style) => style.italic), isTrue);
        final dom = selected.dom;
        final paragraph = elementsOf(dom.body)
            .firstWhere((element) => element.name == 'p');
        final style = styleSection(input(book, 0), dom, settings)[paragraph]!;
        expect(style.fontWeight, night ? 700 : 400);
        expect(style.textIndent.value, night || width >= 600 ? 7 : 0);
        expect(style.italic, isTrue);
      }
    }
  });

  test(
    'conditional short routes retain imports hidden by a deeper first route',
    () {
      final book = Publication.admit(
        styledBook(
          extraSheets: {
            'one.css':
                '@charset "utf-8"; @layer book;'
                '@import "a.css" (prefers-color-scheme: dark);'
                '@import url("d.css") (min-width: 600px);'
                '@import "a.css"; p {font-size: 19px} @import "unused0.css";',
            'a.css': '@import "b.css";',
            'b.css': '@import "c.css";',
            'c.css': '@import "d.css";',
            'd.css': '@import "e.css";',
            'e.css': '@import "f.css";',
            'f.css': '@import "g.css";',
            'g.css': '@import "too-deep.css"; p {font-weight: bold}',
            'too-deep.css': 'p {font-size: 80px}',
          },
        ),
      );
      expect(book.stylesForSection(book.spine[0]).keys.toSet(), {
        'OPS/css/one.css',
        'OPS/css/inline.css',
        for (final letter in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
          'OPS/css/$letter.css',
      });
      for (final night in [false, true]) {
        final settings = PageSettings(
          width: 800,
          height: 671,
          fontSize: 18,
          night: night,
        );
        expect(
          dumpPrepared(prepareSections([input(book, 0)], settings).single),
          dumpPrepared(
            prepareSections([input(book, 0, all: true)], settings).single,
          ),
        );
      }
    },
  );

  for (final path in ['whole', 'partial', 'sample']) {
    test('the actual $path worker receives only its sections CSS', () async {
      final book = Publication.admit(styledBook(paragraphs: 4000));
      final reports = ReceivePort();
      final received = <(String?, List<String>)>[];
      final subscription = reports.listen(
        (value) => received.add(value as (String?, List<String>)),
      );
      final scheduler = TestScheduler();
      final calls = <Future<Object?>>[];
      final results = <Object?>[];
      Future<R> work<R>(FutureOr<R> Function() computation) {
        final call = Isolate.run(computation).then((value) {
          results.add(value);
          return value;
        });
        calls.add(call);
        return call;
      }

      final source = PageSource(
        _ObservedPublication(book, reports.sendPort),
        schedule: scheduler.schedule,
        work: work,
      )..settings = readerPage;
      try {
        if (path == 'whole') {
          final section = await source.section(0);
          expect(
            dumpPrepared(section),
            dumpPrepared(
              prepareSections([input(book, 0, all: true)], readerPage).single,
            ),
          );
        } else if (path == 'partial') {
          final place = await source.findPlace(0, _middle);
          expect(place, isNotNull);
          await source.section(0);
          expect(
            results
                .whereType<({EpubPlace? place, PreparedSection? section})>()
                .single
                .section!
                .whole,
            isFalse,
          );
        } else {
          expect(await source.shownMainText(readerPage), 23);
        }
        await Future.wait(calls);
        // Deliver messages that the completed workers already sent.
        await subscription.cancel();
        expect(received, isNotEmpty);
        for (final (isolate, paths) in received) {
          expect(isolate, isNot(Isolate.current.debugName));
          expect(
            paths.toSet(),
            path == 'sample' && !paths.contains('OPS/css/one.css')
                ? anyOf({'OPS/css/two.css'}, {'OPS/css/three.css'})
                : firstPaths,
          );
        }
        expect(
          received,
          hasLength(
            path == 'sample'
                ? 3
                : path == 'partial'
                ? 2
                : 1,
          ),
        );
        if (path == 'sample') {
          expect(
            received.map((entry) => entry.$2.toSet()),
            unorderedEquals([
              firstPaths,
              {'OPS/css/two.css'},
              {'OPS/css/three.css'},
            ]),
          );
        }
        final supplied = received.fold<int>(
          0,
          (count, entry) => count + entry.$2.length,
        );
        expect(
          supplied,
          path == 'sample'
              ? 7
              : path == 'partial'
              ? 10
              : 5,
        );
        // The old sample worker held one shared full map for all samples.
        final previousInputs =
            book.bookStyles.length * (path == 'partial' ? 2 : 1);
        debugPrint(
          '$path CSS map entries: $supplied; previous worker inputs: $previousInputs',
        );
      } finally {
        await Future.wait(calls);
        source.dispose();
        await subscription.cancel();
        reports.close();
      }
    });
  }

  test(
    'an admitted EPUB keeps every prepared section with selected sheets',
    () {
      final book = Publication.admit(
        File('test/reader/fixtures/broken-image.epub').readAsBytesSync(),
      );
      var supplied = 0;
      for (var index = 0; index < book.spine.length; index++) {
        supplied += input(book, index).styleSheets.length;
        expect(
          dumpPrepared(
            prepareSections([input(book, index)], readerPage).single,
          ),
          dumpPrepared(
            prepareSections([input(book, index, all: true)], readerPage).single,
          ),
        );
      }
      expect(
        supplied,
        lessThanOrEqualTo(book.spine.length * book.bookStyles.length),
      );
    },
  );

  test('real Alice MOBI sections and its admitted reopen keep their styled output', () async {
    final folder = await Directory.systemTemp.createTemp(
      'bookfin-section-css-',
    );
    final file = await File('tool/research/readers/fixtures/pg11-kf8.mobi')
        .copy('${folder.path}/alice.mobi');
    final digest = sha256.convert(await file.readAsBytes()).toString();
    addTearDown(() async {
      await AdmittedBooks.written(file);
      await folder.delete(recursive: true);
    });
    final original = VerifiedFile(file.uri, digest);
    final admitted = await readMobi(original, (book) => book);
    await AdmittedBooks.written(file);
    await file.writeAsString('The original MOBI is unavailable.');
    final reopened = await readMobi(original, (book) => book);
    var supplied = 0;
    for (final book in [admitted, reopened]) {
      book.checkInvariants();
      for (var index = 0; index < book.spine.length; index++) {
        supplied += input(book, index).styleSheets.length;
        for (final night in [false, true]) {
          final settings = PageSettings(
            width: night ? 800 : 320,
            height: 671,
            fontSize: 18,
            night: night,
          );
          final full = prepareSections([
            input(book, index, all: true),
          ], settings).single;
          final selected = prepareSections([
            input(book, index),
          ], settings).single;
          expect(
            dumpPrepared(selected),
            dumpPrepared(full),
            reason: 'section $index, night $night',
          );
        }
      }
    }
    expect(
      supplied,
      lessThanOrEqualTo(2 * admitted.spine.length * admitted.bookStyles.length),
    );
    debugPrint(
      'Alice original + admitted reopen: ${2 * admitted.spine.length} section inputs, $supplied CSS entries; full maps: ${2 * admitted.spine.length * admitted.bookStyles.length}',
    );
  });
}
