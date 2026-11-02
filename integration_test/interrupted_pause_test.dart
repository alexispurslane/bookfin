import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

import '../test/playback/playback_test.dart'
    show LocalFiles, MemoryResume, account, first, second, title, recording;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual Pause during lost focus prevents decoder recovery', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('bookfin-focus-');
      final downloads = LocalFiles();
      final decoder = AudioPlayer();
      final engine = LocalAudioEngine(player: decoder);
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: MemoryResume(),
      );
      final handler = await AudioService.init(
        builder: PlaybackHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.bookfin.playback',
          androidNotificationChannelName: 'Bookfin listening',
          androidNotificationIcon: 'drawable/bookfin_launcher',
          androidStopForegroundOnPause: false,
        ),
      );
      handler.attach(playback);
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      final lost = Completer<void>();
      final returned = Completer<void>();
      final interruption = session.interruptionEventStream.listen((event) {
        if (event.begin && !lost.isCompleted) lost.complete();
        if (!event.begin && !returned.isCompleted) returned.complete();
      });
      try {
        for (final source in [first, second]) {
          final file = File('${directory.path}/${source.itemId}.wav');
          await file.writeAsBytes(wave(source.durationMs! ~/ 1000));
          downloads.files[source.key] = file.uri;
        }
        await playback.bind(account(), [title]);
        await playback.open(title, recording);
        await playback.seekEdition(15000);
        await decoder.playerStateStream.firstWhere((state) => state.playing);
        debugPrint('FOCUS_TEST_READY: send a T3 synthetic call now');
        await lost.future.timeout(const Duration(seconds: 120));
        await decoder.playerStateStream.firstWhere((state) => !state.playing);
        final before = decoder.position.inMilliseconds;
        expect(before, greaterThanOrEqualTo(15000));
        await handler.pause();
        await playback.flush();
        expect(playback.playing, isFalse);
        expect(playback.position?.milliseconds, before);
        debugPrint('FOCUS_TEST_PAUSED: retained=$before; end the T3 call now');
        await returned.future.timeout(const Duration(seconds: 120));
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(decoder.playing, isFalse);
        expect(playback.playing, isFalse);
        expect(decoder.position.inMilliseconds, before);
        expect(playback.position?.milliseconds, before);
        playback.checkInvariants();
        debugPrint('FOCUS_TEST_VERIFIED: no recovery; retained=$before');
      } finally {
        await interruption.cancel();
        await playback.close();
        downloads.dispose();
        await directory.delete(recursive: true);
      }
    });
  });
}

Uint8List wave(int seconds) {
  final bytes = Uint8List(44 + seconds * 22050 * 2);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 22050, Endian.little);
  data.setUint32(28, 44100, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, bytes.length - 44, Endian.little);
  for (var index = 44; index < bytes.length; index += 2) {
    data.setInt16(index, (index ~/ 50).isEven ? 64 : -64, Endian.little);
  }
  return bytes;
}
