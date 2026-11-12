import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../downloads/verified_reads.dart';

const mobiSource = SourceFile(
  itemId: 'mobi',
  displayName: 'Book.mobi',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'mobi',
  sizeBytes: 1000,
);

void main() {
  for (final fixture in ['mobi6-plain', 'mobi6-palmdoc', 'pg11-kf8']) {
    test(
      'the production importer converts $fixture locally without changing original bytes',
      () async {
        final folder = await Directory.systemTemp.createTemp('bookfin-mobi-');
        addTearDown(() => folder.delete(recursive: true));
        final bytes = await File('tool/research/readers/fixtures/$fixture.mobi')
            .readAsBytes();
        final file = await File('${folder.path}/original.mobi')
            .writeAsBytes(bytes);
        final document = await loadReadingDocument(verified(file), mobiSource);
        addTearDown(document.dispose);
        expect(document.format, 'mobi');
        expect(document.originalDigest, sha256.convert(bytes).toString());
        final publication = (document as EpubDocument).publication;
        publication.checkInvariants();
        final text = publication.spine
            .map((path) => utf8.decode(publication.textFiles[path]!))
            .join();
        expect(text, contains(fixture == 'pg11-kf8' ? 'Alice' : 'The river'));
        expect(
          publication.mediaTypes.values.any(
            (type) => type.startsWith('image/'),
          ),
          isTrue,
        );
        expect(await file.readAsBytes(), bytes);
        final reopened = await loadReadingDocument(verified(file), mobiSource);
        expect(reopened.identity, document.identity);
        expect(reopened.originalDigest, document.originalDigest);
        await reopened.dispose();
        final cache = Directory('${folder.path}/.bookfin-mobi');
        final cached = await cache
            .list()
            .where((entry) => entry is Directory)
            .cast<Directory>()
            .single;
        await File('${cached.path}/book.epub')
            .writeAsString('damaged derived cache');
        final repaired = await loadReadingDocument(verified(file), mobiSource);
        expect(repaired.identity, document.identity);
        expect(repaired.originalDigest, document.originalDigest);
        expect(await file.readAsBytes(), bytes);
        await repaired.dispose();
      },
    );
  }

  test('malformed MOBI never replaces its original or publishes a successful cache', () async {
    final folder = await Directory.systemTemp.createTemp(
      'bookfin-mobi-rejected-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = await File('${folder.path}/broken.mobi')
        .writeAsString('not a MOBI book');
    await expectLater(
      loadReadingDocument(verified(file), mobiSource),
      throwsFormatException,
    );
    expect(await file.readAsString(), 'not a MOBI book');
    expect(
      await Directory('${folder.path}/.bookfin-mobi').list().toList(),
      isEmpty,
    );
  });
}
