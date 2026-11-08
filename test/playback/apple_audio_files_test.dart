import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/playback/apple_audio_files.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(64, 0)]);

void main() {
  group('the audio format of a download, from its first bytes', () {
    test('an MP4 file such as an M4B audiobook is m4a', () {
      expect(
        audioExtension(_bytes([0, 0, 0, 0x20, ...'ftypM4B '.codeUnits])),
        'm4a',
      );
    });

    test('an MP3 file is mp3, with or without an ID3 tag', () {
      expect(audioExtension(_bytes('ID3'.codeUnits)), 'mp3');
      expect(audioExtension(_bytes([0xFF, 0xFB, 0x90, 0x64])), 'mp3');
    });

    test('FLAC, WAV and AIFF files keep their own formats', () {
      expect(audioExtension(_bytes('fLaC'.codeUnits)), 'flac');
      expect(
        audioExtension(
          _bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits]),
        ),
        'wav',
      );
      expect(
        audioExtension(
          _bytes([...'FORM'.codeUnits, 0, 0, 0, 0, ...'AIFF'.codeUnits]),
        ),
        'aiff',
      );
    });

    test('a format that Apple cannot name from its bytes has none', () {
      expect(audioExtension(_bytes('OggS'.codeUnits)), isNull);
      expect(audioExtension(Uint8List(2)), isNull);
    });
  });

  group('a playable name for a download', () {
    late Directory directory;
    late Directory links;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('bookfin-apple-audio-');
      links = Directory('${directory.path}/links');
    });
    tearDown(() => directory.delete(recursive: true));

    test('names the same bytes with the extension of their format', () async {
      final download = File('${directory.path}/complete');
      await download.writeAsBytes(
        _bytes([0, 0, 0, 0x20, ...'ftypM4A '.codeUnits]),
      );

      final playable = await playableAudioFile(download.uri, links: links);

      expect(playable.path, endsWith('.m4a'));
      expect(
        await File.fromUri(playable).readAsBytes(),
        await download.readAsBytes(),
      );
    });

    test(
      'names each download once, and the name follows a new download',
      () async {
        final download = File('${directory.path}/complete');
        await download.writeAsBytes(_bytes('ID3'.codeUnits));
        final first = await playableAudioFile(download.uri, links: links);

        await download.delete();
        await download.writeAsBytes(
          _bytes([0, 0, 0, 0x20, ...'ftypM4A '.codeUnits]),
        );
        final second = await playableAudioFile(download.uri, links: links);

        expect(first.path, endsWith('.mp3'));
        expect(second.path, endsWith('.m4a'));
        expect(
          await File.fromUri(second).readAsBytes(),
          await download.readAsBytes(),
        );
        expect(await File.fromUri(first).exists(), isFalse);
      },
    );

    test(
      'leaves a download with an extension or an unknown format as it is',
      () async {
        final named = File('${directory.path}/book.mp3');
        await named.writeAsBytes(_bytes('ID3'.codeUnits));
        final unknown = File('${directory.path}/complete');
        await unknown.writeAsBytes(_bytes('OggS'.codeUnits));

        expect(await playableAudioFile(named.uri, links: links), named.uri);
        expect(await playableAudioFile(unknown.uri, links: links), unknown.uri);
      },
    );
  });
}
