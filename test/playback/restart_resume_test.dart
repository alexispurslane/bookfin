import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/phone.dart';
import 'held_engine.dart';
import 'playback_test.dart' as audio;

/// boo-jxf9: after a restart, Resume opened an audiobook at 0:00 while
/// another device's saved place waited as a sync choice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite' : 'preferences', () {
      Phone? phone;
      late audio.LocalFiles downloads;
      late HeldEngine engine;
      late Playback player;
      final account = audio.account().scope.key;

      LocalResumeStore newStore() => LocalResumeStore(
        openDatabase: sqlite ? () async => phone!.database : null,
      );

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (sqlite) phone = await Phone.open('restart-resume');
        downloads = audio.LocalFiles();
        engine = HeldEngine();
        player = Playback(
          downloads: downloads,
          engine: engine,
          store: newStore(),
        );
        await player.bind(audio.account(), [audio.title]);
      });

      tearDown(() async {
        engine.release();
        await player.close();
        downloads.dispose();
      });

      /// A tablet that never saw this phone's place saves its own, so the
      /// two places compete until the person chooses one.
      Future<void> tabletSavesWithoutSeeingThisPhone(
        LocalResumeStore store,
        int milliseconds,
      ) async {
        final tablet = RecordJournal(account, 'tablet');
        tablet.change(resumeRecordAddress(audio.recording), {
          'edition': audio.recording.id,
          'source': audio.first.key,
          'revision': audio.first.revision,
          'sources': editionSources(audio.recording),
          'milliseconds': milliseconds,
          'pendingOffline': false,
        }, device: 'Pixel Tablet');
        await store.receivePage(account, tablet.uploads, 0);
        await player.refreshPersonalRecords();
      }

      Future<void> restart() async {
        await player.close();
        engine.release();
        if (sqlite) await phone!.restart();
        engine = HeldEngine();
        player = Playback(
          downloads: downloads,
          engine: engine,
          store: newStore(),
        );
        await player.bind(audio.account(), [audio.title]);
      }

      test(
        'after a restart, Resume opens at the place this phone saved last while a sync choice waits',
        () async {
          final store = player.store as LocalResumeStore;
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.seekEdition(11000);
          await player.flush();
          await tabletSavesWithoutSeeingThisPhone(store, 40000);
          expect(
            await store.listeningResume(account, audio.recording),
            isNull,
            reason: 'the two saved places compete as a sync choice',
          );

          // The person keeps listening on this phone while the choice waits.
          await player.seekEdition(15000);
          await player.flush();

          await restart();
          await player.open(audio.title, audio.recording, autoplay: false);

          expect(player.position!.milliseconds, 15000);
          player.checkInvariants();
        },
      );

      test(
        'after a restart, Resume opens at this phone\'s place when it saved nothing since the sync choice arrived',
        () async {
          final store = player.store as LocalResumeStore;
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.seekEdition(11000);
          await player.flush();
          await tabletSavesWithoutSeeingThisPhone(store, 40000);

          await restart();
          await player.open(audio.title, audio.recording, autoplay: false);

          expect(player.position!.milliseconds, 11000);
          player.checkInvariants();
        },
      );

      test(
        'listening on after a restart keeps the sync choice and the other device\'s place',
        () async {
          final store = player.store as LocalResumeStore;
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.seekEdition(11000);
          await player.flush();
          await tabletSavesWithoutSeeingThisPhone(store, 40000);

          await restart();
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.seekEdition(18000);
          await player.flush();

          final restarted = player.store as LocalResumeStore;
          expect(
            await restarted.listeningResume(account, audio.recording),
            isNull,
            reason: 'only the person settles a sync choice',
          );
          final versions = (await restarted.conflicts(
            account,
          )).values.single;
          expect(
            versions.map(
              (version) =>
                  (version.value!.position as AudioPosition).milliseconds,
            ),
            unorderedEquals([18000, 40000]),
          );
        },
      );

      test('a book with no saved place still opens at its start', () async {
        await restart();
        await player.open(audio.title, audio.recording, autoplay: false);

        expect(player.position!.milliseconds, 0);
        player.checkInvariants();
      });
    });
  }
}
