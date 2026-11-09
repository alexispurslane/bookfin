// The reader's reading speed comes from the person's own page turns. It
// counts a page when the person turned forward from it, measures the time
// that the page was shown, and leaves out flipping, skimming and long
// pauses. It is derived data with a store of its own.
import 'package:bookfin/reader/reading_speed.dart';
import 'package:flutter_test/flutter_test.dart';

/// A speed store in memory. [unreadable] makes each read fail, and
/// [corrupt] makes it return text that is not a saved speed.
class MemorySpeedStore implements ReadingSpeedStore {
  MemorySpeedStore([this.value]);
  String? value;
  bool unreadable = false;
  var writes = 0;

  @override
  Future<String?> read() async {
    if (unreadable) throw StateError('The store cannot be read.');
    return value;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    this.value = value;
  }
}

/// A reading speed with a clock that the test moves.
class Reading {
  Reading([ReadingSpeedStore? store])
    : store = store ?? MemorySpeedStore(),
      now = DateTime(2026, 11, 9, 20);

  final ReadingSpeedStore store;
  DateTime now;
  late final speed = ReadingSpeed(store, clock: () => now);

  /// The person opens a book: its first page shows.
  void open() => speed.pageShown();

  /// The person spends [time] on a page of [characters] visible characters,
  /// then turns forward from it.
  void turn(int characters, Duration time) {
    now = now.add(time);
    speed.pageShown(read: characters);
  }

  /// The person reads [pages] pages of [characters] characters at
  /// [perMinute] characters a minute.
  void read(int pages, {int characters = 1200, double perMinute = 1200}) {
    for (var page = 0; page < pages; page++) {
      turn(
        characters,
        Duration(milliseconds: (characters / perMinute * 60000).round()),
      );
    }
  }

  double? get shown => speed.charactersPerMinute.value;
}

void main() {
  test('no speed shows before five page turns count', () {
    final reading = Reading()..open();
    reading.read(4);
    expect(reading.shown, isNull);
    reading.read(1);
    expect(reading.shown, closeTo(1200, 1));
  });

  test('the speed is the characters per minute of the pages that the '
      'person read', () {
    final reading = Reading()..open();
    reading.read(5, characters: 900, perMinute: 1500);
    expect(reading.shown, closeTo(1500, 1));
  });

  test('a long pause does not lower the speed', () {
    final reading = Reading()..open();
    reading.read(3);
    // The person put the phone down for half an hour on one page.
    reading.turn(1200, const Duration(minutes: 30));
    reading.read(2);
    expect(reading.shown, closeTo(1200, 1));
  });

  test('a pause of a few minutes among normal pages does not lower the '
      'speed', () {
    final reading = Reading()..open();
    reading.read(3);
    reading.turn(1200, const Duration(minutes: 6));
    reading.read(3);
    expect(reading.shown, closeTo(1200, 1));
  });

  test('fast flipping does not raise the speed', () {
    final reading = Reading()..open();
    reading.read(5);
    // The person flips through ten pages to find a place.
    for (var page = 0; page < 10; page++) {
      reading.turn(1200, const Duration(seconds: 1));
    }
    expect(reading.shown, closeTo(1200, 1));
  });

  test('skimming does not raise the speed', () {
    final reading = Reading()..open();
    reading.read(5);
    reading.read(10, perMinute: 8000);
    expect(reading.shown, closeTo(1200, 1));
  });

  test('a page with little text, such as a picture or a chapter title, '
      'does not count', () {
    final reading = Reading()..open();
    for (var page = 0; page < 5; page++) {
      reading.turn(40, const Duration(seconds: 20));
    }
    expect(reading.shown, isNull);
  });

  test('the time on a page counts from when it showed, so a jump or an '
      'opening starts it again', () {
    final reading = Reading()..open();
    reading.read(5);
    // The person leaves the book open for an hour, then jumps to a chapter.
    reading.now = reading.now.add(const Duration(hours: 1));
    reading.speed.pageShown();
    reading.read(5, perMinute: 1000);
    expect(reading.shown, closeTo(1100, 1));
  });

  test('the shown speed changes only after every fifth counted page, so '
      'the time left does not move on every page', () {
    final reading = Reading()..open();
    reading.read(5);
    expect(reading.shown, closeTo(1200, 1));
    reading.read(4, perMinute: 600);
    expect(reading.shown, closeTo(1200, 1));
    reading.read(1, perMinute: 600);
    expect(reading.shown, closeTo(900, 1));
  });

  test('the speed follows the latest forty counted pages, so it moves to '
      'the speed of a new book', () {
    final reading = Reading()..open();
    reading.read(40);
    reading.read(40, perMinute: 800);
    expect(reading.shown, closeTo(800, 1));
  });

  test('the speed carries to the next start from its store', () async {
    final store = MemorySpeedStore();
    final first = Reading(store)..open();
    first.read(6, perMinute: 1500);
    await first.speed.saved;

    final next = Reading(store);
    expect(next.shown, isNull);
    await next.speed.restore();
    expect(next.shown, closeTo(1500, 1));
  });

  test('pages counted before the store is read are kept with the saved '
      'ones', () async {
    final store = MemorySpeedStore();
    final first = Reading(store)..open();
    first.read(3, perMinute: 1500);
    await first.speed.saved;

    final next = Reading(store)..open();
    final restored = next.speed.restore();
    next.read(2, perMinute: 1500);
    await restored;
    await next.speed.saved;
    expect(next.shown, closeTo(1500, 1));

    final third = Reading(store);
    await third.speed.restore();
    expect(third.shown, closeTo(1500, 1));
  });

  test('a speed store that cannot be read starts without a speed, and the '
      'next counted page replaces it', () async {
    for (final store in [
      MemorySpeedStore()..unreadable = true,
      MemorySpeedStore('{"version": 1, "samples": ["fast"]}'),
      MemorySpeedStore('not a saved speed'),
    ]) {
      final reading = Reading(store);
      await reading.speed.restore();
      expect(reading.shown, isNull);
      store.unreadable = false;
      reading
        ..open()
        ..read(5);
      await reading.speed.saved;
      final next = Reading(store);
      await next.speed.restore();
      expect(next.shown, closeTo(1200, 1));
    }
  });

  test('a failed write keeps the speed and later writes', () async {
    final store = _FailingOnce();
    final reading = Reading(store)..open();
    reading.read(5);
    await reading.speed.saved;
    expect(reading.shown, closeTo(1200, 1));
    reading.read(1);
    await reading.speed.saved;
    final next = Reading(store);
    await next.speed.restore();
    expect(next.shown, closeTo(1200, 1));
  });
}

class _FailingOnce extends MemorySpeedStore {
  var failed = false;

  @override
  Future<void> write(String value) async {
    if (!failed) {
      failed = true;
      throw StateError('The disk is full.');
    }
    await super.write(value);
  }
}
