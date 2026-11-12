// The layout that one install of the app kept is never used after an update
// of the app. A change to how the reader lays out text, such as drawing a
// book's own fonts in the reader font (boo-iv7q), ships in an update, and
// Android gives the update a new install time. That time is part of the
// text engine fingerprint, which keys both the page maps and the kept page.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/kept_page.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_maps.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/kept_pages.dart';
import 'package:bookfin/sync/device.dart';
import 'package:flutter/services.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFont);
  const channel = MethodChannel('bookfin/device');

  /// Starts a new process of the install that Android installed or last
  /// updated at [installTime], in milliseconds since the epoch.
  void launch(int installTime) {
    forgetInstalledBuild();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'build'
              ? {'installTime': installTime, 'system': 'google/oriole/15'}
              : null,
        );
  }

  /// The fingerprint of the running process, as a release build gives it.
  Future<String?> engine() =>
      textEngineFingerprint(debug: false, locales: const [Locale('en', 'US')]);

  late File download;
  late VerifiedFile original;

  setUp(() async {
    final folder = await Directory.systemTemp.createTemp('bookfin-update-');
    addTearDown(() => folder.delete(recursive: true));
    download = await File('${folder.path}/complete').writeAsString('book');
    original = VerifiedFile(download.uri, 'a' * 64);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    forgetInstalledBuild();
  });

  test(
    'a page kept before an update of the app is not drawn after it',
    () async {
      final pages = runToEnd(
        prepareSections([section(prose(20))], readerPage).single,
      );
      addTearDown(() {
        for (final page in pages) {
          page.dispose();
        }
      });
      launch(1762700000000);
      await KeptPages(engine: engine)
          .write(original, _place, KeptPage.encode(pages[1])!);
      final before = await KeptPages(engine: engine).read(original, _place);
      addTearDown(() => before?.dispose());
      expect(before, isNotNull);

      launch(1762800000000);

      expect(await KeptPages(engine: engine).read(original, _place), isNull);
    },
  );

  test(
    'a page map kept before an update of the app is not read after it',
    () async {
      final sections = [
        KeptSection(
          const [PageStart(0, 0), PageStart(3, 0)],
          firsts: const [EpubPlace(0, 2, 0), EpubPlace(0, 9, 0)],
          visible: (starts: const [0, 900], length: 1800),
          complete: true,
        ),
      ];
      launch(1762700000000);
      await BookPageMaps(
        download,
        book: 'book-identity',
        engine: engine(),
      ).write(readerPage, sections);
      expect(
        await BookPageMaps(
          download,
          book: 'book-identity',
          engine: engine(),
        ).read(readerPage),
        isNotNull,
      );

      launch(1762800000000);

      expect(
        await BookPageMaps(
          download,
          book: 'book-identity',
          engine: engine(),
        ).read(readerPage),
        isNull,
      );
    },
  );
}
