import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

void main() {
  testWidgets(
    'chapter and progress follow visible pages, including after restore',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      final port = ControlPort();
      reader.attach(reader.token, port, []);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      expect(find.textContaining('Page progress unavailable'), findsOneWidget);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 2,
          'pages': 8,
        }),
      );
      await reader.addBookmark(title: 'River mark');
      final bookmark = reader.bookmarks.single;
      await tester.pumpAndSettle();
      expect(find.text('River heading · Page 2 of 8'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .25,
      );
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'The bridge',
          'page': 3,
          'pages': 4,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('The bridge · Page 3 of 4'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
      await reader.restoreBookmark(bookmark.id);
      await tester.pumpAndSettle();
      expect(port.destinations.single.cfi, visible.cfi);
      expect(find.text('The bridge · Page 3 of 4'), findsOneWidget);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 1,
          'pages': 5,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('River heading · Page 1 of 5'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .2,
      );
      reader.acceptVisible(reader.token, visible);
      await tester.pumpAndSettle();
      expect(find.textContaining('Page progress unavailable'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  /// Opens the reader on [book] at a visible place, with one untitled
  /// bookmark there, and shows its bookmarks panel.
  Future<ReaderSession> openBookmarks(WidgetTester tester) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => Publication.admit(epub()),
    );
    addTearDown(() {
      reader.dispose();
      downloads.dispose();
    });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.attach(reader.token, ControlPort(), []);
    reader.acceptVisible(reader.token, visible);
    await reader.addBookmark();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading bookmarks'));
    await tester.pumpAndSettle();
    return reader;
  }

  testWidgets(
    'an untitled reading bookmark names the day and time it was saved',
    (tester) async {
      final reader = await openBookmarks(tester);
      final saved = reader.bookmarks.single.createdAt.toLocal();
      final time = const DefaultMaterialLocalizations().formatTimeOfDay(
        TimeOfDay.fromDateTime(saved),
      );
      expect(find.text('Today, $time'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('deleting a reading bookmark asks first and Cancel keeps it', (
    tester,
  ) async {
    final reader = await openBookmarks(tester);
    Future<void> askToDelete() async {
      await tester.tap(find.byTooltip('Edit reading bookmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete reading bookmark?'), findsOneWidget);
    }

    await askToDelete();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(reader.bookmarks, hasLength(1));

    await askToDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(reader.bookmarks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'production reading controls save a bookmark and change text size',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      reader.attach(reader.token, ControlPort(), [
        const ContentsEntry('River heading', 'one.xhtml#start'),
      ]);
      reader.acceptVisible(reader.token, visible);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
      expect(reader.fontSize, 22);
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.pumpAndSettle();
      expect(reader.bookmarks, hasLength(1));
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('River heading'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'incomplete search is visible and large controls do not overflow',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      reader.attach(reader.token, ControlPort(), []);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'river');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        find.text('Search is incomplete. Chapter failed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

class ControlPort implements NavigatorPort {
  final destinations = <ReadingLocation>[];
  @override
  Future<void> cancelSearch(int request) async {}
  @override
  Future<void> configure({
    required double fontSize,
    required bool night,
  }) async {}
  @override
  Future<void> contents(String href) async {}
  @override
  Future<void> display(ReadingLocation location) async {
    destinations.add(location);
  }

  @override
  Future<void> move(bool forward) async {}
  @override
  Future<SearchReport> search(String query, int request) async =>
      const SearchReport([], error: 'Search is incomplete. Chapter failed.');
}
