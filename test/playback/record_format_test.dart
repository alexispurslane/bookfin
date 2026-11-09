import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart' show ReadingChanges;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Golden tests: the stored and synced JSON of each personal record that a
// release before reading history wrote. Every later build must write these
// bytes for the same record and read them back equal, because other devices
// and saved files hold them.

const _listeningEvent =
    '{"id":"event","at":"2026-11-09T21:40:00.000Z","kind":"seek",'
    '"before":{"edition":"edition","source":"source","revision":"revision","milliseconds":1000},'
    '"after":{"edition":"edition","source":"source","revision":"revision","milliseconds":61000},'
    '"bookTitle":"Middlemarch","editionLabel":"Recording"}';

const _listeningBookmark =
    '{"id":"mark","position":{"edition":"edition","source":"source","revision":"revision","milliseconds":15000},'
    '"createdAt":"2026-11-07T12:00:00.000Z","bookTitle":"Middlemarch","editionLabel":"Recording",'
    '"title":"Mark","note":null}';

const _readingBookmark =
    '{"id":"page","position":{"edition":"ebook","source":"file","revision":"revision",'
    r'"anchor":"{\"cfi\":\"/6/4\",\"quote\":\"Miss Brooke\"}"},'
    '"createdAt":"2026-11-07T12:00:00.000Z","title":null,"note":"Read again"}';

AudioPosition _audio(int milliseconds) => AudioPosition(
  editionId: 'edition',
  sourceKey: 'source',
  revision: 'revision',
  milliseconds: milliseconds,
);

final _event = ListeningEvent(
  id: 'event',
  at: DateTime.utc(2026, 11, 9, 21, 40),
  kind: ListeningAction.seek,
  before: _audio(1000),
  after: _audio(61000),
  bookTitle: 'Middlemarch',
  editionLabel: 'Recording',
);

final _mark = AudioBookmark(
  id: 'mark',
  position: _audio(15000),
  createdAt: DateTime.utc(2026, 11, 7, 12),
  bookTitle: 'Middlemarch',
  editionLabel: 'Recording',
  title: 'Mark',
);

final _page = TextBookmark(
  id: 'page',
  position: const TextPosition(
    editionId: 'ebook',
    sourceKey: 'file',
    revision: 'revision',
    anchor: '{"cfi":"/6/4","quote":"Miss Brooke"}',
  ),
  createdAt: DateTime.utc(2026, 11, 7, 12),
  note: 'Read again',
);

/// The value of the record at [address] in the saved journal of `alice`, as
/// the text that sync uploads.
Future<String> _savedValue(List<String> address) async {
  final preferences = await SharedPreferences.getInstance();
  final saved =
      jsonDecode(preferences.getString('bookfin.playback.v1.alice')!) as Map;
  final action = (saved['sync']['actions'] as List).lastWhere(
    (action) => action['record'] == jsonEncode(address),
  );
  return jsonEncode(action['value']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a listening event writes the bytes of earlier releases and reads them back equal', () {
    expect(jsonEncode(_event.toJson()), _listeningEvent);
    expect(
      jsonEncode(
        ListeningEvent.fromJson(
          jsonDecode(_listeningEvent) as Map<String, dynamic>,
        ).toJson(),
      ),
      _listeningEvent,
    );
  });

  test('a listening bookmark writes the bytes of earlier releases and reads them back equal', () {
    expect(jsonEncode(_mark.toJson()), _listeningBookmark);
    expect(
      jsonEncode(
        AudioBookmark.fromJson(
          jsonDecode(_listeningBookmark) as Map<String, dynamic>,
        ).toJson(),
      ),
      _listeningBookmark,
    );
  });

  test('a reading bookmark without book names writes the bytes of earlier releases and reads them back equal', () {
    expect(jsonEncode(_page.toJson()), _readingBookmark);
    expect(
      jsonEncode(
        TextBookmark.fromJson(
          jsonDecode(_readingBookmark) as Map<String, dynamic>,
        ).toJson(),
      ),
      _readingBookmark,
    );
  });

  test(
    'the store saves and syncs each record with the bytes of earlier releases',
    () async {
      final store = LocalResumeStore();
      await store.save(
        'alice',
        ListeningChanges(
          const {'version': 3},
          history: {'event': _event.toJson()},
          bookmarks: {'mark': _mark.toJson()},
        ),
      );
      await store.reading.saveReading(
        'alice',
        ReadingChanges(
          const {'version': 1},
          bookmarks: {'page': _page.toJson()},
        ),
      );

      expect(await _savedValue(['audio', 'history', 'event']), _listeningEvent);
      expect(
        await _savedValue(['audio', 'bookmarks', 'mark']),
        _listeningBookmark,
      );
      expect(
        await _savedValue(['reading', 'bookmarks', 'page']),
        _readingBookmark,
      );
    },
  );
}
