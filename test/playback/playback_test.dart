import 'dart:async';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/session.dart' show ReadingChanges, ReadingStore;
import 'package:flutter_test/flutter_test.dart';

import '../downloads/verified_reads.dart';
import 'observe_playback.dart';

const first = SourceFile(
  itemId: 'one',
  displayName: 'Part one',
  mediaSourceId: 'm1',
  revision: 'r1',
  durationMs: 60000,
  container: 'wav',
  sizeBytes: 42,
  chapters: [AudioChapter('Opening', 0), AudioChapter('Arrival', 40000)],
);
const second = SourceFile(
  itemId: 'two',
  displayName: 'Part two',
  mediaSourceId: 'm2',
  revision: 'r2',
  durationMs: 90000,
  container: 'wav',
  sizeBytes: 42,
  chapters: [AudioChapter('Return', 10000)],
);
const recording = Edition(
  id: 'recording',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [first, second],
  memberIds: ['one:m1', 'two:m2'],
);
const title = Book(
  id: 'book',
  title: 'The journey',
  author: 'A. Writer',
  editions: [recording],
);
JellyfinSession account({String user = 'alice', String serverId = 'server'}) =>
    JellyfinSession(
      scope: AccountScope(
        server: Uri.parse('http://127.0.0.1:8888'),
        serverId: serverId,
        userId: user,
      ),
      token: 'fixture-token',
      username: user,
      canDownload: true,
    );

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles();
    engine = TestEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title]);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  test('overlapping short jumps accumulate inside the command owner', () async {
    await playback.open(title, recording);
    await Future.wait([
      playback.jump(forward: true),
      playback.jump(forward: true),
    ]);
    expect(playback.editionMilliseconds, 60000);
  });

  test('short jumps work within a source with unknown duration', () async {
    const file = SourceFile(
      itemId: 'one',
      mediaSourceId: 'm1',
      revision: 'r1',
      displayName: 'Unknown',
      durationMs: null,
      container: 'wav',
      sizeBytes: 42,
    );
    const edition = Edition(
      id: 'unknown',
      kind: EditionKind.audio,
      label: 'Unknown',
      files: [file],
      memberIds: ['one:m1'],
    );
    const book = Book(
      id: 'unknown',
      title: 'Unknown',
      author: '',
      editions: [edition],
    );
    await playback.bind(account(), [book]);
    await playback.open(book, edition);
    await playback.jump(forward: true);
    expect(playback.position?.milliseconds, 30000);
  });

  for (final switchAccount in [false, true]) {
    test(
      'unrestored account survives ${switchAccount ? 'sign out' : 'flush'}',
      () async {
        await playback.open(title, recording);
        await playback.seekEdition(75000);
        await playback.flush();
        await playback.bind(null, []);
        final saved = store.values[account().scope.key];
        store.readGate = Completer<void>();
        final binding = playback.bind(account(), [title]);
        final operation = switchAccount
            ? playback.bind(null, [])
            : playback.flush();
        await Future<void>.delayed(Duration.zero);
        store.readGate!.complete();
        await Future.wait([binding, operation]);
        expect(store.values[account().scope.key], saved);
      },
    );
  }

  test('a recording shows how far the saved position is into it', () async {
    expect(playback.progress(recording), isNull);
    await playback.open(title, recording);
    await playback.seekEdition(75000);
    await playback.flush();
    expect(playback.progress(recording), (elapsedMs: 75000, totalMs: 150000));
    await playback.bind(null, []);
    await playback.bind(account(), [title]);
    expect(playback.progress(recording), (
      elapsedMs: 75000,
      totalMs: 150000,
    ), reason: 'a saved position counts without opening the recording');
  });

  test('failed resume read cannot be overwritten by later saves', () async {
    await playback.open(title, recording);
    await playback.seekEdition(75000);
    await playback.flush();
    await playback.bind(null, []);
    final saved = store.values[account().scope.key];
    store.failRead = true;
    await playback.bind(account(), [title]);
    await playback.flush();
    expect(store.values[account().scope.key], saved);
    store.failRead = false;
  });

  test(
    'plays only verified local files in explicit recording order while offline',
    () async {
      await playback.open(title, recording);
      expect(engine.files, [Uri.file('/one.wav'), Uri.file('/two.wav')]);
      expect(playback.playing, isTrue);
      expect(playback.position?.sourceKey, first.key);
      expect(downloads.requested, isEmpty);
      playback.checkInvariants();
    },
  );
  test(
    'a missing local part cannot become a remote playback request',
    () async {
      downloads.files.remove(second.key);
      await playback.open(title, recording);
      expect(playback.message, contains('Download'));
      expect(engine.files, isEmpty);
      expect(downloads.requested, isEmpty);
    },
  );
  test(
    'maps edition time and configurable jumps across ordered file boundaries',
    () async {
      await playback.open(title, recording);
      await playback.seekEdition(65000);
      expect(playback.position?.sourceKey, second.key);
      expect(playback.position?.milliseconds, 5000);
      await playback.setJumps(12, 45);
      await playback.jump(forward: false);
      expect(playback.position?.sourceKey, first.key);
      expect(playback.position?.milliseconds, 53000);
      await playback.jump(forward: true);
      expect(playback.editionMilliseconds, 98000);
      await playback.seekEdition(900000);
      expect(playback.editionMilliseconds, 150000);
    },
  );
  test('chapter ranges remain distinct from file boundaries', () async {
    await playback.open(title, recording);
    expect(playback.chapters.map((chapter) => chapter.name), [
      'Opening',
      'Arrival',
      'Part two',
      'Return',
    ]);
    await playback.seekSource(second.key, 10000);
    expect(playback.editionMilliseconds, 70000);
  });
  test('speed changes do not multiply the recorded audio position', () async {
    await playback.open(title, recording);
    await playback.seekEdition(45000);
    await playback.setSpeed(1.75);
    expect(engine.rate, 1.75);
    expect(playback.position?.milliseconds, 45000);
    expect(playback.playbackSpeed, 1.75);
  });
  test('restart restores the source position paused and retains pending offline resume', () async {
    await playback.open(title, recording);
    await playback.seekEdition(72000);
    await playback.setSpeed(1.5);
    await playback.setJumps(15, 45);
    await playback.pause();
    await playback.close();
    engine = TestEngine();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title]);
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 12000);
    expect(playback.playing, isFalse);
    expect(playback.pendingOfflineResume, isTrue);
    expect(playback.playbackSpeed, 1.5);
    expect(playback.backwardSeconds, 15);
    expect(playback.forwardSeconds, 45);
  });
  test(
    'restart reopens the saved book when the library loads after the account',
    () async {
      await playback.open(title, recording);
      await playback.seekEdition(72000);
      await playback.pause();
      await playback.close();
      engine = TestEngine();
      playback = Playback(downloads: downloads, engine: engine, store: store);
      await playback.bind(account(), []);
      expect(playback.book, isNull);

      final reopened = waitForPlayback(playback, () => playback.book != null);
      await playback.bind(account(), [title]);
      await reopened;

      expect(playback.book, title);
      expect(playback.editionMilliseconds, 72000);
      expect(playback.playing, isFalse);
    },
  );
  test(
    'sampled native position survives restart without an ordinary pause',
    () async {
      await playback.open(title, recording);
      engine.emit(1, 17000, playing: true);
      await playback.flush();
      final other = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: store,
      );
      await other.bind(account(), [title]);
      expect(other.position?.milliseconds, 17000);
      expect(other.position?.sourceKey, second.key);
      await other.close();
    },
  );
  test('changing account stops playback and never exposes the previous account resume', () async {
    await playback.open(title, recording);
    await playback.seekEdition(80000);
    await playback.bind(account(user: 'bob'), [title]);
    expect(playback.position, isNull);
    expect(playback.book, isNull);
    expect(engine.isPlaying, isFalse);
    await playback.open(title, recording, autoplay: false);
    expect(playback.position?.milliseconds, 0);
    await playback.bind(account(), [title]);
    expect(playback.position?.milliseconds, 20000);
  });
  test('a different server installation cannot reuse a saved resume', () async {
    await playback.open(title, recording);
    await playback.seekEdition(80000);
    await playback.bind(account(serverId: 'replacement'), [title]);
    expect(playback.position, isNull);
    await playback.open(title, recording, autoplay: false);
    expect(playback.position?.milliseconds, 0);
  });

  test('an explicit play waits for account resume restoration instead of overwriting it', () async {
    await playback.open(title, recording);
    await playback.seekEdition(81000);
    await playback.close();
    store.readGate = Completer<void>();
    engine = TestEngine();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    final restoring = playback.bind(account(), [title]);
    await Future<void>.delayed(Duration.zero);
    final opening = playback.open(title, recording);
    await Future<void>.delayed(Duration.zero);
    final loadedBeforeRestore = List<Uri>.of(engine.files);
    store.readGate!.complete();
    await restoring;
    await opening;
    expect(loadedBeforeRestore, isEmpty);
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 21000);
    expect(playback.playing, isTrue);
  });

  test('source verification cannot start audio after sign-out', () async {
    await playback.open(title, recording, autoplay: false);
    downloads.lookupGate = Completer<void>();
    final playing = playback.play();
    await Future<void>.delayed(Duration.zero);
    final signingOut = playback.bind(null, []);
    downloads.lookupGate!.complete();
    await playing;
    await signingOut;
    expect(engine.playCount, 0);
    expect(playback.book, isNull);
  });

  test('metadata corrections update the selected book without a second playback owner', () async {
    await playback.open(title, recording);
    const corrected = Book(
      id: 'book',
      title: 'Corrected journey',
      author: 'A. Writer',
      editions: [recording],
    );
    await playback.bind(account(), [corrected]);
    expect(playback.book?.title, 'Corrected journey');
    expect(playback.playing, isTrue);
  });

  test('finishing the recording preserves its final source and explicit play begins again', () async {
    await playback.open(title, recording);
    engine.emit(1, 90000, completed: true);
    await playback.flush();
    expect(playback.playing, isFalse);
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 90000);
    await playback.play();
    expect(playback.position?.sourceKey, first.key);
    expect(playback.position?.milliseconds, 0);
  });
  test(
    'a changed source revision keeps the saved resume but does not apply it',
    () async {
      await playback.open(title, recording);
      await playback.seekEdition(80000);
      await playback.bind(null, []);
      const changed = SourceFile(
        itemId: 'two',
        displayName: 'Replacement',
        mediaSourceId: 'm2',
        revision: 'r3',
        durationMs: 90000,
        container: 'wav',
        sizeBytes: 42,
      );
      const replacement = Edition(
        id: 'recording',
        kind: EditionKind.audio,
        label: 'Narrator',
        files: [first, changed],
        memberIds: ['one:m1', 'two:m2'],
      );
      await playback.bind(account(), [
        const Book(
          id: 'book',
          title: 'The journey',
          author: '',
          editions: [replacement],
        ),
      ]);
      expect(playback.position, isNull);
      expect(playback.message, contains('changed'));
      expect(store.values[account().scope.key]!['resumes'], isNotEmpty);
    },
  );
  test('unknown durations still permit source chapter seeking but not guessed edition time', () async {
    const unknown = SourceFile(
      itemId: 'unknown',
      displayName: 'Unknown length',
      mediaSourceId: 'mu',
      revision: 'r',
      durationMs: null,
      container: 'wav',
      sizeBytes: 42,
    );
    const edition = Edition(
      id: 'unknown',
      kind: EditionKind.audio,
      label: 'Audio',
      files: [unknown, second],
      memberIds: ['unknown:mu', 'two:m2'],
    );
    const book = Book(
      id: 'unknown',
      title: 'Unknown',
      author: '',
      editions: [edition],
    );
    downloads.files[unknown.key] = Uri.file('/unknown.wav');
    await playback.bind(account(), [title, book]);
    await playback.open(book, edition);
    expect(playback.durationMilliseconds, isNull);
    await playback.seekSource(second.key, 5000);
    expect(playback.position?.milliseconds, 5000);
    expect(playback.editionMilliseconds, isNull);
  });
  test('sleep timer pauses playback without erasing the resume', () async {
    await playback.open(title, recording);
    await playback.seekEdition(23000);
    await playback.setSleep(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(playback.playing, isFalse);
    expect(playback.position?.milliseconds, 23000);
    expect(playback.sleepDeadline, isNull);
  });
  test(
    'rejects unsafe speeds and jump lengths without changing settings',
    () async {
      await playback.open(title, recording);
      await expectLater(playback.setSpeed(double.nan), throwsArgumentError);
      await expectLater(playback.setSpeed(0), throwsArgumentError);
      await expectLater(playback.setJumps(0, 30), throwsArgumentError);
      expect(playback.playbackSpeed, 1);
    },
  );
  test('a native playback failure stops audio and keeps the last durable source position', () async {
    await playback.open(title, recording);
    await playback.seekEdition(78000);
    final stopped = waitForPlayback(playback, () => !playback.active);
    engine.events.addError(Exception('decoder failed'));
    await stopped;
    expect(engine.isPlaying, isFalse);
    expect(playback.active, isFalse);
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 18000);
    expect(playback.message, contains('Cannot play'));
  });
  test('recording completion clears native play intent so later chapter seeks stay paused', () async {
    await playback.open(title, recording);
    engine.emit(1, 90000, playing: true, completed: true);
    await playback.flush();
    expect(engine.isPlaying, isFalse);
    await playback.seekSource(first.key, 30000);
    expect(engine.isPlaying, isFalse);
    expect(playback.playing, isFalse);
    await playback.play();
    expect(playback.playing, isTrue);
  });
}

class MemoryResume extends ResumeStore implements ListeningStore, ReadingStore {
  final values = <String, Map<String, dynamic>>{};
  Completer<void>? readGate;
  bool failRead = false;
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    await readGate?.future;
    if (failRead) throw Exception('read failed');
    return values[accountKey];
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    values[accountKey] = value;
  }

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    values[accountKey] = changes.applyTo(values[accountKey]);
  }

  @override
  Future<PlaceOrigin> origin(String accountKey, Edition edition) async =>
      (own: null, elsewhere: false, device: null);

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) async {
    values[accountKey] = changes.applyTo(values[accountKey]);
  }
}

class TestEngine implements AudioEngine {
  final events = StreamController<AudioSample>.broadcast(sync: true);
  List<Uri> files = [];
  int index = 0;
  int milliseconds = 0;
  bool isPlaying = false;
  double rate = 1;
  bool closed = false;
  int playCount = 0;
  void emit(
    int fileIndex,
    int position, {
    bool playing = false,
    bool completed = false,
  }) {
    index = fileIndex;
    milliseconds = position;
    isPlaying = playing;
    events.add(
      AudioSample(index, milliseconds, playing: playing, completed: completed),
    );
  }

  @override
  Stream<AudioSample> get samples => events.stream;
  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    files = sources;
    emit(fileIndex, position);
  }

  @override
  Future<void> play() async {
    playCount++;
    emit(index, milliseconds, playing: true);
  }

  @override
  Future<void> pause() async => emit(index, milliseconds);
  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    emit(fileIndex, position, playing: isPlaying);
    return AudioSample(index, milliseconds, playing: isPlaying);
  }

  @override
  Future<void> speed(double value) async {
    rate = value;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await events.close();
  }
}

class LocalFiles extends Downloads with VerifiedReads {
  LocalFiles() : super(MediaPolicy()..network = MediaNetwork.disconnected);
  final files = {
    first.key: Uri.file('/one.wav'),
    second.key: Uri.file('/two.wav'),
  };
  final requested = <String>[];
  Completer<void>? lookupGate;
  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async {
    await lookupGate?.future;
    return files[source.key];
  }

  @override
  EditionDownload status(Edition edition) =>
      const EditionDownload(phase: DownloadPhase.downloaded);
  @override
  Future<void> request(Edition edition) async {
    requested.add(edition.id);
  }

  @override
  Future<void> cancel(Edition edition) async {}
  @override
  Future<void> remove(Edition edition) async {}
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}
