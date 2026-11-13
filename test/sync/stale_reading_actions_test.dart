import 'dart:convert';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import '../reader/native_reader.dart' show twoChapterBook;
import '../reader/session_test.dart' show book, edition, source;
import 'batch_api_test.dart' show BatchApi;
import 'phone.dart';

/// Reports confirmed reading places, as the reader viewport does.
class _Navigator implements DocumentNavigator {
  _Navigator(this.reader);
  final ReaderSession reader;
  int displays = 0;
  @override
  void reportPendingPlace() {}
  @override
  Future<void> display(ReaderAddress address) async {
    displays++;
    reader.acceptAddress(reader.token, address);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final session = JellyfinSession(
    scope: account().scope,
    token: 'test',
    username: 'Alice',
    canDownload: true,
  );
  final key = session.scope.key;
  late Phone phone;
  late ReaderSession reader;
  late LocalFiles downloads;
  late _Navigator navigator;
  late BatchApi api;
  late JellyfinClient client;
  late RecordJournal remote;
  late String bookmarkId;
  late String historyId;
  int opens = 0;
  var disposed = false;

  Future<void> synchronize() =>
      RecordTransport(phone.store).synchronize(session, client);

  Future<void> deleteRemotely(String collection, String id) async {
    remote.change(jsonEncode(['reading', collection, id]), null);
    for (final action in remote.uploads) {
      api.put(RecordJournal.identity(action), jsonEncode(action));
    }
    await synchronize();
    await reader.refreshPersonalRecords();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = BatchApi();
    client = JellyfinClient(
      session.scope.server,
      deviceId: 'stale-reading',
      transport: api,
    );
    phone = await Phone.open('stale-reading');
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    opens = 0;
    disposed = false;
    reader = ReaderSession(
      downloads: downloads,
      store: phone.store.reading,
      load: (_) async {
        opens++;
        return twoChapterBook();
      },
    );
    await reader.bind(session, [book]);
    await reader.open(book, edition);
    reader.acceptVisible(
      reader.token,
      const VisibleLocation(
        'epubcfi(/6/2!/4/2/1:0)',
        'OPS/text/s0.xhtml',
        'One',
      ),
    );
    navigator = _Navigator(reader);
    reader.attachDocument(reader.token, navigator, const []);
    await reader.addBookmark(title: 'Reading mark');
    bookmarkId = reader.bookmarks.single.id;
    historyId = reader.history.first.id;
    // Leave the saved bookmark behind and create an Undo offer that deletion
    // of the earlier open event must not discard.
    reader.acceptVisible(
      reader.token,
      const VisibleLocation(
        'epubcfi(/6/4!/4/2/1:0)',
        'OPS/text/s1.xhtml',
        'Two',
      ),
    );
    await reader.restoreBookmark(bookmarkId);
    await reader.flush();
    expect(reader.undoOffer, isNotNull);
    await synchronize();
    remote = RecordJournal(key, 'other-reader')
      ..receive(
        api.objects.values.map(
          (object) =>
              jsonDecode(object['Payload'] as String) as Map<String, dynamic>,
        ),
      );
  });

  tearDown(() async {
    if (!disposed) reader.dispose();
    await reader.flush();
    downloads.dispose();
    client.close();
  });

  for (final action in [
    'history before',
    'history after',
    'bookmark restore',
    'bookmark edit',
  ]) {
    test(
      'a stale reading $action does nothing after sync deletes its record',
      () async {
        final history = action.startsWith('history');
        final collection = history ? 'history' : 'bookmarks';
        final id = history ? historyId : bookmarkId;
        await deleteRemotely(collection, id);
        final saved = await phone.store.reading.read(key);
        final pending = await phone.store.pendingUploads(key);
        final position = encodeTextPosition(reader.position!);
        final undo = reader.undoOffer!.action.id;
        final displays = navigator.displays;
        final opened = opens;

        await switch (action) {
          'history before' => reader.restoreHistory(id),
          'history after' => reader.restoreHistory(id, previous: false),
          'bookmark restore' => reader.restoreBookmark(id),
          _ => reader.editBookmark(id, title: 'Too late', note: 'Stale note'),
        };

        expect(encodeTextPosition(reader.position!), position);
        expect(navigator.displays, displays);
        expect(opens, opened);
        expect(reader.undoOffer?.action.id, undo);
        expect(reader.message, isNull);
        expect(reader.saveFailed, isFalse);
        expect(await phone.store.reading.read(key), saved);
        expect(await phone.store.pendingUploads(key), pending);
        expect(
          (saved![collection] as List).map((value) => value['id']),
          isNot(contains(id)),
        );
        await reader.addBookmark(title: 'Still works');
        expect(
          reader.bookmarks.map((mark) => mark.title),
          contains('Still works'),
        );
        reader.checkInvariants();
        reader.dispose();
        disposed = true;
        await reader.flush();
        await phone.restart();
        final restarted = (await phone.store.reading.read(key))!;
        expect(
          (restarted[collection] as List).map((value) => value['id']),
          isNot(contains(id)),
        );
      },
    );
  }

  test('stale reading actions after account replacement cannot change either account', () async {
    await reader.bind(account(user: 'bob'), [book]);
    final alice = await phone.store.reading.read(key);
    final bobKey = account(user: 'bob').scope.key;
    final bob = await phone.store.reading.read(bobKey);
    final opened = opens;
    await reader.restoreHistory(historyId);
    await reader.restoreBookmark(bookmarkId);
    await reader.editBookmark(bookmarkId, title: 'Wrong account');
    expect(reader.position, isNull);
    expect(reader.history, isEmpty);
    expect(reader.bookmarks, isEmpty);
    expect(reader.message, isNull);
    expect(opens, opened);
    expect(await phone.store.reading.read(key), alice);
    expect(await phone.store.reading.read(bobKey), bob);
    await reader.bind(session, [book]);
    await reader.open(book, edition);
    expect(reader.bookmarks.single.title, 'Reading mark');
  });

  testWidgets(
    'the reading editor completes normally when sync deletes its bookmark while it is open',
    (tester) async {
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: ReaderScope(
            reader: reader,
            show: (_) {},
            child: Builder(
              builder: (context) {
                page = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      openHistory(page, null, book: book, showing: EditionKind.text);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading mark', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Edit bookmark'), findsOneWidget);
      await tester.runAsync(() => deleteRemotely('bookmarks', bookmarkId));
      await tester.pumpAndSettle();
      expect(reader.bookmarks, isEmpty);
      final history = reader.history;
      final undo = reader.undoOffer?.action.id;
      final position = encodeTextPosition(reader.position!);
      final displays = navigator.displays;
      final pending = await tester.runAsync(
        () => phone.store.pendingUploads(key),
      );
      await tester.enterText(find.byType(TextField).first, 'Too late');
      await tester.tap(find.text('Save bookmark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Edit bookmark'), findsNothing);
      expect(reader.bookmarks, isEmpty);
      expect(reader.history, history);
      expect(reader.undoOffer?.action.id, undo);
      expect(encodeTextPosition(reader.position!), position);
      expect(navigator.displays, displays);
      expect(reader.message, isNull);
      await tester.runAsync(() async {
        expect((await phone.store.reading.read(key))!['bookmarks'], isEmpty);
        expect(await phone.store.pendingUploads(key), pending);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
