import 'dart:convert';
import 'dart:io';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' as fixture;

void main() {
  for (final missingMetadata in [false, true]) {
    test(
      'verified EPUB files with missing metadata $missingMetadata reopen and reject tampering',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'bookfin-local-reader-',
        );
        final policy = MediaPolicy()..network = MediaNetwork.disconnected;
        final downloads = LocalDownloads(
          root: root,
          freeBytes: () async => 100000000,
          policy: policy,
        );
        final bytes = epub();
        final source = missingMetadata
            ? buildBooks([
                CatalogEntry.fromJson({
                  'Id': 'ebook',
                  'Type': 'Book',
                  'Name': 'River',
                  'Etag': 'revision-one',
                }, libraryId: 'books'),
              ]).single.editions.single.files.single
            : SourceFile(
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
        final book = Book(
          id: fixture.book.id,
          title: 'River',
          author: 'Writer',
          editions: [edition],
        );
        String hash(String value) =>
            sha256.convert(utf8.encode(value)).toString();
        final directory = Directory(
          '${root.path}/${hash(account().scope.key)}/${hash(jsonEncode([source.key, source.revision]))}',
        );
        await directory.create(recursive: true);
        final file = await File('${directory.path}/complete')
            .writeAsBytes(bytes);
        await File('${directory.path}/record.json').writeAsString(
          jsonEncode({
            'key': source.key,
            'revision': source.revision,
            'length': bytes.length,
            'digest': sha256.convert(bytes).toString(),
            'complete': true,
            'requested': false,
          }),
        );
        final store = MemoryResume();
        final reader = ReaderSession(
          downloads: downloads,
          store: store,
          load: loadPublication,
        );
        try {
          await downloads.bind(account(), [book]);
          await reader.bind(account(), [book]);
          await reader.open(book, edition);
          expect(reader.publication?.spine, ['OPS/one.xhtml']);
          reader.acceptVisible(reader.token, fixture.visible);
          await reader.flush();
          await reader.open(book, edition);
          expect(reader.initialLocation?.cfi, fixture.visible.cfi);
          await file.writeAsBytes([...bytes, 0]);
          await reader.open(book, edition);
          expect(reader.publication, isNull);
          expect(reader.message, contains('verified local files'));
          if (missingMetadata) {
            // A verified local file is not necessarily an EPUB.
            final invalid = utf8.encode('%PDF-1.7 not an EPUB');
            await file.writeAsBytes(invalid);
            await File('${directory.path}/record.json').writeAsString(
              jsonEncode({
                'key': source.key,
                'revision': source.revision,
                'length': invalid.length,
                'digest': sha256.convert(invalid).toString(),
                'complete': true,
                'requested': false,
              }),
            );
            await downloads.bind(null, []);
            await downloads.bind(account(), [book]);
            expect(await downloads.localFile(source), isNotNull);
            await reader.open(book, edition);
            expect(reader.publication, isNull);
            expect(reader.message, isNotEmpty);
          }
          reader.checkInvariants();
          downloads.checkInvariants();
        } finally {
          reader.dispose();
          downloads.dispose();
          await downloads.idle;
          policy.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
