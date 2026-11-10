import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'pdf_viewport_test.dart' show DrawnPdf;
import 'session_reflow_test.dart' show otherBook;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalFiles downloads;

  ReaderSession session(ReadingStore store) {
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
    SharedPreferences.setMockInitialValues({});
    downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/text.pdf');
  });
  tearDown(() => downloads.dispose());

  for (final sqlite in [false, true]) {
    for (final view in PdfPageView.values) {
      test(
        '${sqlite ? 'SQLite' : 'preferences'} restores each book and account '
        'with $view without changing reading records',
        () async {
          String? path;
          RecordDatabase? database;
          if (sqlite) {
            final directory = await Directory.systemTemp.createTemp(
              'pdf-choices-',
            );
            addTearDown(() => directory.delete(recursive: true));
            path = '${directory.path}/records.sqlite';
            database = await RecordDatabase.open(
              factory: databaseFactoryFfi,
              path: path,
            );
          }
          final store = LocalResumeStore(
            openDatabase: database == null ? null : () async => database!,
          );
          final reader = session(store.reading);
          final key = account().scope.key;
          await reader.bind(account(), [book, otherBook]);
          await reader.open(book, edition);
          reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
          await reader.addBookmark(title: 'The river');
          await reader.flush();
          final records = (await store.reading.read(key))!;
          reader.setPdfView(PdfPageView.text);
          reader.setPdfView(view);
          await reader.setTrimMargins(false);
          await reader.flush();
          final changed = (await store.reading.read(key))!;
          for (final collection in ['resumes', 'bookmarks', 'history']) {
            expect(changed[collection], records[collection]);
          }
          await reader.open(otherBook, edition);
          reader.setPdfView(PdfPageView.pageWords);
          await reader.flush();
          await reader.bind(account(user: 'bob'), [book]);
          await reader.open(book, edition);
          reader.setPdfView(PdfPageView.text);
          await reader.flush();
          RecordDatabase? reopened;
          if (database != null) {
            await database.close();
            reopened = await RecordDatabase.open(
              factory: databaseFactoryFfi,
              path: path!,
            );
            addTearDown(reopened.close);
          }
          final restoredStore = LocalResumeStore(
            openDatabase: reopened == null ? null : () async => reopened!,
          );
          final restarted = session(restoredStore.reading);
          await restarted.bind(account(), [book, otherBook]);
          await restarted.open(book, edition);
          expect(restarted.pdfView, view);
          expect(restarted.trimMargins, isFalse);
          expect((restarted.initialAddress as PdfAddress).sourcePage, 2);
          expect(restarted.bookmarks.single.title, 'The river');
          expect(
            restarted.history.map((move) => move.toJson()),
            containsAll(records['history'] as List),
          );
          await restarted.open(otherBook, edition);
          expect(restarted.pdfView, PdfPageView.pageWords);
          expect(restarted.trimMargins, isTrue);
          await restarted.bind(account(user: 'bob'), [book]);
          await restarted.open(book, edition);
          expect(restarted.pdfView, PdfPageView.text);
          expect(restarted.trimMargins, isTrue);
          if (sqlite) await restoredStore.checkInvariants();
        },
      );
    }
  }

  test('legacy SQLite trim remains the fallback after one book saves its own choices', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-legacy-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(database.close);
    final store = LocalResumeStore(openDatabase: () async => database);
    await store.reading.write(account().scope.key, {
      'version': 1,
      'fontSize': 28,
      'trimMargins': false,
      'resumes': <dynamic>[],
      'bookmarks': <dynamic>[],
      'history': <dynamic>[],
    });
    final reader = session(store.reading);
    await reader.bind(account(), [book, otherBook]);
    await reader.open(book, edition);
    expect(reader.pdfView, PdfPageView.original);
    expect(reader.trimMargins, isFalse);
    reader.setPdfView(PdfPageView.text);
    await reader.setTrimMargins(true);
    await reader.flush();
    await database.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopened.close);
    final restarted = session(
      LocalResumeStore(openDatabase: () async => reopened).reading,
    );
    await restarted.bind(account(), [book, otherBook]);
    await restarted.open(book, edition);
    expect(restarted.pdfView, PdfPageView.text);
    expect(restarted.trimMargins, isTrue);
    expect(restarted.fontSize, 28);
    expect(restarted.sizesMainText, isTrue);
    await restarted.open(otherBook, edition);
    expect(restarted.pdfView, PdfPageView.original);
    expect(restarted.trimMargins, isFalse);
  });

  test('malformed SQLite PDF choices block writes without changing durable records', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-malformed-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(database.close);
    final store = LocalResumeStore(openDatabase: () async => database);
    final key = account().scope.key;
    final reader = session(store.reading);
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
    await reader.addBookmark(title: 'Keep this damaged snapshot');
    await reader.flush();
    await store.reading.write(key, {
      ...(await store.reading.read(key))!,
      'pdfBooks': {
        'work': {'view': 'unknown', 'trimMargins': false},
      },
    });
    final saved = jsonDecode((await database.read(key))!);
    await database.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopened.close);
    final restarted = session(
      LocalResumeStore(openDatabase: () async => reopened).reading,
    );
    await restarted.bind(account(), [book]);
    expect(restarted.message, contains('Existing records were kept'));
    await restarted.open(book, edition);
    restarted.setPdfView(PdfPageView.text);
    await restarted.setTrimMargins(false);
    await restarted.setFontSize(32);
    await restarted.flush();
    expect(jsonDecode((await reopened.read(key))!), saved);
  });

  test('a failed SQLite preference transaction preserves records and retries after an account change', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-save-retry-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final sql = await databaseFactoryFfi.openDatabase(path);
    final store = LocalResumeStore(openDatabase: () async => database);
    final reader = session(store.reading);
    final key = account().scope.key;
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
    await reader.addBookmark(title: 'Do not lose this place');
    await reader.flush();
    final saved = jsonDecode((await database.read(key))!);
    await sql.execute(
      "CREATE TRIGGER fail_pdf_settings BEFORE UPDATE ON record_accounts BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    reader.setPdfView(PdfPageView.text);
    await reader.setTrimMargins(false);
    await reader.flush();
    expect(reader.saveFailed, isTrue);
    expect(jsonDecode((await database.read(key))!), saved);
    await reader.bind(account(user: 'bob'), [book]);
    await reader.open(book, edition);
    expect(reader.pdfView, PdfPageView.original);
    expect(reader.trimMargins, isTrue);
    await sql.execute('DROP TRIGGER fail_pdf_settings');
    await reader.flush();
    await sql.close();
    await database.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopened.close);
    final restarted = session(
      LocalResumeStore(openDatabase: () async => reopened).reading,
    );
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.pdfView, PdfPageView.text);
    expect(restarted.trimMargins, isFalse);
    expect((restarted.initialAddress as PdfAddress).sourcePage, 2);
    expect(restarted.bookmarks.single.title, 'Do not lose this place');
    expect(
      (jsonDecode((await reopened.read(key))!) as Map)['sync'],
      (saved as Map)['sync'],
    );
  });
}
