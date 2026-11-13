// Speech reads the words of a downloaded ebook in its own worker, outside
// Downloads' read of the download, so it writes nothing beside the
// download: a removal never races with it (t4-3o9f). Only Downloads'
// preparation, the reader and the outline measurement, under a hold of the
// download, keep admitted books and MOBI conversions.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart' show VerifiedFile;
import 'package:bookfin/reader/admitted_books.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/speech/book_search.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_native_test.dart' show navBook;

Future<BookWords> inWorker(ReadBook read) async {
  final search = BookSearch();
  try {
    return (await search.withBook('ebook:r1', read, (words) => words))!;
  } finally {
    await search.close();
  }
}

void main() {
  late Directory folder;
  setUp(() async => folder = await Directory.systemTemp.createTemp());
  tearDown(() => folder.delete(recursive: true));

  Future<(VerifiedFile, SourceFile)> download(
    Uint8List bytes,
    String container,
  ) async {
    final file = File('${folder.path}/book.$container');
    await file.writeAsBytes(bytes);
    return (
      VerifiedFile(file.uri, sha256.convert(bytes).toString()),
      SourceFile(
        itemId: 'ebook',
        displayName: 'Book',
        mediaSourceId: 'original',
        revision: 'r1',
        durationMs: null,
        container: container,
        sizeBytes: bytes.length,
      ),
    );
  }

  List<String> besideTheDownload() => [
    for (final entry in folder.listSync())
      entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
  ]..sort();

  final emptyOutline = TextOutline(parts: [], entries: []);

  test('reads the words of an EPUB and writes nothing beside it', () async {
    final bytes = navBook(['<p>Call me Ishmael.</p>'], const []);
    final (original, source) = await download(bytes, 'epub');
    final outline = measureTextOutline(Publication.admit(bytes));
    final port = ReceivePort();
    addTearDown(port.close);
    final lent = VerifiedFile.lent(
      original.uri,
      original.digest,
      hold: (_) {
        // A ReceivePort cannot travel to a worker. The factory must capture
        // only the path, digest and outline, never this lent file or its hold.
        port.sendPort.send('unexpected hold');
        throw StateError('Speech does not hold a download for a write.');
      },
    );
    final read = (await bookWordsReader(lent, source, outline))!;
    final words = (await inWorker(read));
    expect(words.words, containsAllInOrder(['call', 'me', 'ishmael']));
    expect(besideTheDownload(), ['book.epub']);
  });

  group('a MOBI', () {
    final mobi = File('tool/research/readers/fixtures/pg11-kf8.mobi')
        .readAsBytesSync();

    test('that the reader did not convert yet gives speech no words, and '
        'nothing is written beside it', () async {
      final (original, source) = await download(mobi, 'mobi');
      final read = (await bookWordsReader(original, source, emptyOutline))!;
      await expectLater(inWorker(read), throwsA(isA<FormatException>()));
      expect(besideTheDownload(), ['book.mobi']);
    });

    test('that Downloads prepared gives speech its words', () async {
      final (original, source) = await download(mobi, 'mobi');
      await prepareDownloadedBook(original, source);
      final outline = await measureDownloadedOutline(original, source);
      await AdmittedBooks.written(File.fromUri(original.uri));
      final kept = besideTheDownload();
      final read = (await bookWordsReader(original, source, outline))!;
      expect((await inWorker(read)).words, contains('alice'));
      expect(besideTheDownload(), kept);
    });

    test('that the reader converted gives speech its words', () async {
      final (original, source) = await download(mobi, 'mobi');
      final outline = await measureDownloadedOutline(original, source);
      // The admitted record is written after the outline comes back. In the
      // app, Downloads holds the download until then.
      await AdmittedBooks.written(File.fromUri(original.uri));
      final kept = besideTheDownload();
      final read = (await bookWordsReader(original, source, outline))!;
      expect((await inWorker(read)).words, contains('alice'));
      expect(besideTheDownload(), kept);
    });
  });

  test('a reopened EPUB worker uses the supplied back-matter boundary and writes nothing', () async {
    final (original, source) = await download(
      navBook(
        [
          '<p>Call me Ishmael some years ago never mind how long precisely.</p>',
          '<p>Quoted here.</p>',
        ],
        [('Loomings', 'text/s0.xhtml'), ('Endnotes', 'text/s1.xhtml')],
      ),
      'epub',
    );
    await prepareDownloadedBook(original, source);
    final outline = await measureDownloadedOutline(original, source);
    await AdmittedBooks.written(File.fromUri(original.uri));
    final before = <String, String>{
      for (final file in folder.listSync(recursive: true).whereType<File>())
        file.path: sha256.convert(file.readAsBytesSync()).toString(),
    };
    final read = (await bookWordsReader(original, source, outline))!;
    final words = await inWorker(read);
    expect(words.bodyEnd, 11);
    expect(words.words[words.bodyEnd], 'quoted');
    // A caller's outline without a back-matter entry must search the whole
    // book. Remeasuring the publication here would wrongly exclude it.
    final unabridged = TextOutline(parts: outline.parts, entries: []);
    final all = await inWorker(
      (await bookWordsReader(original, source, unabridged))!,
    );
    expect(all.bodyEnd, 13);
    expect(all.words, words.words);
    expect(all.offsets, words.offsets);
    expect({
      for (final file in folder.listSync(recursive: true).whereType<File>())
        file.path: sha256.convert(file.readAsBytesSync()).toString(),
    }, before);
  });
}
