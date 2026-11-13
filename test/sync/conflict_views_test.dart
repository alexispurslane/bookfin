import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/sync/record_address.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _place(String domain, int step) => {
  'edition': 'edition',
  'source': 'source',
  'revision': 'revision',
  if (domain == 'audio') 'milliseconds': step * 1000,
  if (domain == 'reading') 'anchor': 'opaque-location-$step',
};

Map<String, dynamic> _value(String domain, String collection, int step) =>
    switch (collection) {
      'resumes' => _place(domain, step),
      'bookmarks' => {
        'id': 'item',
        'position': _place(domain, step),
        'createdAt': '2026-11-07T21:12:00Z',
        'bookTitle': 'Book',
        'editionLabel': 'Edition',
        'title': 'Title $step',
        'note': 'Note $step',
      },
      _ => {
        'id': 'item',
        'before': _place(domain, 0),
        'after': _place(domain, step),
        'at': '2026-11-07T21:12:00Z',
        'kind': 'seek',
        'bookTitle': 'Book',
        'editionLabel': 'Edition',
      },
    };

String _address(String domain, String collection) => jsonEncode([
  domain,
  collection,
  collection == 'resumes'
      ? jsonEncode(['edition', 'source', 'revision'])
      : 'item',
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final domain in ['audio', 'reading']) {
    for (final collection in ['resumes', 'bookmarks', 'history']) {
      test(
        '$domain $collection choices retain values and resolve from current originals',
        () async {
          final store = LocalResumeStore();
          final record = RecordAddress.parse(_address(domain, collection));
          final first = RecordJournal('alice', 'phone')
            ..change(record.encoded, _value(domain, collection, 1));
          final second = RecordJournal('alice', 'tablet')
            ..change(record.encoded, {
              ..._value(domain, collection, 2),
              'future': {
                'nested': [1, 2],
              },
            });
          await store.receivePage('alice', [
            ...first.uploads,
            ...second.uploads,
          ], 2);
          final views = await store.conflicts('alice');
          expect(views.keys, [record]);
          expect(views[record]!.map((version) => version.identity), [
            'action.phone.1',
            'action.tablet.1',
          ]);
          final value = views[record]!.last.value!;
          if (domain == 'audio') {
            expect((value.position as AudioPosition).milliseconds, 2000);
          } else {
            expect(
              (value.position as TextPosition).anchor,
              'opaque-location-2',
            );
          }
          switch (value) {
            case BookmarkValue(:final bookmark):
              expect((bookmark.title, bookmark.note), ('Title 2', 'Note 2'));
            case HistoryValue(:final event):
              expect(event.kind.name, 'seek');
            case ResumeValue():
              expect(collection, 'resumes');
          }
          expect(() => views.clear(), throwsUnsupportedError);
          expect(() => views[record]!.clear(), throwsUnsupportedError);
          final labels = labelConflict(
            record,
            views[record]!,
            books: [],
            now: DateTime.utc(2026, 11, 8),
            clock: (_) => '21:12',
          );
          expect(
            labels.kind,
            '${domain == 'audio' ? 'Listening' : 'Reading'} ${switch (collection) {
              'resumes' => 'saved place',
              'bookmarks' => 'bookmark',
              _ => 'history entry',
            }}',
          );
          expect(labels.choices.last.time, domain == 'audio' ? '0:02' : isNull);
          expect(
            labels.choices.last.detail,
            [
              if (domain == 'reading')
                'Saved reading place (preview unavailable)',
              if (collection == 'bookmarks') ...['Title 2', 'Note 2'],
            ].join(' · '),
          );
          expect(await store.conflicts('bob'), isEmpty);
          expect(
            await store.resolve('alice', record, 'action.tablet.1'),
            isTrue,
          );
          expect(
            await store.resolve('alice', record, 'action.phone.1'),
            isFalse,
          );
          final reopened = LocalResumeStore();
          expect(await reopened.conflicts('alice'), isEmpty);
          final uploaded = await reopened.pendingUploads('alice');
          expect(uploaded.last['record'], record.encoded);
          expect(uploaded.last['value'], {
            ..._value(domain, collection, 2),
            'future': {
              'nested': [1, 2],
            },
          });
          if (collection == 'resumes') {
            expect(
              uploaded.where(
                (action) =>
                    RecordAddress.parse(action['record'] as String)
                        .collection ==
                    'bookmarks',
              ),
              hasLength(2),
            );
          }
        },
      );

      test(
        '$domain $collection damage is rejected by validation and conflict projection',
        () {
          final record = _address(domain, collection);
          final value = _value(domain, collection, 1);
          final place = switch (collection) {
            'bookmarks' => value['position'] as Map,
            'history' => value['after'] as Map,
            _ => value,
          };
          place[domain == 'audio' ? 'milliseconds' : 'anchor'] = null;
          final action = <String, dynamic>{'record': record, 'value': value};
          expect(() => validateRecordAction(action), throwsFormatException);
          expect(
            () => recordConflicts({
              record: [action],
            }),
            throwsFormatException,
          );
        },
      );

      test(
        '$domain $collection deletion remains a choice and resolves durably',
        () async {
          final store = LocalResumeStore();
          final record = RecordAddress.parse(_address(domain, collection));
          final first = RecordJournal('alice', 'phone')
            ..change(record.encoded, _value(domain, collection, 1));
          final second = RecordJournal('alice', 'tablet')
            ..change(record.encoded, null);
          await store.receivePage('alice', [
            ...first.uploads,
            ...second.uploads,
          ], 2);
          final versions = (await store.conflicts('alice'))[record]!;
          expect(versions.last.value, isNull);
          final labels = labelConflict(
            record,
            versions,
            books: [],
            now: DateTime.utc(2026, 11, 8),
            clock: (_) => '21:12',
          );
          expect(labels.choices.last.detail, 'Keep deletion');
          expect(labels.track, isNull);
          expect(
            await store.resolve('alice', record, 'action.tablet.1'),
            isTrue,
          );
          final reopened = LocalResumeStore();
          expect(await reopened.conflicts('alice'), isEmpty);
          expect(
            (await reopened.pendingUploads('alice')).last['value'],
            isNull,
          );
        },
      );
    }
  }

  test('distinct legacy encodings keep distinct journal keys and resolution addresses', () async {
    const canonical = '["audio","bookmarks","item"]';
    const legacy = r' [ "audio", "bookmarks", "it\u0065m" ] ';
    final store = LocalResumeStore();
    final phone = RecordJournal('alice', 'phone')
      ..change(canonical, _value('audio', 'bookmarks', 1))
      ..change(legacy, _value('audio', 'bookmarks', 1));
    final tablet = RecordJournal('alice', 'tablet')
      ..change(canonical, _value('audio', 'bookmarks', 2))
      ..change(legacy, _value('audio', 'bookmarks', 2));
    await store.receivePage('alice', [...phone.uploads, ...tablet.uploads], 4);
    expect((await store.conflicts('alice')).keys, [
      RecordAddress.parse(canonical),
      RecordAddress.parse(legacy),
    ]);
    expect(
      await store.resolve(
        'alice',
        RecordAddress.parse(legacy),
        'action.tablet.2',
      ),
      isTrue,
    );
    expect((await store.conflicts('alice')).keys, [
      RecordAddress.parse(canonical),
    ]);
    expect((await store.pendingUploads('alice')).single['record'], legacy);
  });

  test(
    'a detached view stays unchanged when its input and journal advance',
    () async {
      final record = RecordAddress.parse(_address('reading', 'bookmarks'));
      final first = RecordJournal('alice', 'phone')
        ..change(record.encoded, _value('reading', 'bookmarks', 1));
      final second = RecordJournal('alice', 'tablet')
        ..change(record.encoded, _value('reading', 'bookmarks', 2));
      final originals = [...first.uploads, ...second.uploads];
      final view = recordConflicts({record.encoded: originals})[record]!;
      final store = LocalResumeStore();
      await store.receivePage('alice', originals, 2);
      (originals.last['value'] as Map)['title'] = 'Changed outside the store';
      ((originals.last['value'] as Map)['position'] as Map)['anchor'] =
          'changed-anchor';
      expect((view.last.value as BookmarkValue).bookmark.title, 'Title 2');
      expect(
        (view.last.value!.position as TextPosition).anchor,
        'opaque-location-2',
      );
      expect(view, (await store.conflicts('alice'))[record]);
      await store.resolve('alice', record, view.last.identity);
      expect(
        (await store.pendingUploads('alice')).single['value'],
        _value('reading', 'bookmarks', 2),
      );
      expect(view, hasLength(2));
      expect(
        (view.first.value!.position as TextPosition).anchor,
        'opaque-location-1',
      );
    },
  );

  test('future domains, collections and history kinds remain retained without selectable choices', () async {
    final store = LocalResumeStore();
    final phone = RecordJournal('alice', 'phone', null, validateRecordAction);
    final tablet = RecordJournal('alice', 'tablet', null, validateRecordAction);
    for (final record in [
      RecordAddress('future', 'resumes', 'item'),
      RecordAddress('reading', 'highlights', 'item'),
      RecordAddress('audio', 'history', 'item'),
      RecordAddress('reading', 'history', 'item'),
    ]) {
      final value = {
        'kind': 'future-move',
        'unknown': [1, 2],
      };
      phone.change(record.encoded, value);
      tablet.change(record.encoded, null);
    }
    final originals = [...phone.uploads, ...tablet.uploads];
    await store.receivePage('alice', originals, 8);
    expect(await store.conflicts('alice'), isEmpty);
    final reopened = LocalResumeStore();
    expect(await reopened.conflicts('alice'), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(preferences.getString('bookfin.playback.v1.alice')!) as Map;
    expect(saved['sync']['actions'], originals);
    await reopened.checkInvariants();
  });

  test(
    'legacy metadata fallbacks and opaque reading hints keep their labels',
    () {
      final record = _address('reading', 'resumes');
      final anchors = <String, String>{
        'opaque-anchor': 'Saved reading place (preview unavailable)',
        '[]': 'Saved reading place (preview unavailable)',
        '{"page":7,"quote":"  Words  "}': 'Source page 7 · “  Words  ”',
        '{"page":-1,"quote":42}':
            'Source page -1 · Saved reading place (preview unavailable)',
        '{"page":"7","quote":""}': 'Saved reading place (preview unavailable)',
      };
      for (final entry in anchors.entries) {
        final journal =
            RecordJournal('alice', 'phone', null, validateRecordAction)
              ..change(record, {
                ..._place('reading', 1),
                'anchor': entry.key,
                'createdAt': '2026-11-07T21:12:00Z',
              });
        final raw = journal.uploads.single;
        raw['device'] = '  ';
        raw['savedAt'] = 'not-a-date';
        final versions = recordConflicts({
          record: [raw],
        }).values.single;
        final labels = labelConflict(
          RecordAddress.parse(record),
          versions,
          books: [],
          now: DateTime.utc(2026, 11, 8),
          clock: (_) => '21:12',
        );
        expect(labels.choices.single.detail, entry.value);
        expect(labels.choices.single.source, 'Saved 21:12 yesterday');
      }
    },
  );
}
