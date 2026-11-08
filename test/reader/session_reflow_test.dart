import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'pdf_viewport_test.dart' show CountingPdf;

void main() {
  late LocalFiles downloads;
  late MemoryResume store;

  ReaderSession session() {
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: loadPublication,
      loadDocument: (_, _) async => CountingPdf(),
    );
    addTearDown(reader.dispose);
    return reader;
  }

  setUp(() {
    downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/text.pdf');
    store = MemoryResume();
  });

  tearDown(() => downloads.dispose());

  test('the reflow choice lasts while the reader closes and reopens, and a new '
      'session starts on the original page', () async {
    final reader = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect(reader.reflow, isFalse);
    reader.setReflow(true);
    expect(reader.reflow, isTrue);
    reader.closeView(reader.token);
    await reader.open(book, edition);
    expect(reader.reflow, isTrue);
    await reader.bind(account(user: 'bob'), [book]);
    expect(reader.reflow, isTrue, reason: 'The choice is for this run.');
    final restarted = session();
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.reflow, isFalse);
  });

  test(
    'choosing reflow notifies its own signal once and saves no reading record',
    () async {
      final reader = session();
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await reader.flush();
      final saved = Map.of(store.values);
      final counts = <String, int>{};
      void count(String name, Listenable signal) =>
          signal.addListener(() => counts[name] = (counts[name] ?? 0) + 1);
      count('reflow', reader.reflowChanges);
      count('place', reader.placeChanges);
      count('document', reader.documentChanges);
      count('fontSize', reader.fontSizeChanges);
      count('session', reader);
      reader.setReflow(true);
      reader.setReflow(true);
      await reader.flush();
      expect(counts, {'reflow': 1, 'session': 1});
      expect(store.values, saved);
      reader.setReflow(false);
      expect(counts, {'reflow': 2, 'session': 2});
    },
  );
}
