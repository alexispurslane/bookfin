// Speech reads the words of a downloaded ebook in its own worker, outside
// Downloads' read of the download, so it writes nothing beside the
// download: a removal never races with it (t4-3o9f). Only the reader and
// the outline measurement, inside a read, keep admitted books and MOBI
// conversions.
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart' show VerifiedFile;
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_native_test.dart' show navBook;

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

  test('reads the words of an EPUB and writes nothing beside it', () async {
    final (original, source) = await download(
      navBook(['<p>Call me Ishmael.</p>'], const []),
      'epub',
    );
    final read = (await bookWordsReader(original, source))!;
    final words = (await read())!;
    expect(words.words, containsAllInOrder(['call', 'me', 'ishmael']));
    expect(besideTheDownload(), ['book.epub']);
  });

  group('a MOBI', () {
    final mobi = File('tool/research/readers/fixtures/pg11-kf8.mobi')
        .readAsBytesSync();

    test('that the reader did not convert yet gives speech no words, and '
        'nothing is written beside it', () async {
      final (original, source) = await download(mobi, 'mobi');
      final read = (await bookWordsReader(original, source))!;
      await expectLater(read(), throwsA(isA<FormatException>()));
      expect(besideTheDownload(), ['book.mobi']);
    });

    test('that the reader converted gives speech its words', () async {
      final (original, source) = await download(mobi, 'mobi');
      await measureDownloadedOutline(original, source);
      final kept = besideTheDownload();
      final read = (await bookWordsReader(original, source))!;
      expect((await read())!.words, contains('alice'));
      expect(besideTheDownload(), kept);
    });
  });
}
