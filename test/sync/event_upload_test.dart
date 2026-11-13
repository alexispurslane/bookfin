import 'dart:async';

import 'package:bookfin/sync/record_address.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/widgets.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/reporting.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import '../playback/held_engine.dart';
import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../catalog/controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials;
import 'controlled_transport.dart';

const otherEdition = Edition(
  id: 'other',
  kind: EditionKind.audio,
  label: 'Other recording',
  files: [audio.first],
  memberIds: ['one:m1'],
);
const otherBook = Book(
  id: 'other',
  title: 'Other book',
  author: '',
  editions: [otherEdition],
);

void main() {
  testUpload('sync exchanges durable records while an audio seek stays held', (
    tester,
    rig,
  ) async {
    rig.records.gate = Completer<void>();
    rig.engine.emit(0, 3456, playing: true);
    rig.engine.held = HeldCommand.seek;
    final seeking = rig.player.seekEdition(78000);
    await rig.engine.entered.future;
    final syncing = rig.sync.syncNow();
    try {
      await tester.pump();
      expect(rig.exchanges, 0);
      rig.records.gate!.complete();
      await tester.pump();
      expect(rig.sentPlace('recording'), 3456);
      expect(rig.engine.released.isCompleted, isFalse);
      final reopened = LocalResumeStore(hop: inlineHop);
      expect(
        (await reopened.read(
          rig.account,
        ))!['resumes']['recording'].single['milliseconds'],
        3456,
      );
    } finally {
      if (!rig.records.gate!.isCompleted) rig.records.gate!.complete();
      rig.engine.release();
      await seeking;
      await syncing;
    }
  });

  testUpload(
    'a stop whose audio device fails still uploads the last durable place',
    (tester, rig) async {
      rig.engine.emit(0, 3210, playing: true);
      rig.engine.failPause = true;
      await rig.player.stop();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 3210);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
    },
  );

  testUpload('an event upload replaces an older choice message', (
    tester,
    rig,
  ) async {
    await rig.sync.resolve(RecordAddress('audio', 'resumes', 'gone'), 'gone');
    expect(rig.sync.message, isNotNull);
    rig.engine.emit(0, 3456, playing: true);
    await rig.player.pause();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.sentPlace('recording'), 3456);
    expect(rig.sync.message, isNull);
  });

  testUpload('a real event during a failed upload gets one later attempt', (
    tester,
    rig,
  ) async {
    rig.gate = Completer<void>();
    rig.fail = true;
    rig.engine.emit(0, 1234, playing: true);
    await rig.player.pause();
    await tester.pump(const Duration(seconds: 1));
    rig.engine.emit(0, 2345);
    await rig.player.pause();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.exchanges, 1);
    rig.gate!.complete();
    await tester.pump();
    expect(rig.sync.lastSyncNotifier.value?.failure, isNotNull);
    rig.fail = false;
    await tester.pump(const Duration(seconds: 1));
    expect(rig.exchanges, 2);
    expect(rig.sentPlace('recording'), 2345);
    await tester.pump(const Duration(minutes: 5));
    expect(rig.exchanges, 2);
  });

  for (final retired in [false, true]) {
    testUpload(
      '${retired ? 'an unregistered writer' : 'another account writer'} cannot schedule uploads',
      (tester, rig) async {
        final signal = ChangeNotifier();
        final unregister = rig.records.registerWriter(
          account: () =>
              retired ? rig.account : audio.account(user: 'bob').scope.key,
          flush: () async {},
          refresh: () async {},
          uploadRequests: signal,
        );
        if (retired) unregister();
        rig.engine.emit(0, 1234, playing: true);
        await rig.player.flush();
        signal.notifyListeners();
        await tester.pump(const Duration(seconds: 1));
        expect(rig.exchanges, 0);
        expect(await rig.records.pendingUploads(rig.account), isNotEmpty);
        unregister();
        signal.dispose();
      },
    );
  }

  testUpload(
    'the app hide sequence saves and uploads without waiting for resume',
    (tester, rig) async {
      final catalog = CatalogController(
        credentials: MemoryCredentials()..value = audio.account(),
        store: MemoryCatalogStore(),
        hop: inlineHop,
      );
      await catalog.restore();
      final appearance = AppearanceController(MemoryAppearanceStore());
      try {
        await tester.pumpWidget(
          BookfinApp(
            appearance: appearance,
            catalog: catalog,
            playback: rig.player,
            sync: rig.sync,
          ),
        );
        rig.engine.emit(0, 4567, playing: true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(rig.exchanges, 0);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 1));
        expect(rig.sentPlace('recording'), 4567);
        expect(await rig.records.pendingUploads(rig.account), isEmpty);
        final exchanges = rig.exchanges;
        await tester.pump(const Duration(minutes: 2));
        expect(rig.exchanges, exchanges);
      } finally {
        rig.disposed = true; // BookfinApp owns disposal of its coordinator.
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        catalog.dispose();
        appearance.dispose();
      }
    },
  );

  for (final check in ['local flush', 'final upload']) {
    testWidgets('$check does not wait for a slow Jellyfin playback report', (
      tester,
    ) async {
      final policy = MediaPolicy()..network = MediaNetwork.wifi;
      final client = SlowReports();
      final reports = LiveReports(policy, clientFactory: (_) => client);
      final rig = await UploadRig.open(tester, reports: reports);
      Future<void>? saving;
      try {
        client.gate = Completer<void>();
        rig.engine.emit(0, 11000, playing: true);
        var saved = false;
        saving = rig.player.flush().then((_) => saved = true);
        rig.sync.suspend();
        await tester.pump(const Duration(seconds: 1));
        if (check == 'local flush') {
          expect(saved, isTrue);
        } else {
          expect(rig.sentPlace('recording'), 11000);
        }
        expect(client.gate!.isCompleted, isFalse);
      } finally {
        client.gate!.complete();
        await saving;
        await rig.close(tester);
        policy.dispose();
      }
    });
  }

  testUpload(
    'the final upload waits for local storage to confirm the newest save',
    (tester, rig) async {
      rig.records.gate = Completer<void>();
      rig.engine.emit(0, 3456, playing: true);
      final pausing = rig.player.pause();
      rig.sync.suspend();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 0);
      rig.records.gate!.complete();
      await pausing;
      await tester.pump();
      expect(rig.sentPlace('recording'), 3456);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
    },
  );

  for (final change in ['sign out', 'account', 'dispose']) {
    testUpload('$change during a writer flush prevents the obsolete exchange', (
      tester,
      rig,
    ) async {
      final gate = Completer<void>();
      final unregister = rig.records.registerWriter(
        account: () => rig.account,
        flush: () => gate.future,
        refresh: () async {},
      );
      final syncing = rig.sync.synchronize();
      await tester.pump();
      switch (change) {
        case 'sign out':
          rig.sync.bind(null);
        case 'account':
          rig.sync.bind(audio.account(user: 'bob'));
        case 'dispose':
          rig.disposeSync();
      }
      gate.complete();
      await syncing;
      unregister();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 0);
    });
  }

  for (final event in ['pause', 'stop', 'book change', 'app hide']) {
    testUpload('$event uploads the newest durable place', (tester, rig) async {
      rig.engine.emit(0, 4321, playing: true);
      switch (event) {
        case 'pause':
          await rig.player.pause();
        case 'stop':
          await rig.player.stop();
        case 'book change':
          await rig.player.open(otherBook, otherEdition);
        case 'app hide':
          rig.sync.resume();
          rig.sync.suspend();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 4321);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
      // Reopening storage proves that the uploaded place was durable.
      final reopened = LocalResumeStore(hop: inlineHop);
      final saved = (await reopened.read(rig.account))!;
      expect(saved['resumes']['recording'].single['milliseconds'], 4321);
    });
  }

  testUpload('ordinary persistence finishes while an upload is blocked', (
    tester,
    rig,
  ) async {
    rig.gate = Completer<void>();
    rig.engine.emit(0, 1500, playing: true);
    await rig.player.pause();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.exchanges, 1);
    rig.engine.emit(0, 2500);
    await rig.player.flush();
    expect(
      (await rig.records.read(
        rig.account,
      ))!['resumes']['recording'].single['milliseconds'],
      2500,
    );
    expect(rig.gate!.isCompleted, isFalse);
    rig.gate!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.sentPlace('recording'), 2500);
    expect(await rig.records.pendingUploads(rig.account), isEmpty);
  });

  testUpload(
    'nearby pause stop and hide events combine and keep the final save',
    (tester, rig) async {
      rig.engine.emit(0, 1234, playing: true);
      await rig.player.pause();
      await tester.pump(const Duration(milliseconds: 50));
      rig.engine.emit(0, 2345);
      await rig.player.stop();
      rig.sync.suspend();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 1);
      expect(rig.sentPlace('recording'), 2345);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
    },
  );

  testUpload(
    'background listening uploads at ten seconds of audio progress and stops when idle',
    (tester, rig) async {
      rig.engine.emit(0, 9000, playing: true);
      await rig.player.flush();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 0);
      rig.engine.emit(0, 10000, playing: true);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 10000);
      rig.engine.emit(0, 20000, playing: true);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 20000);
      await rig.player.pause();
      await tester.pump(const Duration(seconds: 1));
      final exchanges = rig.exchanges;
      await tester.pump(const Duration(minutes: 5));
      expect(rig.exchanges, exchanges);
    },
  );

  testUpload(
    'a failed upload keeps actions without an idle retry and a later pause retries',
    (tester, rig) async {
      rig.fail = true;
      rig.engine.emit(0, 3210, playing: true);
      await rig.player.pause();
      final pending = await rig.records.pendingUploads(rig.account);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 1);
      expect(await rig.records.pendingUploads(rig.account), pending);
      expect(rig.sync.message, isNull);
      expect(rig.sync.busy, isFalse);
      await tester.pump(const Duration(minutes: 5));
      expect(rig.exchanges, 1);
      rig.fail = false;
      await rig.player.pause();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 3210);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
    },
  );

  testUpload('hiding with no pending records makes no exchange', (
    tester,
    rig,
  ) async {
    rig.sync.suspend();
    await tester.pump(const Duration(minutes: 5));
    expect(rig.exchanges, 0);
  });

  for (final change in ['sign out', 'account', 'dispose']) {
    testUpload('$change cancels the scheduled old-account upload', (
      tester,
      rig,
    ) async {
      rig.engine.emit(0, 3210, playing: true);
      await rig.player.pause();
      switch (change) {
        case 'sign out':
          rig.sync.bind(null);
        case 'account':
          rig.sync.bind(audio.account(user: 'bob'));
        case 'dispose':
          rig.disposeSync();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 0);
      expect(await rig.records.pendingUploads(rig.account), isNotEmpty);
      rig.sync.checkInvariants();
    });
  }

  testUpload(
    'a pending event waits for an earlier exchange and sends its later save',
    (tester, rig) async {
      rig.gate = Completer<void>();
      final first = rig.sync.synchronize();
      await tester.pump();
      rig.engine.emit(0, 4567, playing: true);
      await rig.player.pause();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.exchanges, 1);
      rig.gate!.complete();
      await first;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.sentPlace('recording'), 4567);
      expect(await rig.records.pendingUploads(rig.account), isEmpty);
    },
  );

  testUpload('resume and manual sync retry failed pending uploads', (
    tester,
    rig,
  ) async {
    rig.engine.emit(0, 6789, playing: true);
    await rig.player.pause();
    rig.fail = true;
    await tester.pump(const Duration(seconds: 1));
    rig.fail = false;
    rig.sync.resume();
    await tester.pump(const Duration(seconds: 1));
    expect(rig.sentPlace('recording'), 6789);
    rig.engine.emit(0, 7890);
    await rig.sync.syncNow();
    expect(rig.sentPlace('recording'), 7890);
  });
}

void testUpload(
  String name,
  Future<void> Function(WidgetTester, UploadRig) body,
) {
  testWidgets(name, (tester) async {
    final rig = await UploadRig.open(tester);
    try {
      await body(tester, rig);
    } finally {
      await rig.close(tester);
    }
  });
}

Future<R> inlineHop<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);

class UploadRig {
  UploadRig({this.reports});
  final LiveReports? reports;
  final records = DelayedRecords();
  final engine = FailingEngine();
  final downloads = audio.LocalFiles();
  late final player = Playback(
    downloads: downloads,
    engine: engine,
    store: records,
    reports: reports,
  );
  late final sync = RecordSync(
    records: records,
    transport: ControlledTransport(records, exchange),
  );
  final account = audio.account().scope.key;
  final sent = <Map<String, dynamic>>[];
  int exchanges = 0;
  bool fail = false;
  bool disposed = false;
  Completer<void>? gate;

  static Future<UploadRig> open(
    WidgetTester tester, {
    LiveReports? reports,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final rig = UploadRig(reports: reports);
    await rig.player.bind(audio.account(), [audio.title, otherBook]);
    await rig.player.open(audio.title, audio.recording);
    rig.sync.bind(audio.account());
    await rig.sync.synchronize();
    rig.sync.suspend();
    await tester.pump(const Duration(seconds: 1));
    rig.exchanges = 0;
    rig.sent.clear();
    return rig;
  }

  Future<SyncReport> exchange(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    exchanges++;
    final actions = await records.pendingUploads(session.scope.key);
    await gate?.future;
    if (fail) throw Exception('offline');
    for (final action in actions) {
      expectSync(action['account'], session.scope.key);
      sent.add(action);
      await records.acknowledge(
        session.scope.key,
        RecordJournal.identity(action),
      );
    }
    return (replaced: 0);
  }

  int? sentPlace(String edition) {
    final places = sent.where((action) {
      final address = RecordAddress.parse(action['record'] as String);
      return address.domain == 'audio' &&
          address.collection == 'resumes' &&
          action['value']?['edition'] == edition;
    });
    return places.isEmpty ? null : places.last['value']['milliseconds'] as int;
  }

  Future<void> close(WidgetTester tester) async {
    for (final pending in [gate, records.gate]) {
      if (pending != null && !pending.isCompleted) pending.complete();
    }
    disposeSync();
    engine.failPause = false;
    await tester.pump();
    var closed = false;
    final closing = player.close().then((_) => closed = true);
    // Stream cancellation can finish in the root zone. Let its microtasks
    // run as well as fake-time work, without advancing time or sleeping.
    for (var turn = 0; !closed && turn < 20; turn++) {
      await tester.pump();
      await tester.runAsync(() async {});
    }
    expect(closed, isTrue, reason: 'fixture playback closes');
    await closing;
    downloads.dispose();
  }

  void disposeSync() {
    if (disposed) return;
    disposed = true;
    sync.dispose();
  }
}

class DelayedRecords extends LocalResumeStore {
  DelayedRecords() : super(hop: inlineHop);
  Completer<void>? gate;

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    await gate?.future;
    await super.save(accountKey, changes);
  }
}

class SlowReports extends JellyfinClient {
  SlowReports() : super(audio.account().scope.server, deviceId: 'test');
  Completer<void>? gate;

  @override
  Future<void> reportPlayback(
    JellyfinSession session,
    String event,
    Map<String, dynamic> body,
  ) async {
    await gate?.future;
  }
}

class FailingEngine extends HeldEngine {
  bool failPause = false;

  @override
  Future<void> pause() async {
    if (failPause) throw Exception('audio device unavailable');
    await super.pause();
  }
}
