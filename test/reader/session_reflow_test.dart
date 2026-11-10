import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'pdf_viewport_test.dart' show DrawnPdf;

void main() {
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

  for (final view in [PdfPageView.pageWords, PdfPageView.text]) {
    test('${view.name} lasts across books and accounts, but a new run opens '
        'the original page', () async {
      const otherBook = Book(
        id: 'other-work',
        title: 'Another PDF book',
        author: 'Writer',
        editions: [edition],
      );
      final reader = session();
      await reader.bind(account(), [book, otherBook]);
      await reader.open(book, edition);
      expect(reader.pdfView, PdfPageView.original);
      reader.setPdfView(view);
      reader.closeView(reader.token);
      await reader.open(otherBook, edition);
      expect(reader.pdfView, view);
      reader.closeView(reader.token);
      await reader.open(book, edition);
      expect(reader.pdfView, view);
      await reader.bind(account(user: 'bob'), [book]);
      expect(reader.pdfView, view, reason: 'The choice is for this run.');
      final restarted = session();
      await restarted.bind(account(), [book]);
      await restarted.open(book, edition);
      expect(restarted.pdfView, PdfPageView.original);
    });
  }

  test(
    'choosing a PDF view notifies only its signal and saves no reading record',
    () async {
      final reader = session();
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
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
      expect(store.values, saved);
      reader.setPdfView(PdfPageView.text);
      reader.setPdfView(PdfPageView.text);
      await reader.flush();
      expect(counts, {'pdfView': 2, 'session': 2});
      expect(store.values, saved);
      reader.setPdfView(PdfPageView.original);
      expect(counts, {'pdfView': 3, 'session': 3});
    },
  );
}
