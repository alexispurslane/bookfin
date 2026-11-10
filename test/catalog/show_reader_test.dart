import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../foundation_test.dart' show disconnectedCatalog;
import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import '../reader/native_reader.dart';
import '../reader/session_test.dart' show book, edition, source;

// The library brings the one reader screen to the front: a new screen when
// the reader shows no book, and the screen under the page otherwise, so one
// reader session never has two screens.

class _MemoryLayoutStore implements LayoutStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() {
  testWidgets('the reader comes to the front once: a new screen at first, '
      'and the same screen from a page above it', (tester) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    addTearDown(downloads.dispose);
    final opened = twoChapterBook();
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => opened,
    );
    await reader.bind(account(), [book]);
    final layout = LibraryLayout(_MemoryLayoutStore());
    addTearDown(layout.dispose);
    final services = LibraryServices(
      catalog: disconnectedCatalog(),
      layout: layout,
      onReaderNightChanged: (_) {},
      reader: reader,
    );
    addTearDown(services.catalog.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: services.pageScope(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                ReaderScope.maybeOf(context)!.show(context);
                reader.open(book, edition);
              },
              child: const Text('Read'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Read'));
    await waitForPage(tester, reader);
    expect(find.byType(ReaderScreen), findsOneWidget);

    // A page over the reader, such as the book page from the player.
    final above = tester.element(find.byType(ReaderScreen));
    Navigator.of(above).push<void>(
      MaterialPageRoute(
        builder: (_) => services.pageScope(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ReaderScope.maybeOf(context)!.show(context),
              child: const Text('Back to the reader'),
            ),
          ),
        ),
      ),
    );
    await settleReader(
      tester,
      () => find.text('Back to the reader').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Back to the reader'));
    await settleReader(
      tester,
      () => find.text('Back to the reader').evaluate().isEmpty,
    );

    expect(find.byType(ReaderScreen, skipOffstage: false), findsOneWidget);
    expect(reader.book, book);
    await closeNative(tester, reader);
  });
}
