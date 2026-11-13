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
import 'epub/book_fonts_test.dart' show face, fontBook, star, starFont;
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

/// A download of [bytes] in a folder of its own, as Downloads keeps it. It
/// is removed after the test, once the loads of it wrote their records, as
/// a removal of a download waits for them.
Future<File> _download(List<int> bytes) async {
  final folder = await Directory.systemTemp.createTemp('bookfin-admitted-');
  final file = File('${folder.path}/complete');
  addTearDown(() async {
    await AdmittedBooks.written(file);
    await folder.delete(recursive: true);
  });
  return file.writeAsBytes(bytes);
}

/// The kept record of the download [file].
File _record(File file) =>
    File('${file.parent.path}/.bookfin-admitted/publication');

/// Refuses a record open in the calling isolate. IO overrides stay in this
/// zone; the real load worker opens the real saved record. Keep path queries
/// available because the caller tracks pending writes by record path.
T _withoutRecordOpen<T>(File original, T Function() work) {
  final record = _record(original);
  return IOOverrides.runZoned(
    work,
    createFile: (path) => path == record.path
        ? _RecordNeedsWorker(record)
        : Zone.root.run(() => File(path)),
  );
}

class _RecordNeedsWorker extends Fake implements File {
  _RecordNeedsWorker(this.file);
  final File file;

  @override
  String get path => file.path;
  @override
  Directory get parent => file.parent;
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      throw _RecordOpenedInCaller();
}

class _RecordOpenedInCaller extends Error {}

/// The publication of the download [file] as [AdmittedBooks.read] gives it
/// in this isolate, once its record is kept.
Future<Publication> _openHere(
  File file,
  String digest,
  String policy,
  Future<Publication> Function() admit,
) async {
  final (publication, record) = await AdmittedBooks.read(
    file,
    digest,
    policy,
    admit,
  );
  if (record != null) await AdmittedBooks.keep(record);
  return publication;
}

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
  'sectionFaces': publication.sectionFaces,
  'resources': {
    for (final MapEntry(key: path, value: bytes)
        in publication.textFiles.entries)
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

  test('the record-open guard detects a saved record read in the calling '
      'isolate', () async {
    final bytes = epub();
    final file = await _download(bytes);
    final digest = _digest(bytes);
    await _open(file, digest, 'epub');
    await AdmittedBooks.written(file);

    await expectLater(
      _withoutRecordOpen(
        file,
        () => _openHere(
          file,
          digest,
          Publication.policy,
          () => throw StateError('The saved book must not admit again.'),
        ),
      ),
      throwsA(isA<_RecordOpenedInCaller>()),
    );
  });

  group('an EPUB', () {
    test('a second open reads the saved EPUB outside the calling isolate, '
        'without the downloaded bytes', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);
      final first = await _open(file, _digest(bytes), 'epub');
      await AdmittedBooks.written(file);

      // The kept record is the only source left: the file is no EPUB now.
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final second = await _withoutRecordOpen(
        file,
        () => _open(file, _digest(bytes), 'epub'),
      );

      expect(_facts(second.publication), _facts(first.publication));
      second.publication.checkInvariants();
    });

    test('the publication loader reads the saved EPUB outside the calling '
        'isolate, without the downloaded bytes', () async {
      final bytes = epub();
      final file = await _download(bytes);
      final original = VerifiedFile(file.uri, _digest(bytes));
      final first = await loadPublication(original);
      await AdmittedBooks.written(file);
      await file.writeAsBytes(List.filled(bytes.length, 0));

      final second = await _withoutRecordOpen(
        file,
        () => loadPublication(original),
      );

      expect(_facts(second), _facts(first));
      expect(
        () => second.textFiles['OPS/one.xhtml']![0] = 0,
        throwsUnsupportedError,
      );
      expect(
        await second.bytesOf('OPS/dot.png'),
        await first.bytesOf('OPS/dot.png'),
      );
      second.checkInvariants();
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
      // The largest header length that the record can name, far past its
      // end (boo-yjq6 review).
      (
        'naming a header past its end',
        (Uint8List kept) => Uint8List.fromList(kept)
          ..setRange(kept.indexOf(0x0a) + 1, kept.indexOf(0x0a) + 5, [
            0xff,
            0xff,
            0xff,
            0xff,
          ]),
      ),
    ]) {
      test('a kept record that is $name is set aside, and the book admits '
          'in full', () async {
        final bytes = showcaseBooks()['showcase-frost']!;
        final file = await _download(bytes);
        final first = await _open(file, _digest(bytes), 'epub');
        await AdmittedBooks.written(file);
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

    test('a load whose use of the book fails still keeps the record of the '
        'book that it admitted', () async {
      final bytes = epub();
      final file = await _download(bytes);
      final digest = _digest(bytes);

      await expectLater(
        AdmittedBooks.load(
          VerifiedFile(file.uri, digest),
          Publication.policy,
          () async => Publication.admit(bytes, digest),
          (_) => throw const FormatException('No outline in this book.'),
        ),
        throwsFormatException,
      );

      await AdmittedBooks.written(file);
      expect(await _record(file).exists(), isTrue);
    });

    test('a load writes its record under a hold of the download, so that '
        'a removal of the download waits for the write', () async {
      final bytes = epub();
      final file = await _download(bytes);
      final held = <Future<void>>[];
      final lent = VerifiedFile.lent(
        file.uri,
        _digest(bytes),
        hold: (work) {
          final done = work();
          held.add(done);
          return done;
        },
      );

      await loadReadingDocument(lent, _source('epub'));

      expect(held, hasLength(1));
      await Future.wait(held);
      expect(await _record(file).exists(), isTrue);
    });

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

      // The read ends once the book loads. Its record is written after,
      // under a hold of the download.
      final digest = await downloads.readLocalFile(source, (file) async {
        await loadReadingDocument(file, source);
        return file.digest;
      });
      expect(digest, _digest(bytes));

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
      await AdmittedBooks.written(file);
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

      await _openHere(file, digest, 'policy-1', admit);
      // The record as revision 1 kept it, before it held the size.
      final record = _record(file);
      final kept = await record.readAsBytes();
      final end = kept.indexOf(0x0a);
      await record.writeAsBytes([
        ...utf8.encode(jsonEncode([1, 'policy-1', digest])),
        ...kept.sublist(end),
      ]);

      final reopened = await _openHere(file, digest, 'policy-1', admit);

      expect(admissions, 2);
      expect(reopened.mainTextSize, 12);
    });
  });

  test('a record of revision 4, kept before admission chose the fonts that '
      "a book's sections need, admits again and keeps those fonts", () async {
    final bytes = fontBook(
      ['<p>A star $star here.</p>'],
      css: '${face('Star', 'star.woff')}p{font-family:Star,serif}',
      fonts: {'star.woff': starFont},
    );
    final digest = _digest(bytes);
    final file = await _download(bytes);
    var admissions = 0;
    Future<Publication> admit() async {
      admissions++;
      return Publication.admit(bytes, digest);
    }

    await _openHere(file, digest, 'policy-1', admit);
    final record = _record(file);
    final kept = await record.readAsBytes();
    final end = kept.indexOf(0x0a);
    await record.writeAsBytes([
      ...utf8.encode(jsonEncode([4, 'policy-1', digest])),
      ...kept.sublist(end),
    ]);

    final reopened = await _openHere(file, digest, 'policy-1', admit);

    expect(admissions, 2);
    expect(reopened.sectionFaces, {
      'OPS/text/s0.xhtml': ['OPS/fonts/star.woff'],
    });
    expect(await reopened.bytesOf('OPS/fonts/star.woff'), starFont);
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

      await _openHere(file, _digest(bytes), 'policy-1', admit);
      await _openHere(file, _digest(bytes), 'policy-1', admit);

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

      await _openHere(file, _digest(bytes), 'policy-1', admit);
      await _openHere(file, _digest(bytes), 'policy-2', admit);
      await _openHere(file, _digest(bytes), 'policy-2', admit);

      expect(admissions, 2);
    });

    test('an admission gives its record to keep and writes nothing, and the '
        'record that it keeps opens the book without an admission', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      final (admitted, record) = await AdmittedBooks.read(
        file,
        _digest(bytes),
        'policy-1',
        admit,
      );
      expect(record, isNotNull);
      expect(await _record(file).exists(), isFalse);

      await AdmittedBooks.keep(record!);
      final (kept, none) = await AdmittedBooks.read(
        file,
        _digest(bytes),
        'policy-1',
        admit,
      );

      expect(admissions, 1);
      expect(none, isNull);
      expect(_facts(kept), _facts(admitted));
    });

    test('a book whose record was never written, as when the app stopped '
        'before the write, admits again at the next open', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      await AdmittedBooks.read(file, _digest(bytes), 'policy-1', admit);
      final again = await _openHere(file, _digest(bytes), 'policy-1', admit);

      expect(admissions, 2);
      again.checkInvariants();
    });

    test('a load gives the book before its record is written, and the next '
        'load waits for that record instead of admitting again', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);
      final first = await _open(file, _digest(bytes), 'epub');
      // The kept record is the only source left: the file is no EPUB now.
      await file.writeAsBytes(List.filled(bytes.length, 0));

      final second = await _open(file, _digest(bytes), 'epub');

      expect(_facts(second.publication), _facts(first.publication));
    });

    test('a write that stopped midway leaves the kept book readable', () async {
      final bytes = epub();
      final file = await _download(bytes);
      var admissions = 0;
      Future<Publication> admit() async {
        admissions++;
        return Publication.admit(bytes, _digest(bytes));
      }

      await _openHere(file, _digest(bytes), 'policy-1', admit);
      // A process that was killed while it wrote left its partial file.
      final kept = await _record(file).readAsBytes();
      await File('${_record(file).parent.path}/publication-killed.partial')
          .writeAsBytes(kept.sublist(0, kept.length ~/ 3));

      final again = await _openHere(file, _digest(bytes), 'policy-1', admit);

      expect(admissions, 1);
      again.checkInvariants();
    });

    test('a record that cannot be kept does not stop the book from '
        'opening', () async {
      final bytes = epub();
      final file = await _download(bytes);
      // A file where the record's folder belongs.
      await File('${file.parent.path}/.bookfin-admitted').writeAsString('');

      final publication = await _openHere(
        file,
        _digest(bytes),
        'policy-1',
        () async => Publication.admit(bytes, _digest(bytes)),
      );

      expect(publication.spine, ['OPS/one.xhtml']);
    });
  });

  group('the images and fonts of a kept record (boo-yjq6)', () {
    /// The position of [part] in [bytes].
    int indexOf(List<int> bytes, List<int> part) {
      search:
      for (var at = 0; at + part.length <= bytes.length; at++) {
        for (var index = 0; index < part.length; index++) {
          if (bytes[at + index] != part[index]) continue search;
        }
        return at;
      }
      throw StateError('The part is not in the bytes.');
    }

    final dot = File('tool/research/readers/fixtures/dot.png')
        .readAsBytesSync();

    Future<Publication> admit(Uint8List bytes) async =>
        Publication.admit(bytes, _digest(bytes));

    test('a reopened book holds its documents, and reads an image from its '
        'record only when a page asks for it', () async {
      final bytes = epub();
      final file = await _download(bytes);
      await _openHere(file, _digest(bytes), 'policy-1', () => admit(bytes));
      final reopened = await _openHere(
        file,
        _digest(bytes),
        'policy-1',
        () => throw StateError('The book admitted again.'),
      );
      expect(reopened.textFiles, contains('OPS/one.xhtml'));
      expect(reopened.textFiles, isNot(contains('OPS/dot.png')));

      // The image's bytes in the record change after the reopen.
      final record = await _record(file).readAsBytes();
      final at = indexOf(record, dot);
      final changed = [...dot]..last ^= 0xff;
      record.setRange(at, at + dot.length, changed);
      await _record(file).writeAsBytes(record);

      expect(await reopened.bytesOf('OPS/dot.png'), changed);
      reopened.checkInvariants();
    });

    test('an image whose record was replaced since the reopen reads as '
        'missing, so its page draws its alt text', () async {
      final bytes = epub();
      final file = await _download(bytes);
      await _openHere(file, _digest(bytes), 'policy-1', () => admit(bytes));
      final reopened = await _openHere(
        file,
        _digest(bytes),
        'policy-1',
        () => admit(bytes),
      );

      await _openHere(file, _digest(bytes), 'policy-2', () => admit(bytes));

      expect(await reopened.bytesOf('OPS/dot.png'), isNull);
    });

    test(
      'a book that was just admitted reads its images from memory',
      () async {
        final bytes = epub();
        final publication = await admit(bytes);

        expect(publication.textFiles, isNot(contains('OPS/dot.png')));
        expect(await publication.bytesOf('OPS/dot.png'), dot);
      },
    );
  });

  group('a MOBI', () {
    test('a second open reads the saved MOBI outside the calling isolate, '
        'without its conversion or downloaded bytes', () async {
      final bytes = _books['pg11-kf8.mobi']!.$1;
      final file = await _download(bytes);
      final first = await _open(file, _digest(bytes), 'mobi');
      await AdmittedBooks.written(file);

      await Directory('${file.parent.path}/.bookfin-mobi')
          .delete(recursive: true);
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final second = await _withoutRecordOpen(
        file,
        () => _open(file, _digest(bytes), 'mobi'),
      );

      expect(second.format, 'mobi');
      expect(second.identity, first.identity);
      expect(second.originalDigest, first.originalDigest);
      expect(_facts(second.publication), _facts(first.publication));
    });
  });

  group('the preparation of a download (boo-sy2d)', () {
    test('the first open of a prepared EPUB reads the kept record, not the '
        'downloaded file', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);

      await prepareDownloadedBook(
        VerifiedFile(file.uri, _digest(bytes)),
        _source('epub'),
      );
      // The kept record is the only source left: the file is no EPUB now.
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final opened = await _open(file, _digest(bytes), 'epub');

      expect(
        _facts(opened.publication),
        _facts(Publication.admit(bytes, _digest(bytes))),
      );
    });

    test('the first open of a prepared MOBI neither converts nor reads the '
        'file, and the conversion is kept', () async {
      final bytes = _books['pg11-kf8.mobi']!.$1;
      final file = await _download(bytes);

      await prepareDownloadedBook(
        VerifiedFile(file.uri, _digest(bytes)),
        _source('mobi'),
      );
      final converted = Directory('${file.parent.path}/.bookfin-mobi')
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('.epub'));
      expect(await converted.length, 1);
      await file.writeAsBytes(List.filled(bytes.length, 0));
      final opened = await _open(file, _digest(bytes), 'mobi');

      expect(opened.format, 'mobi');
      expect(opened.originalDigest, _digest(bytes));
    });

    for (final (container, bytes) in [
      ('epub', showcaseBooks()['showcase-frost']!),
      ('mobi', _books['pg11-kf8.mobi']!.$1),
    ]) {
      test('a $container that Downloads lent is prepared under its hold, and '
          'the hold stays out of the worker', () async {
        final file = await _download(bytes);
        // A list of futures cannot go to another isolate, so a worker that
        // captured the lent file would fail to start.
        final held = <Future<void>>[];
        final lent = VerifiedFile.lent(
          file.uri,
          _digest(bytes),
          hold: (work) {
            final done = work();
            held.add(done);
            return done;
          },
        );

        await prepareDownloadedBook(lent, _source(container));

        expect(held, isNotEmpty);
        expect(await _record(file).exists(), isTrue);
      });
    }

    test('a PDF needs no preparation', () async {
      final file = await _download(utf8.encode('%PDF-1.4 not parsed'));

      await prepareDownloadedBook(
        VerifiedFile(file.uri, 'digest'),
        _source(''),
      );

      expect(await file.parent.list().map((entry) => entry.path).toList(), [
        file.path,
      ]);
    });

    test('a book whose record is current is not admitted again', () async {
      final bytes = epub();
      final file = await _download(bytes);
      final log = File('${file.parent.path}/admissions');

      for (var round = 0; round < 2; round++) {
        await AdmittedBooks.prepare(
          VerifiedFile(file.uri, _digest(bytes)),
          'policy-1',
          _logged(log, bytes),
        );
      }

      expect(await log.readAsString(), 'admitted\n');
    });

    test('a book whose record has an older key, as after an update of the '
        'admission, is admitted again, and its next open reads it', () async {
      final bytes = epub();
      final file = await _download(bytes);
      final log = File('${file.parent.path}/admissions');
      final original = VerifiedFile(file.uri, _digest(bytes));
      await AdmittedBooks.prepare(original, 'policy-1', _logged(log, bytes));

      await AdmittedBooks.prepare(original, 'policy-2', _logged(log, bytes));
      await AdmittedBooks.load(
        original,
        'policy-2',
        _logged(log, bytes),
        (publication) => publication.identity,
      );

      expect(await log.readAsString(), 'admitted\nadmitted\n');
    });

    test('an open during a preparation waits for it, and does not admit the '
        'book again', () async {
      final bytes = showcaseBooks()['showcase-frost']!;
      final file = await _download(bytes);
      final log = File('${file.parent.path}/admissions');
      final original = VerifiedFile(file.uri, _digest(bytes));

      final preparing = AdmittedBooks.prepare(
        original,
        'policy-1',
        _logged(log, bytes),
      );
      final identity = await AdmittedBooks.load(
        original,
        'policy-1',
        _logged(log, bytes),
        (publication) => publication.identity,
      );
      await preparing;

      expect(identity, Publication.admit(bytes, _digest(bytes)).identity);
      expect(await log.readAsString(), 'admitted\n');
    });

    test(
      'a book whose preparation failed is not admitted again by the next '
      'preparation until its key changes, and its open still admits it',
      () async {
        final bytes = utf8.encode('not a zip archive');
        final file = await _download(bytes);
        final log = File('${file.parent.path}/admissions');
        final original = VerifiedFile(file.uri, _digest(bytes));

        await expectLater(
          AdmittedBooks.prepare(original, 'policy-1', _logged(log, bytes)),
          throwsA(anything),
        );
        await AdmittedBooks.prepare(original, 'policy-1', _logged(log, bytes));
        expect(await log.readAsString(), 'admitted\n');

        await expectLater(
          AdmittedBooks.prepare(original, 'policy-2', _logged(log, bytes)),
          throwsA(anything),
        );
        await expectLater(
          AdmittedBooks.load(
            original,
            'policy-2',
            _logged(log, bytes),
            (publication) => publication.identity,
          ),
          throwsA(anything),
        );
        expect(await log.readAsString(), 'admitted\nadmitted\nadmitted\n');
      },
    );

    test('a book that cannot be admitted fails its preparation and keeps no '
        'record', () async {
      final bytes = utf8.encode('not a zip archive');
      final file = await _download(bytes);

      await expectLater(
        prepareDownloadedBook(
          VerifiedFile(file.uri, _digest(bytes)),
          _source('epub'),
        ),
        throwsA(anything),
      );
      expect(await _record(file).exists(), isFalse);
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
        'pixels', () async {
      final publication = Publication.admit(_books['broken-image.epub']!.$1);

      expect(publication.imageSizes['OPS/plate.jpg'], (40, 30));
      expect(await publication.bytesOf('OPS/plate.jpg'), isNotNull);
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
        expect(publication.textFiles, isNot(contains('OPS/dot.png')));
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
            utf8.decode(publication.textFiles[publication.packagePath]!),
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

/// An admission of [bytes] that adds a line to [log] each time it runs. It
/// captures only a path and bytes, so it can run in a worker.
Future<Publication> Function() _logged(File log, List<int> bytes) {
  final path = log.path;
  final book = Uint8List.fromList(bytes);
  return () async {
    await File(path).writeAsString('admitted\n', mode: FileMode.append);
    return Publication.admit(book, _digest(book));
  };
}
