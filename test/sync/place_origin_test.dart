import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixture.dart';
import 'phone.dart';

// A book can open at a place that another device saved. The reader then
// records a move from this phone's own last place, which the record store
// finds in its journal, with the name of the other device.

const _file = SourceFile(
  itemId: 'ebook',
  displayName: 'Middlemarch.epub',
  mediaSourceId: 'original',
  revision: 'revision',
  durationMs: null,
  container: 'epub',
  sizeBytes: 100,
);
const _edition = Edition(
  id: 'ebook',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [_file],
  memberIds: ['ebook'],
);

/// A reading place in [_edition] at the passage [quote].
Map<String, dynamic> _place(String quote) => {
  'edition': _edition.id,
  'source': _file.key,
  'revision': _file.revision,
  'anchor': jsonEncode({'cfi': '/6/4', 'quote': quote}),
};

/// The address of the saved place of [_edition].
final _resume = jsonEncode([
  'reading',
  'resumes',
  jsonEncode([_edition.id, _file.key, _file.revision]),
]);

ReadingChanges _at(String quote) => ReadingChanges(
  const {'version': 1, 'fontSize': 20.0},
  resumes: [_place(quote)],
);

/// The quote of [place], a reading place.
String? _quote(Place? place) => place is! TextPosition
    ? null
    : (jsonDecode(place.anchor) as Map<String, dynamic>)['quote'] as String;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SyncFixture server;
  late String account;
  setUp(() async {
    server = await SyncFixture.open();
    addTearDown(server.close);
    account = server.session.scope.key;
  });

  /// The actions on the server, as each device downloads them.
  List<Map<String, dynamic>> served() => [
    for (final object in server.objects.values)
      jsonDecode(object['Payload'] as String) as Map<String, dynamic>,
  ];

  /// Phone A, which saw every action on the server, reads on to [quote]
  /// and uploads that place, saved on the device [device].
  void phoneAReadsTo(String quote, {String? device = 'Phone A'}) =>
      server.publish(
        RecordJournal(account, 'phone-a')
          ..receive(served())
          ..change(_resume, _place(quote), device: device),
      );

  test('an edition that this phone never read has no own place, and no '
      'other device saved its place', () async {
    final phone = LocalResumeStore();

    final origin = await phone.reading.origin(account, _edition);

    expect(origin.own, isNull);
    expect(origin.elsewhere, isFalse);
  });

  test('a place that this phone saved is its own place, and no other device '
      'saved it', () async {
    final phone = LocalResumeStore();
    await phone.reading.saveReading(account, _at('Miss Brooke'));
    await phone.reading.saveReading(account, _at('Dorothea'));

    final origin = await phone.reading.origin(account, _edition);

    expect(_quote(origin.own), 'Dorothea');
    expect(origin.elsewhere, isFalse);
  });

  test('after a sync brings the place of another device, the phone keeps '
      'its own last place and names that device', () async {
    final phone = LocalResumeStore();
    await phone.reading.saveReading(account, _at('Miss Brooke'));
    await RecordTransport(phone).synchronize(server.session, server.client);
    phoneAReadsTo('Lydgate');
    await RecordTransport(phone).synchronize(server.session, server.client);

    final origin = await phone.reading.origin(account, _edition);

    expect(_quote(origin.own), 'Miss Brooke');
    expect(origin.elsewhere, isTrue);
    expect(origin.device, 'Phone A');
    final saved = (await phone.reading.read(account))!['resumes'] as List;
    expect(_quote(decodeTextPosition(saved.single)), 'Lydgate');
  });

  test(
    'a place from a device without a name still came from elsewhere',
    () async {
      final phone = LocalResumeStore();
      await phone.reading.saveReading(account, _at('Miss Brooke'));
      await RecordTransport(phone).synchronize(server.session, server.client);
      phoneAReadsTo('Lydgate', device: null);
      await RecordTransport(phone).synchronize(server.session, server.client);

      final origin = await phone.reading.origin(account, _edition);

      expect(origin.elsewhere, isTrue);
      expect(origin.device, isNull);
    },
  );

  test('the own last place stays after a restart', () async {
    final phone = await Phone.open('origin-restart');
    await phone.store.reading.saveReading(account, _at('Miss Brooke'));
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);
    phoneAReadsTo('Lydgate');
    await RecordTransport(phone.store)
        .synchronize(server.session, server.client);

    await phone.restart();
    final origin = await phone.store.reading.origin(account, _edition);

    expect(_quote(origin.own), 'Miss Brooke');
    expect(origin.device, 'Phone A');
    await phone.store.checkInvariants();
  });

  test('the move of a book that opened at another device\'s place names '
      'that device, and other moves name none', () {
    HistoryEvent<TextPosition> event({String? device}) => HistoryEvent(
      id: 'opened',
      at: DateTime.utc(2026, 11, 9, 21),
      kind: HistoryAction.open,
      before: decodeTextPosition(_place('Miss Brooke')),
      after: decodeTextPosition(_place('Lydgate')),
      bookTitle: 'Middlemarch',
      editionLabel: 'EPUB',
      device: device,
    );

    final named = HistoryEvent.fromJson(
      jsonDecode(jsonEncode(event(device: 'Phone A').toJson())),
      decodeTextPosition,
    );
    expect(named.device, 'Phone A');
    expect(event().toJson().containsKey('device'), isFalse);
    expect(
      () => HistoryEvent.fromJson({
        ...event().toJson(),
        'device': 8,
      }, decodeTextPosition),
      throwsA(anything),
    );
  });
}
