import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'pdf_viewport_test.dart' show DrawnPdf;

const otherEdition = Edition(
  id: 'another-pdf-edition',
  kind: EditionKind.text,
  label: 'Another PDF',
  files: [pdfSource],
  memberIds: ['pdf'],
);
const otherBook = Book(
  id: 'other-work',
  title: 'Another PDF book',
  author: 'Writer',
  editions: [edition, otherEdition],
);

class FailingReadingStore extends MemoryResume {
  bool failSave = true;

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    if (failSave) throw Exception('Storage is full.');
    return super.saveReading(accountKey, changes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalFiles downloads;
  late MemoryResume store;

  ReaderSession session() {
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: loadPublication,
      loadDocument: (_, _) async => DrawnPdf(),
    );
    addTearDown(reader.dispose);
    return reader;
  }

  setUp(() {
    downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/text.pdf');
    store = MemoryResume();
  });

  tearDown(() => downloads.dispose());

  for (final view in PdfPageView.values) {
    test(
      '${view.name} and its trim choice belong to the book after restart',
      () async {
        final reader = session();
        await reader.bind(account(), [book, otherBook]);
        await reader.open(book, edition);
        expect(reader.pdfView, PdfPageView.original);
        reader.setPdfView(PdfPageView.text);
        reader.setPdfView(view);
        await reader.setTrimMargins(false);
        reader.closeView(reader.token);
        await reader.open(otherBook, edition);
        expect(reader.pdfView, PdfPageView.original);
        expect(reader.trimMargins, isTrue);
        reader.setPdfView(PdfPageView.pageWords);
        reader.closeView(reader.token);
        await reader.open(book, edition);
        expect(reader.pdfView, view);
        expect(reader.trimMargins, isFalse);
        await reader.flush();
        final restarted = session();
        await restarted.bind(account(), [book, otherBook]);
        await restarted.open(book, edition);
        expect(restarted.pdfView, view);
        expect(restarted.trimMargins, isFalse);
        await restarted.open(otherBook, otherEdition);
        expect(restarted.pdfView, PdfPageView.pageWords);
        expect(restarted.trimMargins, isTrue);
        reader.checkInvariants();
        restarted.checkInvariants();
      },
    );
  }

  test('the same book ID has separate PDF choices in each account', () async {
    final reader = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.setPdfView(PdfPageView.text);
    await reader.setTrimMargins(false);
    await reader.bind(account(user: 'bob'), [book]);
    await reader.open(book, edition);
    expect(reader.pdfView, PdfPageView.original);
    expect(reader.trimMargins, isTrue);
    reader.setPdfView(PdfPageView.pageWords);
    await reader.flush();
    final restarted = session();
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.pdfView, PdfPageView.text);
    expect(restarted.trimMargins, isFalse);
    await restarted.bind(account(user: 'bob'), [book]);
    await restarted.open(book, edition);
    expect(restarted.pdfView, PdfPageView.pageWords);
    expect(restarted.trimMargins, isTrue);
  });

  for (final legacyTrim in [true, false]) {
    test(
      'legacy trim $legacyTrim stays the fallback for an untouched book',
      () async {
        store.values[account().scope.key] = {
          'version': 1,
          'fontSize': 28,
          'trimMargins': legacyTrim,
          'resumes': <dynamic>[],
          'bookmarks': <dynamic>[],
          'history': <dynamic>[],
        };
        final reader = session();
        await reader.bind(account(), [book, otherBook]);
        await reader.open(book, edition);
        expect(reader.pdfView, PdfPageView.original);
        expect(reader.trimMargins, legacyTrim);
        await reader.setTrimMargins(!legacyTrim);
        reader.setPdfView(PdfPageView.text);
        await reader.flush();
        final restarted = session();
        await restarted.bind(account(), [book, otherBook]);
        await restarted.open(book, edition);
        expect(restarted.pdfView, PdfPageView.text);
        expect(restarted.trimMargins, !legacyTrim);
        expect(restarted.fontSize, 28);
        expect(restarted.sizesMainText, isTrue);
        await restarted.open(otherBook, edition);
        expect(restarted.pdfView, PdfPageView.original);
        expect(restarted.trimMargins, legacyTrim);
      },
    );
  }

  test(
    'a failed save retries choices for both books without losing records',
    () async {
      final failing = FailingReadingStore();
      store = failing;
      final reader = session();
      await reader.bind(account(), [book, otherBook]);
      await reader.open(book, edition);
      reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
      await reader.addBookmark(title: 'Kept place');
      final history = reader.history.map((move) => move.toJson()).toList();
      reader.setPdfView(PdfPageView.text);
      await reader.setTrimMargins(false);
      expect(reader.saveFailed, isTrue);
      await reader.open(otherBook, edition);
      reader.setPdfView(PdfPageView.pageWords);
      await reader.flush();
      expect(failing.values, isEmpty);
      failing.failSave = false;
      await reader.flush();
      expect(reader.saveFailed, isFalse);
      final restarted = session();
      await restarted.bind(account(), [book, otherBook]);
      await restarted.open(book, edition);
      expect(restarted.pdfView, PdfPageView.text);
      expect(restarted.trimMargins, isFalse);
      expect((restarted.initialAddress as PdfAddress).sourcePage, 2);
      expect(restarted.bookmarks.single.title, 'Kept place');
      expect(
        restarted.history.map((move) => move.toJson()),
        containsAll(history),
      );
      await restarted.open(otherBook, edition);
      expect(restarted.pdfView, PdfPageView.pageWords);
      expect(restarted.trimMargins, isTrue);
    },
  );

  for (final malformed in <Object?>[
    null,
    [],
    {'work': false},
    {
      'work': {'view': 'reflow', 'trimMargins': true},
    },
    {
      'work': {'view': 'text', 'trimMargins': 'false'},
    },
  ]) {
    test(
      'malformed PDF preferences $malformed cannot overwrite saved records',
      () async {
        final reader = session();
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
        await reader.addBookmark(title: 'Keep despite damaged preferences');
        await reader.flush();
        final saved = {
          ...store.values[account().scope.key]!,
          'pdfBooks': malformed,
        };
        store.values[account().scope.key] = saved;
        final restarted = session();
        await restarted.bind(account(), [book]);
        expect(restarted.message, contains('Existing records were kept'));
        await restarted.open(book, edition);
        restarted.setPdfView(PdfPageView.text);
        await restarted.setTrimMargins(false);
        await restarted.setFontSize(32);
        await restarted.flush();
        expect(store.values[account().scope.key], saved);
      },
    );
  }

  for (final view in [PdfPageView.pageWords, PdfPageView.text]) {
    testWidgets(
      'the first PDF viewport restores ${view.name} and trim after binding',
      (tester) async {
        final reader = session();
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        reader.setPdfView(view);
        await reader.setTrimMargins(false);
        await reader.flush();
        store.readGate = Completer<void>();
        final restarted = session();
        final binding = restarted.bind(account(), [book]);
        final opening = restarted.open(book, edition);
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(reader: restarted, onNightChanged: (_) {}),
          ),
        );
        expect(find.byType(PdfViewport), findsNothing);
        final usefulViews = <(PdfPageView, bool)>[];
        restarted.documentChanges.addListener(() {
          if (restarted.document != null) {
            usefulViews.add((restarted.pdfView, restarted.trimMargins));
          }
        });
        store.readGate!.complete();
        await binding;
        await opening;
        await tester.pump();
        final viewport = tester.widget<PdfViewport>(find.byType(PdfViewport));
        expect(viewport.view, view);
        expect(viewport.trimMargins, isFalse);
        expect(usefulViews, isNotEmpty);
        expect(usefulViews, everyElement((view, false)));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('choosing a PDF view notifies only its signal and preserves reading records', () async {
    final reader = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
    await reader.addBookmark(title: 'Kept while changing view');
    await reader.flush();
    final saved = Map.of(store.values);
    final counts = <String, int>{};
    void count(String name, Listenable signal) =>
        signal.addListener(() => counts[name] = (counts[name] ?? 0) + 1);
    count('pdfView', reader.pdfViewChanges);
    count('place', reader.placeChanges);
    count('document', reader.documentChanges);
    count('fontSize', reader.fontSizeChanges);
    count('session', reader);
    reader.setPdfView(PdfPageView.pageWords);
    reader.setPdfView(PdfPageView.pageWords);
    await reader.flush();
    expect(counts, {'pdfView': 1, 'session': 1});
    for (final collection in ['resumes', 'bookmarks', 'history']) {
      expect(
        store.values[account().scope.key]![collection],
        saved[account().scope.key]![collection],
      );
    }
    reader.setPdfView(PdfPageView.text);
    reader.setPdfView(PdfPageView.text);
    await reader.flush();
    expect(counts, {'pdfView': 2, 'session': 2});
    reader.setPdfView(PdfPageView.original);
    expect(counts, {'pdfView': 3, 'session': 3});
  });
}
