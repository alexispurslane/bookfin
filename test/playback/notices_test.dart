import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart';
import 'replacement_test.dart' show revisedBook, replacement;

const otherFile = SourceFile(
  itemId: 'other',
  mediaSourceId: 'other-source',
  revision: 'r1',
  displayName: 'Other audio',
  durationMs: 60000,
  container: 'm4b',
  sizeBytes: 42,
);
const otherEdition = Edition(
  id: 'other-edition',
  kind: EditionKind.audio,
  label: 'Other narrator',
  files: [otherFile],
  memberIds: ['other:other-source'],
);
const otherBook = Book(
  id: 'other-book',
  title: 'Another journey',
  author: 'B. Writer',
  editions: [otherEdition],
);

class NoticeStore extends MemoryResume {
  bool recovered = false;
  bool failSave = false;
  Completer<void>? readEntered;
  @override
  Future<Map<String, dynamic>?> read(String accountKey) {
    final entered = readEntered;
    readEntered = null;
    entered?.complete();
    return super.read(accountKey);
  }

  @override
  bool setAside(String accountKey) => recovered;
  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    if (failSave) throw Exception('storage full');
    await super.save(accountKey, changes);
  }
}

class NoticeEngine extends TestEngine {
  bool failLoad = false;
  bool failPlay = false;
  Completer<void>? failedPauseEntered;
  Completer<void>? releaseFailedPause;
  Completer<void>? loadEntered;
  Completer<void>? releaseFailedLoad;

  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    final release = releaseFailedLoad;
    if (release != null) {
      releaseFailedLoad = null;
      loadEntered!.complete();
      await release.future;
      throw Exception('old source could not load');
    }
    if (failLoad) throw Exception('decoder rejected file');
    await super.load(sources, fileIndex, position);
  }

  @override
  Future<void> play() async {
    if (failPlay) throw Exception('decoder rejected play');
    await super.play();
  }

  @override
  Future<void> pause() async {
    final release = releaseFailedPause;
    if (release != null) {
      releaseFailedPause = null;
      failedPauseEntered!.complete();
      await release.future;
      throw Exception('audio device failed while pausing');
    }
    await super.pause();
  }
}

void main() {
  late LocalFiles downloads;
  late NoticeStore store;
  late Playback playback;
  late NoticeEngine engine;
  setUp(() async {
    downloads = LocalFiles();
    store = NoticeStore();
    engine = NoticeEngine();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title, otherBook]);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  test(
    'playing the already-open edition clears a failed other-book action',
    () async {
      await playback.open(title, recording, autoplay: false);
      await playback.open(otherBook, otherEdition);
      expect(
        playback.statusNotifier.value.actionNotice?.message,
        contains('Download'),
      );
      expect(playback.edition, recording);

      await playback.play();

      expect(playback.playing, isTrue);
      expect(playback.statusNotifier.value.actionNotice, isNull);
      playback.checkInvariants();
    },
  );

  test('opening an edition preserves unresolved record recovery', () async {
    await playback.bind(null, []);
    store.recovered = true;
    await playback.bind(account(), [title, otherBook]);
    expect(playback.statusNotifier.value.recoveryMessage, contains('damaged'));

    await playback.open(title, recording);

    expect(playback.playing, isTrue);
    expect(playback.statusNotifier.value.recoveryMessage, contains('damaged'));
  });

  test(
    'a failed old-account read does not report on the replacement account',
    () async {
      await playback.bind(null, []);
      store.readGate = Completer<void>();
      final entered = store.readEntered = Completer<void>();
      store.failRead = true;
      final oldBinding = playback.bind(account(), [title, otherBook]);
      await entered.future;
      final newBinding = playback.bind(null, []);
      store.readGate!.complete();
      await Future.wait([oldBinding, newBinding]);

      expect(playback.session, isNull);
      expect(playback.statusNotifier.value, (
        actionNotice: null,
        recoveryMessage: null,
        saveFailed: false,
      ));
    },
  );

  test(
    'a failed load belongs to the attempted edition, not the retained player',
    () async {
      await playback.open(title, recording, autoplay: false);
      downloads.files[otherFile.key] = Uri.file('/other.m4b');
      engine.failLoad = true;
      await playback.open(otherBook, otherEdition);

      expect(playback.edition, recording);
      expect(
        playback.statusNotifier.value.messagesFor(edition: recording),
        isEmpty,
      );
      expect(
        playback.statusNotifier.value.messagesFor(book: otherBook),
        contains(contains('Cannot play')),
      );
      expect(
        playback.statusNotifier.value.actionNotice?.operation,
        PlaybackOperation.open,
      );
      engine.failLoad = false;
      await playback.play();
      expect(playback.playing, isTrue);
      expect(playback.statusNotifier.value.actionNotice, isNull);
    },
  );

  test(
    'a failed Play remains visible for its edition until Play succeeds',
    () async {
      await playback.open(title, recording, autoplay: false);
      engine.failPlay = true;
      await playback.play();
      expect(
        playback.statusNotifier.value.messagesFor(edition: recording),
        contains(contains('Cannot play')),
      );
      expect(
        playback.statusNotifier.value.actionNotice?.operation,
        PlaybackOperation.play,
      );
      await playback.flush();
      expect(playback.statusNotifier.value.actionNotice, isNotNull);
      engine.failPlay = false;
      await playback.play();
      expect(playback.statusNotifier.value.actionNotice, isNull);
      expect(playback.playing, isTrue);
    },
  );

  test(
    'a late error while pausing a failed action cannot reach a new account',
    () async {
      await playback.open(title, recording, autoplay: false);
      engine.failPlay = true;
      engine.failedPauseEntered = Completer<void>();
      final release = engine.releaseFailedPause = Completer<void>();
      final failed = playback.play();
      await engine.failedPauseEntered!.future;
      final replacement = playback.bind(account(user: 'bob'), [
        title,
        otherBook,
      ]);
      release.complete();
      await Future.wait([failed, replacement]);

      expect(playback.session!.scope.userId, 'bob');
      expect(playback.statusNotifier.value.messagesFor(book: title), isEmpty);
      expect(playback.edition, isNull);
      playback.checkInvariants();
    },
  );

  test('save retry resolves only the save notice and keeps recovery and action notices', () async {
    await playback.bind(null, []);
    store.recovered = true;
    await playback.bind(account(), [title, otherBook]);
    store.failSave = true;
    await playback.open(title, recording, autoplay: false);
    await playback.addBookmark(title: 'Keep this');
    await playback.open(otherBook, otherEdition);
    final status = playback.statusNotifier.value;
    expect(status.messagesFor(book: otherBook), hasLength(3));
    expect(status.saveFailed, isTrue);

    store.failSave = false;
    await playback.flush();

    expect(playback.statusNotifier.value.saveFailed, isFalse);
    expect(playback.statusNotifier.value.actionNotice, status.actionNotice);
    expect(
      playback.statusNotifier.value.recoveryMessage,
      status.recoveryMessage,
    );
    expect(playback.bookmarks.single.title, 'Keep this');
    await playback.play();
    expect(playback.statusNotifier.value.actionNotice, isNull);
    expect(
      playback.statusNotifier.value.messagesFor(),
      contains(contains('damaged')),
    );
    playback.checkInvariants();
  });

  test(
    'a failed automatic reopen is an edition action error, not record recovery',
    () async {
      await playback.open(title, recording, autoplay: false);
      await playback.bind(null, []);
      engine.failLoad = true;
      await playback.bind(account(), [title, otherBook]);

      expect(playback.statusNotifier.value.messagesFor(), isEmpty);
      expect(
        playback.statusNotifier.value.messagesFor(book: title),
        contains(contains('Cannot play')),
      );
      expect(
        playback.statusNotifier.value.actionNotice?.operation,
        PlaybackOperation.open,
      );
    },
  );

  test(
    'a delayed old-source failure cannot describe replacement audio',
    () async {
      engine.loadEntered = Completer<void>();
      final release = engine.releaseFailedLoad = Completer<void>();
      final opening = playback.open(title, recording);
      await engine.loadEntered!.future;
      const revised = Edition(
        id: 'recording',
        kind: EditionKind.audio,
        label: 'Replacement recording',
        files: [otherFile],
        memberIds: ['other:other-source'],
      );
      const replacement = Book(
        id: 'book',
        title: 'The journey',
        author: 'A. Writer',
        editions: [revised],
      );
      await playback.bind(account(), [replacement]);
      release.complete();
      await opening;

      expect(
        playback.statusNotifier.value.messagesFor(book: replacement),
        isEmpty,
      );
      expect(playback.edition, isNull);
    },
  );

  test(
    'another edition of the same book does not inherit its failed action',
    () async {
      const editions = Book(
        id: 'book',
        title: 'The journey',
        author: 'A. Writer',
        editions: [recording, otherEdition],
      );
      await playback.bind(account(), [editions]);
      await playback.open(editions, recording, autoplay: false);
      await playback.open(editions, otherEdition);

      expect(
        playback.statusNotifier.value.messagesFor(book: editions),
        contains(contains('Download')),
      );
      expect(
        playback.statusNotifier.value.messagesFor(
          book: editions,
          edition: recording,
        ),
        isEmpty,
      );
      downloads.files[otherFile.key] = Uri.file('/other.m4b');
      await playback.open(editions, otherEdition);
      expect(playback.playing, isTrue);
      expect(playback.statusNotifier.value.actionNotice, isNull);
    },
  );

  test(
    'a stream failure queued behind another open cannot stop its edition',
    () async {
      await playback.open(title, recording);
      downloads.files[otherFile.key] = Uri.file('/other.m4b');
      downloads.lookupGate = Completer<void>();
      final opening = playback.open(otherBook, otherEdition);
      engine.events.addError(Exception('old decoder failed'));
      downloads.lookupGate!.complete();
      await opening;
      // A records command is a barrier behind the queued stream failure.
      await playback.setJumps(10, 30);

      expect(playback.edition, otherEdition);
      expect(playback.playing, isTrue);
      expect(playback.statusNotifier.value.actionNotice, isNull);
    },
  );

  test(
    'a current decoder stream failure stays visible on its edition',
    () async {
      await playback.open(title, recording);
      engine.events.addError(Exception('current decoder failed'));
      await playback.setJumps(10, 30);

      expect(playback.playing, isFalse);
      expect(
        playback.statusNotifier.value.messagesFor(edition: recording),
        contains(contains('Cannot play')),
      );
      expect(
        playback.statusNotifier.value.actionNotice?.operation,
        PlaybackOperation.decoder,
      );
      expect(
        playback.statusNotifier.value.messagesFor(book: otherBook),
        isEmpty,
      );
    },
  );

  test('status notifies about a failure and its resolution, not playing ticks or successful saves', () async {
    await playback.open(title, recording, autoplay: false);
    final shown = <PlaybackStatus>[];
    playback.statusNotifier.addListener(
      () => shown.add(playback.statusNotifier.value),
    );
    await playback.open(otherBook, otherEdition);
    await playback.play();
    engine.emit(0, 1000, playing: true);
    engine.emit(0, 2000, playing: true);
    await playback.flush();

    expect(shown, hasLength(2));
    expect(shown.first.actionNotice?.editionId, otherEdition.id);
    expect(shown.last.actionNotice, isNull);
  });

  test('canceling a replacement dismisses only its action notice', () async {
    await playback.open(title, recording, autoplay: false);
    await playback.seekEdition(75000);
    await playback.addBookmark(title: 'Original recording');
    store.recovered = true;
    await playback.bind(account(), [revisedBook]);
    final offer = playback.replacementStart!;
    final recovery = playback.statusNotifier.value.recoveryMessage;
    expect(recovery, contains('damaged'));
    expect(playback.statusNotifier.value.actionNotice, isNotNull);

    playback.cancelReplacement(offer);

    expect(playback.replacementStart, isNull);
    expect(playback.statusNotifier.value.actionNotice, isNull);
    expect(playback.statusNotifier.value.recoveryMessage, recovery);
    expect(playback.bookmarks.single.title, 'Original recording');
    await playback.open(revisedBook, replacement);
    await playback.confirmReplacement(playback.replacementStart!);
    expect(playback.playing, isTrue);
    expect(playback.statusNotifier.value.recoveryMessage, recovery);
  });
}
