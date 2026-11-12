// The kept pages of downloads: one file beside each download that holds
// the drawn form of the last page that the reader showed of it, keyed by
// everything that changes that page (boo-sy2d). A read with any other key
// gives nothing, so a reopen never draws a page that is not the true one.
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/kept_page.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/kept_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import 'epub/helpers.dart';
import 'epub/layout_run_test.dart' show runToEnd;

const _place = TextPosition(
  editionId: 'edition',
  sourceKey: 'item:original',
  revision: 'revision-one',
  anchor: '{"cfi":"epubcfi(/6/4!/4/2/1:0)"}',
);

void main() {
  setUpAll(loadReaderFont);

  late Directory folder;
  late File download;
  late VerifiedFile original;
  late List<LaidPage> pages;
  final stores = KeptPages(engine: () async => 'engine-one');

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('bookfin-kept-pages-');
    download = await File('${folder.path}/complete').writeAsString('book');
    original = VerifiedFile(download.uri, 'a' * 64);
    pages = runToEnd(prepareSections([section(prose(20))], readerPage).single);
  });

  tearDown(() async {
    for (final page in pages) {
      page.dispose();
    }
    await folder.delete(recursive: true);
  });

  /// The one kept page file of the download.
  File keptFile() => File('${folder.path}/.bookfin-layout/last-page');

  test('a kept page reads back at the same place of the same download and '
      'text engine, and draws that page', () async {
    await stores.write(original, _place, KeptPage.encode(pages[1])!);

    final kept = await stores.read(original, _place);
    addTearDown(() => kept?.dispose());

    expect(kept, isNotNull);
    expect(kept!.depicts(pages[1]), isTrue);
  });

  for (final (name, other) in [
    (
      'another place',
      (VerifiedFile file) => (
        file,
        const TextPosition(
          editionId: 'edition',
          sourceKey: 'item:original',
          revision: 'revision-one',
          anchor: '{"cfi":"epubcfi(/6/4!/4/8/1:0)"}',
        ),
        'engine-one',
      ),
    ),
    (
      'another revision of the source',
      (VerifiedFile file) => (
        file,
        const TextPosition(
          editionId: 'edition',
          sourceKey: 'item:original',
          revision: 'revision-two',
          anchor: '{"cfi":"epubcfi(/6/4!/4/2/1:0)"}',
        ),
        'engine-one',
      ),
    ),
    (
      'another downloaded file',
      (VerifiedFile file) =>
          (VerifiedFile(file.uri, 'b' * 64), _place, 'engine-one'),
    ),
    (
      'another text engine, as after an update of the app or the system',
      (VerifiedFile file) => (file, _place, 'engine-two'),
    ),
  ]) {
    test('a kept page reads as nothing at $name', () async {
      await stores.write(original, _place, KeptPage.encode(pages[1])!);
      final (file, place, engine) = other(original);

      final kept = await KeptPages(engine: () async => engine)
          .read(file, place);

      expect(kept, isNull);
    });
  }

  test('a process without a text-engine fingerprint, as a debug build, keeps '
      'no page and reads none', () async {
    final unknown = KeptPages(engine: () async => null);
    await stores.write(original, _place, KeptPage.encode(pages[1])!);

    await unknown.write(original, _place, KeptPage.encode(pages[2])!);
    expect(await unknown.read(original, _place), isNull);
    final kept = await stores.read(original, _place);
    addTearDown(() => kept?.dispose());
    expect(kept!.depicts(pages[1]), isTrue);
  });

  test(
    'a damaged file reads as nothing, and the next write replaces it',
    () async {
      await stores.write(original, _place, KeptPage.encode(pages[1])!);
      final bytes = await keptFile().readAsBytes();
      // A letter of the page's text that changed, which still decodes.
      final letter = String.fromCharCodes(bytes).lastIndexOf('shoreline');
      for (final damaged in [
        bytes.sublist(0, bytes.length - 40),
        [...bytes.sublist(0, bytes.length - 3), 0x20, 0x20, 0x20],
        [...bytes.sublist(0, letter), 0x6f, ...bytes.sublist(letter + 1)],
        <int>[],
      ]) {
        await keptFile().writeAsBytes(damaged);
        expect(await stores.read(original, _place), isNull);
      }

      await stores.write(original, _place, KeptPage.encode(pages[2])!);
      final kept = await stores.read(original, _place);
      addTearDown(() => kept?.dispose());
      expect(kept!.depicts(pages[2]), isTrue);
    },
  );

  test('a write holds the download, so that a removal waits for it', () async {
    final held = <Future<void>>[];
    final lent = VerifiedFile.lent(
      download.uri,
      'a' * 64,
      hold: (work) {
        final done = work();
        held.add(done);
        return done;
      },
    );

    await stores.write(lent, _place, KeptPage.encode(pages[1])!);

    expect(held, hasLength(1));
    expect(await keptFile().exists(), isTrue);
  });

  test('a page that a newer write replaced reads as the newer page', () async {
    await stores.write(original, _place, KeptPage.encode(pages[1])!);
    const later = TextPosition(
      editionId: 'edition',
      sourceKey: 'item:original',
      revision: 'revision-one',
      anchor: '{"cfi":"epubcfi(/6/4!/4/10/1:0)"}',
    );

    await stores.write(original, later, KeptPage.encode(pages[2])!);

    expect(await stores.read(original, _place), isNull);
    final kept = await stores.read(original, later);
    addTearDown(() => kept?.dispose());
    expect(kept!.depicts(pages[2]), isTrue);
  });
}
