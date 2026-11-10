// A book can open at a listening place that another device saved. The
// player then records a move from this phone's own last place, which the
// record store finds in its journal, with the name of the other device, and
// offers Undo. The reader follows the same rule (see
// test/reader/reading_moves_test.dart).
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;

import '../sync/fixture.dart';
import '../sync/phone.dart';
import 'playback_test.dart' show LocalFiles, TestEngine;

const _minute = 60 * 1000;

/// A two-hour recording in one file.
const _file = SourceFile(
  itemId: 'tide',
  displayName: 'The tide',
  mediaSourceId: 'tide-source',
  revision: 'r1',
  durationMs: 120 * _minute,
  container: 'wav',
  sizeBytes: 42,
);
const _edition = Edition(
  id: 'tide-audio',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [_file],
  memberIds: ['tide:tide-source'],
);
const _book = Book(
  id: 'tide',
  title: 'The tide',
  author: 'A. Writer',
  editions: [_edition],
);

/// A second recording, which this phone listens to in between.
const _otherFile = SourceFile(
  itemId: 'frost',
  displayName: 'Frost',
  mediaSourceId: 'frost-source',
  revision: 'r1',
  durationMs: 60 * _minute,
  container: 'wav',
  sizeBytes: 42,
);
const _otherEdition = Edition(
  id: 'frost-audio',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [_otherFile],
  memberIds: ['frost:frost-source'],
);
const _other = Book(
  id: 'frost',
  title: 'Frost',
  author: 'B. Writer',
  editions: [_otherEdition],
);

/// One phone with its own record store and player.
class _Phone {
  _Phone(this.records) {
    playback = Playback(downloads: downloads, engine: engine, store: store);
  }

  /// The phone's own record file.
  final Phone records;
  LocalResumeStore get store => records.store;
  final downloads = LocalFiles()
    ..files[_file.key] = Uri.file('/tide.wav')
    ..files[_otherFile.key] = Uri.file('/frost.wav');
  final engine = TestEngine();
  late Playback playback;

  /// Listens to [book] up to [minutes] into it, and saves the place.
  Future<void> listenTo(Book book, int minutes) async {
    await playback.open(book, book.editions.single, autoplay: false);
    await playback.seekEdition(minutes * _minute);
    await playback.flush();
  }

  /// The minutes of [place] into the recording.
  static int minutesOf(AudioPosition place) => place.milliseconds ~/ _minute;

  Future<void> close() async {
    await playback.close();
    downloads.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SyncFixture server;
  late _Phone phoneA;
  late _Phone phoneB;
  setUp(() async {
    server = await SyncFixture.open();
    addTearDown(server.close);
    phoneA = _Phone(await Phone.open('opened-a', device: 'Phone A'));
    phoneB = _Phone(await Phone.open('opened-b', device: 'Phone B'));
    addTearDown(phoneA.close);
    addTearDown(phoneB.close);
    await phoneA.playback.bind(server.session, [_book, _other]);
    await phoneB.playback.bind(server.session, [_book, _other]);
  });

  /// Syncs [phone] and shows what the sync brought, as the app does.
  Future<void> sync(_Phone phone) async {
    await phone.store.synchronize(server.session, server.client);
    await phone.playback.refreshPersonalRecords();
  }

  /// Phone B listens to 0:40:00 and syncs. Phone A then listens on to
  /// 1:10:00 and syncs.
  Future<void> phoneAListensPastPhoneB() async {
    await phoneB.listenTo(_book, 40);
    await sync(phoneB);
    await sync(phoneA);
    await phoneA.listenTo(_book, 70);
    await sync(phoneA);
  }

  /// The listening moves of [book] on [phone] whose kind is open.
  List<HistoryEvent<AudioPosition>> opens(_Phone phone) => [
    for (final event in phone.playback.history)
      if (event.kind == HistoryAction.open) event,
  ];

  test('Phone A listens on and syncs. Phone B, which last played an earlier '
      'place, syncs and opens the book at A\'s place. Its timeline shows the '
      'open from Phone A, whose Go back returns to B\'s place, and B offers '
      'Undo', () async {
    await phoneAListensPastPhoneB();
    await sync(phoneB);

    await phoneB.playback.open(_book, _edition, autoplay: false);
    await phoneB.playback.flush();

    final player = phoneB.playback;
    expect(_Phone.minutesOf(player.position!), 70);
    final entry = player.timeline(_book).first as ActionEntry;
    final opened = entry.event as HistoryEvent<AudioPosition>;
    expect(opened.kind, HistoryAction.open);
    expect(opened.device, 'Phone A');
    expect(_Phone.minutesOf(opened.before), 40);
    expect(_Phone.minutesOf(opened.after), 70);
    expect(player.undoNotifier.value?.action, same(opened));
    expect(player.undoNotifier.value?.saved, isTrue);

    await player.restoreHistory(opened.id);
    expect(_Phone.minutesOf(player.position!), 40);
    player.checkInvariants();
  });

  test('Undo after the open from another device goes back to this phone\'s '
      'place', () async {
    await phoneAListensPastPhoneB();
    await sync(phoneB);
    await phoneB.playback.open(_book, _edition, autoplay: false);

    await phoneB.playback.undoSeek();
    await phoneB.playback.flush();

    final player = phoneB.playback;
    expect(_Phone.minutesOf(player.position!), 40);
    expect(player.history.first.kind, HistoryAction.undo);
    expect(player.undoNotifier.value, isNull);
  });

  test(
    'the open move from another device saves with the opened place',
    () async {
      await phoneAListensPastPhoneB();
      await sync(phoneB);

      await phoneB.playback.open(_book, _edition, autoplay: false);
      await phoneB.playback.flush();

      final saved = await phoneB.store.read(server.session.scope.key);
      final history = saved!['history'] as List;
      expect(history.last['kind'], 'open');
      expect(history.last['device'], 'Phone A');
    },
  );

  test('an app start that reopens the book at another device\'s place '
      'records the open from that device', () async {
    await phoneAListensPastPhoneB();
    await phoneB.playback.close();
    await sync(phoneB);

    final player = Playback(
      downloads: phoneB.downloads,
      engine: TestEngine(),
      store: phoneB.store,
    );
    addTearDown(player.close);
    await player.bind(server.session, [_book, _other]);
    await player.flush();

    expect(_Phone.minutesOf(player.position!), 70);
    final opened = player.history.first;
    expect(opened.kind, HistoryAction.open);
    expect(opened.device, 'Phone A');
    expect(_Phone.minutesOf(opened.before), 40);
  });

  test('a book that opens at this phone\'s own last place records no such '
      'move', () async {
    await phoneB.listenTo(_book, 40);
    await sync(phoneB);
    await phoneB.listenTo(_other, 5);

    await phoneB.playback.open(_book, _edition, autoplay: false);
    await phoneB.playback.flush();

    expect(_Phone.minutesOf(phoneB.playback.position!), 40);
    expect(opens(phoneB), isEmpty);
    expect(phoneB.playback.undoNotifier.value, isNull);
  });

  test('a second open at the same place from Phone A records no second '
      'move', () async {
    await phoneAListensPastPhoneB();
    await sync(phoneB);
    await phoneB.playback.open(_book, _edition, autoplay: false);
    await phoneB.listenTo(_other, 5);

    await phoneB.playback.open(_book, _edition, autoplay: false);
    await phoneB.playback.flush();

    expect(opens(phoneB), hasLength(1));
  });

  test('the recently listened order does not change because of the open '
      'move alone', () async {
    await phoneAListensPastPhoneB();
    await phoneB.listenTo(_other, 5);
    await sync(phoneB);
    final order = [for (final entry in phoneB.playback.recent) entry.book.id];
    expect(order, [_other.id, _book.id]);

    await phoneB.playback.open(_book, _edition, autoplay: false);
    await phoneB.playback.flush();

    expect(opens(phoneB), hasLength(1));
    expect([for (final entry in phoneB.playback.recent) entry.book.id], order);
  });
}
