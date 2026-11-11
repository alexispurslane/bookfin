// A downloaded EPUB or MOBI is admitted once. The first open checks and
// sanitizes the book and keeps the admitted book beside the download. Each
// later open of the same file under the same policy reads that record, and
// does not unzip, sanitize or hash the book again (t7-rcyp).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/reader/admitted_books.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart' show EpubPlace;
import 'package:bookfin/reader/epub/page_maps.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

import '../playback/playback_test.dart' show account;
import 'epub/corpus/book.dart' show showcaseBooks;
import 'epub/helpers.dart';
import 'epub/page_source_test.dart' show TestScheduler;
import 'publication_test.dart' show epub;
import 'session_test.dart' as fixture;

SourceFile _source(String container) => SourceFile(
  itemId: 'book',
  displayName: 'Book.$container',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: container,
  sizeBytes: 1000,
);

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

/// A download of [bytes] in a folder of its own, as Downloads keeps it.
Future<File> _download(List<int> bytes) async {
  final folder = await Directory.systemTemp.createTemp('bookfin-admitted-');
  addTearDown(() => folder.delete(recursive: true));
  return File('${folder.path}/complete').writeAsBytes(bytes);
}

/// The kept record of the download [file].
File _record(File file) =>
    File('${file.parent.path}/.bookfin-admitted/publication');

/// Every admitted fact of [publication], in a form that compares by value.
Map<String, Object?> _facts(Publication publication) => {
  'originalDigest': publication.originalDigest,
  'identity': publication.identity,
  'packagePath': publication.packagePath,
  'spine': publication.spine,
  'spineSteps': publication.spineSteps,
  'warnings': publication.warnings,
  'language': publication.language,
  'contents': [
    for (final entry in publication.contents)
      [entry.title, entry.href, entry.depth],
  ],
  'bookStyles': publication.bookStyles,
  'imageSizes': {
    for (final MapEntry(key: path, value: (width, height))
        in publication.imageSizes.entries)
      path: [width, height],
  },
  'mediaTypes': publication.mediaTypes,
  'mainTextSize': publication.mainTextSize,
  'resources': {
    for (final MapEntry(key: path, value: bytes)
        in publication.resources.entries)
      path: _digest(bytes),
  },
};

Future<EpubDocument> _open(File file, String digest, String container) async =>
    await loadReadingDocument(
      VerifiedFile(file.uri, digest),
      _source(container),
    ) as EpubDocument;

/// The places that the code before the kept admitted books saved, by book.
final _placesBefore =
    (jsonDecode(
          File('test/reader/fixtures/places-before-admission-cache.json')
              .readAsStringSync(),
        ) as Map)['books']
        as Map<String, dynamic>;

final _books = <String, (Uint8List, String)>{
  'showcase-frost.epub': (showcaseBooks()['showcase-frost']!, 'epub'),
  'broken-image.epub': (
    File('test/reader/fixtures/broken-image.epub').readAsBytesSync(),
    'epub',
  ),
  'pg11-kf8.mobi': (
    File('tool/research/readers/fixtures/pg11-kf8.mobi').readAsBytesSync(),
    'mobi',
  ),
};

void main() {
  setUpAll(loadReaderFont);

  group('an EPUB', () {
    test('a second open of a book reads the kept admitted book, not the '
        'downloaded file', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);
      final first = await _open(file, _digest(bytes), 'epub');

      // The kept record is the only source left: the file is no EPUB now.
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final second = await _open(file, _digest(bytes), 'epub');

      expect(_facts(second.publication), _facts(first.publication));
      second.publication.checkInvariants();
    });

    test('the publication keeps the digest that Downloads verified, and the '
        'open does not hash the book again', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);
      // Downloads computed this digest when the download completed.
      final verified = 'a' * 64;

      final document = await _open(file, verified, 'epub');

      expect(document.originalDigest, verified);
      expect(document.publication.originalDigest, verified);
    });

    test('a book whose file changed admits again', () async {
      final first = showcaseBooks()['showcase-frost']!;
      final changed = showcaseBooks()['showcase-salt']!;
      final file = await _download(first);
      final before = await _open(file, _digest(first), 'epub');

      await file.writeAsBytes(changed);
      final after = await _open(file, _digest(changed), 'epub');

      expect(after.identity, isNot(before.identity));
      expect(
        _facts(after.publication),
        _facts(Publication.admit(changed, _digest(changed))),
      );
    });

    for (final (name, damage) in [
      ('garbage', (Uint8List kept) => utf8.encode('not a kept book')),
      ('cut short', (Uint8List kept) => kept.sublist(0, kept.length ~/ 2)),
    ]) {
      test('a kept record that is $name is set aside, and the book admits '
          'in full', () async {
        final bytes = showcaseBooks()['showcase-frost']!;
        final file = await _download(bytes);
        final first = await _open(file, _digest(bytes), 'epub');
        final record = _record(file);
        final unreadable = damage(await record.readAsBytes());
        await record.writeAsBytes(unreadable);

        final second = await _open(file, _digest(bytes), 'epub');

        expect(_facts(second.publication), _facts(first.publication));
        expect(
          await File('${record.path}.unreadable').readAsBytes(),
          unreadable,
        );
        // The full admission kept a new record.
        await file.writeAsBytes(List.filled(bytes.length, 0));
        final third = await _open(file, _digest(bytes), 'epub');
        expect(_facts(third.publication), _facts(first.publication));
      });
    }

    test('removing a download removes its kept admitted book', () async {
      final root = await Directory.systemTemp.createTemp('bookfin-removal-');
      addTearDown(() => root.delete(recursive: true));
      final policy = MediaPolicy()..network = MediaNetwork.disconnected;
      addTearDown(policy.dispose);
      final downloads = LocalDownloads(
        root: root,
        freeBytes: () async => 100000000,
        policy: policy,
      );
      addTearDown(downloads.dispose);
      final bytes = epub();
      final source = SourceFile(
        itemId: fixture.source.itemId,
        mediaSourceId: fixture.source.mediaSourceId,
        revision: fixture.source.revision,
        displayName: 'Verified.epub',
        container: 'epub',
        durationMs: null,
        sizeBytes: bytes.length,
        isItemOriginal: true,
      );
      final edition = Edition(
        id: fixture.edition.id,
        kind: EditionKind.text,
        label: 'EPUB',
        files: [source],
        memberIds: [source.key],
      );
      final directory = await _savedDownload(root, source, bytes);
      await downloads.bind(account(), [
        Book(
          id: fixture.book.id,
          title: 'River',
          author: 'Writer',
          editions: [edition],
        ),
      ]);

      final digest = await downloads.readLocalFile(source, (file) async {
        await loadReadingDocument(file, source);
        return file.digest;
      });
      expect(digest, _digest(bytes));
      expect(
        await Directory('${directory.path}/.bookfin-admitted').exists(),
        isTrue,
      );

      await downloads.remove(edition);
      await downloads.idle;

      expect(
        await Directory('${directory.path}/.bookfin-admitted').exists(),
        isFalse,
      );
    });
  });

  group('the main text size', () {
    /// A book with a heading and a paragraph in [size].
    Uint8List sized(String size) => epub(
      chapter:
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>River'
          '</title><link rel="stylesheet" href="book.css"/></head><body>'
          '<h1>River</h1><p>${prose(4)}</p></body></html>',
      extra: {'OPS/book.css': utf8.encode('p{font-size:$size}')},
    );

    test('the first open measures the book\'s main text', () async {
      final bytes = sized('9pt');
      final document = await _open(
        await _download(bytes),
        _digest(bytes),
        'epub',
      );
      expect(document.publication.mainTextSize, 12);
    });

    test(
      'a second open of a book does not measure its main text again',
      () async {
        final bytes = sized('9pt');
        final file = await _download(bytes);
        await _open(file, _digest(bytes), 'epub');

        // The kept record is the only source left: the file is no EPUB now.
        await file.writeAsBytes(List.filled(bytes.length, 0));
        final second = await _open(file, _digest(bytes), 'epub');

        expect(second.publication.mainTextSize, 12);
      },
    );

    test('a book whose file changed measures again', () async {
      final first = sized('9pt');
      final changed = sized('18pt');
      final file = await _download(first);
      await _open(file, _digest(first), 'epub');

      await file.writeAsBytes(changed);
      final after = await _open(file, _digest(changed), 'epub');

      expect(after.publication.mainTextSize, 24);
    });

    test('a kept size that is no type size is set aside, and the book '
        'measures again', () async {
      final bytes = sized('9pt');
      final file = await _download(bytes);
      await _open(file, _digest(bytes), 'epub');
      final record = _record(file);
      // The same number of bytes, so the record's header keeps its length.
      final damaged = latin1.encode(
        latin1
            .decode(await record.readAsBytes())
            .replaceFirst('"mainTextSize":12.0', '"mainTextSize":-1.0'),
      );
      expect(damaged, isNot(await record.readAsBytes()));
      await record.writeAsBytes(damaged);

      final second = await _open(file, _digest(bytes), 'epub');

      expect(second.publication.mainTextSize, 12);
      expect(await File('${record.path}.unreadable').exists(), isTrue);
    });

    test('a book admitted before main text sizes were kept admits again, '
        'and so measures its main text', () async {
      final bytes = sized('9pt');
      final digest = _digest(bytes);
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, digest);
      }

      await AdmittedBooks.open(file, digest, 'policy-1', admit);
      // The record as revision 1 kept it, before it held the size.
      final record = _record(file);
      final kept = await record.readAsBytes();
      final end = kept.indexOf(0x0a);
      await record.writeAsBytes([
        ...utf8.encode(jsonEncode([1, 'policy-1', digest])),
        ...kept.sublist(end),
      ]);

      final reopened = await AdmittedBooks.open(
        file,
        digest,
        'policy-1',
        admit,
      );

      expect(admissions, 2);
      expect(reopened.mainTextSize, 12);
    });
  });

  group('the record of admitted books', () {
    test('a second open under the same policy does not admit the book '
        'again', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      await AdmittedBooks.open(file, _digest(bytes), 'policy-1', admit);
      await AdmittedBooks.open(file, _digest(bytes), 'policy-1', admit);

      expect(admissions, 1);
    });

    test('a new policy admits the book again', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      await AdmittedBooks.open(file, _digest(bytes), 'policy-1', admit);
      await AdmittedBooks.open(file, _digest(bytes), 'policy-2', admit);
      await AdmittedBooks.open(file, _digest(bytes), 'policy-2', admit);

      expect(admissions, 2);
    });

    test('a write that stopped midway leaves the kept book readable', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      await AdmittedBooks.open(file, _digest(bytes), 'policy-1', admit);
      // A process that was killed while it wrote left its partial file.
      final kept = await _record(file).readAsBytes();
      await File('${_record(file).parent.path}/publication-killed.partial')
          .writeAsBytes(kept.sublist(0, kept.length ~/ 3));

      final again = await AdmittedBooks.open(
        file,
        _digest(bytes),
        'policy-1',
        admit,
      );

      expect(admissions, 1);
      again.checkInvariants();
    });

    test('a record that cannot be kept does not stop the book from '
        'opening', () async {
      final bytes = epub();
      final file = await _download(bytes);
      // A file where the record's folder belongs.
      await File('${file.parent.path}/.bookfin-admitted').writeAsString('');

      final publication = await AdmittedBooks.open(
        file,
        _digest(bytes),
        'policy-1',
        () async => Publication.admit(bytes, _digest(bytes)),
      );

      expect(publication.spine, ['OPS/one.xhtml']);
    });
  });

  group('a MOBI', () {
    test('a second open reads the kept admitted book, without its '
        'conversion or its file', () async {
      final bytes = _books['pg11-kf8.mobi']!.$1;
      final file = await _download(bytes);
      final first = await _open(file, _digest(bytes), 'mobi');

      await Directory('${file.parent.path}/.bookfin-mobi')
          .delete(recursive: true);
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final second = await _open(file, _digest(bytes), 'mobi');

      expect(second.format, 'mobi');
      expect(second.identity, first.identity);
      expect(second.originalDigest, first.originalDigest);
      expect(_facts(second.publication), _facts(first.publication));
    });
  });

  group('a place saved before the admission cache', () {
    for (final MapEntry(key: name, value: (bytes, container))
        in _books.entries) {
      final saved = (_placesBefore[name] as Map).cast<String, dynamic>();

      test('opens at the same place in $name, at the first and at a later '
          'open', () async {
        final file = await _download(bytes);
        for (final open in ['first', 'later']) {
          final document = await _open(file, _digest(bytes), container);
          expect(document.originalDigest, saved['original'], reason: open);
          // Since boo-yjq6, an EPUB's identity names the policy, the
          // admission revision and the file's digest, so its places carry
          // an older identity. A MOBI's identity did not change.
          expect(
            document.identity,
            container == 'epub'
                ? isNot(saved['processed'])
                : saved['processed'],
            reason: open,
          );
          final address = document.restore(saved);
          expect(address, isNotNull, reason: open);

          final scheduler = TestScheduler();
          final reported = <EpubAddress>[];
          final warnings = <String>[];
          final pager = EpubPager(
            document,
            initial: address,
            onPlace: reported.add,
            onWarning: warnings.add,
            source: PageSource(
              document.publication,
              schedule: scheduler.schedule,
            ),
          );
          final shown = Completer<void>();
          pager.shown.addListener(() {
            if (!shown.isCompleted) shown.complete();
          });
          pager.present(readerPage);
          await scheduler.until(shown.future);
          pager.dispose();

          expect(warnings, isEmpty, reason: open);
          expect(reported.first.location.cfi, saved['cfi'], reason: open);
        }
      });
    }
  });

  group('the identity of policy, revision and digest (boo-yjq6)', () {
    const engine = 'install-1\nbuild-1\nen-US';

    /// Lays out every section of [publication] at [readerPage] with the page
    /// maps of the download [file] under the book identity [book], and gives
    /// the map that the source keeps.
    Future<List<KeptSection>> layOutWhole(
      File file,
      Publication publication,
      String book,
    ) async {
      final pageMaps = BookPageMaps(
        file,
        book: book,
        engine: Future.value(engine),
      );
      final scheduler = TestScheduler();
      final source = PageSource(
        publication,
        schedule: scheduler.schedule,
        pageMaps: pageMaps,
      )..settings = readerPage;
      addTearDown(source.dispose);
      final dom = (await scheduler.until(source.section(0))).dom;
      source.show(
        await scheduler.until(
          source.pageAt(
            EpubPlace(0, dom.body.order, 0),
            anchored: true,
            urgent: true,
          ),
        ),
      );
      await scheduler.settle();
      for (var tries = 0; tries < 400; tries++) {
        if (await pageMaps.read(readerPage) case final kept?) return kept;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('The page map was never kept.');
    }

    test('the first open after the change lays out the page map once again, '
        'and the next open reads it', () async {
      final (bytes, _) = _books['showcase-frost.epub']!;
      final file = await _download(bytes);
      final document = await _open(file, _digest(bytes), 'epub');
      // The map that an open before boo-yjq6 kept, under the identity that
      // hashed every admitted file.
      final before =
          (_placesBefore['showcase-frost.epub'] as Map)['processed'] as String;
      await layOutWhole(file, document.publication, before);

      final maps = BookPageMaps(
        file,
        book: document.identity,
        engine: Future.value(engine),
      );
      expect(await maps.read(readerPage), isNull);
      final laid = await layOutWhole(
        file,
        document.publication,
        document.identity,
      );

      final next = await _open(file, _digest(bytes), 'epub');
      expect(next.identity, document.identity);
      expect(
        await BookPageMaps(
          file,
          book: next.identity,
          engine: Future.value(engine),
        ).read(readerPage),
        laid,
      );
    });
  });

  group('admission', () {
    test('keeps an image whose header is sound, without decoding its '
        'pixels', () {
      final publication = Publication.admit(_books['broken-image.epub']!.$1);

      expect(publication.imageSizes['OPS/plate.jpg'], (40, 30));
      expect(publication.resources, contains('OPS/plate.jpg'));
    });

    for (final (name, image) in [
      (
        'has more than 16 million pixels',
        raster.encodePng(raster.Image(width: 5000, height: 3201)),
      ),
      ('has no readable header', utf8.encode('not a picture at all')),
    ]) {
      test('still refuses an image that $name', () {
        final publication = Publication.admit(
          epub(extra: {'OPS/dot.png': image}),
        );

        expect(publication.imageSizes, isNot(contains('OPS/dot.png')));
        expect(publication.resources, isNot(contains('OPS/dot.png')));
        expect(
          publication.warnings,
          contains(
            'Some images are damaged or exceed the 16-million-pixel limit.',
          ),
        );
      });
    }

    test('names the spine step of each section as the admitted package '
        'document gives it', () {
      for (final (bytes, container) in _books.values) {
        if (container != 'epub') continue;
        final publication = Publication.admit(bytes);
        expect(
          publication.spineSteps,
          spineSteps(
            utf8.decode(publication.resources[publication.packagePath]!),
          ),
        );
      }
    });
  });
}

/// A complete download of [bytes] for [source], saved as Downloads saves it
/// under [root].
Future<Directory> _savedDownload(
  Directory root,
  SourceFile source,
  List<int> bytes,
) async {
  String hash(String value) => _digest(utf8.encode(value));
  final directory = Directory(
    '${root.path}/${hash(account().scope.key)}/'
    '${hash(jsonEncode([source.key, source.revision]))}',
  );
  await directory.create(recursive: true);
  await File('${directory.path}/complete').writeAsBytes(bytes);
  await File('${directory.path}/record.json').writeAsString(
    jsonEncode({
      'key': source.key,
      'revision': source.revision,
      'length': bytes.length,
      'digest': _digest(bytes),
      'complete': true,
      'requested': false,
    }),
  );
  return directory;
}
