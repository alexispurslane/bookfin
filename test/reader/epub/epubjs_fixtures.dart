// What epub.js measured and saved while Bookfin still had it (ticket
// tc-pshi), and the native pages to hold it against. The fixtures in
// fixtures/ outlive epub.js; test/reader/epub/trial/fidelity_test.dart
// wrote them, and docs/research/native-epub-fidelity.md describes them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_epub_viewer/publication.dart';

import 'helpers.dart';

/// Whether the on-demand runs over the downloaded books are on.
final trialRun = Platform.environment['BOOKFIN_EPUB_TRIAL'] == '1';

/// The fixture file [name] of test/reader/epub/fixtures, decoded.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/reader/epub/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The text sizes, in pixels, at which epub.js measured each section.
const recordedSizes = [20, 23];

/// The reader's default page at text size [size].
PageSettings pageAt(int size) => PageSettings(
  width: readerPage.width,
  height: readerPage.height,
  fontSize: size.toDouble(),
  night: false,
);

/// The downloaded books in .cache/epub-trial/books, by the SHA-256 of their
/// file. Empty when the books are absent.
Map<String, Uint8List> downloadedBooks() {
  final directory = Directory('.cache/epub-trial/books');
  if (!directory.existsSync()) return {};
  final books = <String, Uint8List>{};
  for (final file in directory.listSync().whereType<File>()) {
    if (!file.path.endsWith('.epub')) continue;
    final bytes = file.readAsBytesSync();
    books[sha256.convert(bytes).toString()] = bytes;
  }
  return books;
}

/// A page source of [publication] whose layout steps run as soon as the
/// event loop allows, as they do between frames.
PageSource immediateSource(Publication publication) => PageSource(
  publication,
  schedule: (step, {required urgent}) => Timer.run(step),
);

/// [book], a downloaded book, as epub.js laid it out when it recorded the
/// fixtures: with automatic hyphenation turned off in each style sheet.
/// compare.cjs turned it off in Chromium, and the WebView reader never
/// hyphenated, because the sanitizer empties the Standard Ebooks sheets
/// that ask for it. Native pages can start where epub.js pages started
/// only without it.
Uint8List asRecorded(Uint8List book) {
  final archive = Archive();
  for (final file in ZipDecoder().decodeBytes(book).files) {
    archive.add(
      file.isFile && file.name.endsWith('.css')
          ? ArchiveFile.string(
              file.name,
              '${utf8.decode(file.content)}\n*{hyphens:manual!important}',
            )
          : file,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}
