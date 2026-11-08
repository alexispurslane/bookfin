import 'dart:io';

import 'package:bookfin/catalog/covers_io.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/downloads/platform_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The media host contract is what a platform's runner answers on
// `bookfin/media`. These tests run as macOS, the first runner beside
// Android's that answers it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('bookfin/media');
  const network = EventChannel('bookfin/media-network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  void answerContract() => messenger.setMockMethodCallHandler(
    methods,
    (call) async => switch (call.method) {
      'storage' => {'path': '${directory.path}/bookfin-media'},
      'freeBytes' => 5000000000,
      'network' => 'wifi',
      _ => null,
    },
  );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    directory = await Directory.systemTemp.createTemp('bookfin-media-host-');
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(network, null);
    await directory.delete(recursive: true);
  });

  test('a runner with the media host contract gives downloads in the directory that it names', () async {
    answerContract();

    final downloads = await createDownloads(MediaPolicy());

    expect(downloads.supported, isTrue);
    expect(
      (downloads as LocalDownloads).root.path,
      '${directory.path}/bookfin-media',
    );
    expect(await downloads.freeBytes(), 5000000000);
    downloads.dispose();
  });

  test(
    'the network kind that the runner sends decides whether media streams',
    () async {
      answerContract();
      messenger.setMockStreamHandler(
        network,
        MockStreamHandler.inline(
          onListen: (arguments, events) => events.success('mobile'),
        ),
      );
      final policy = MediaPolicy();

      final downloads = await createDownloads(policy);
      await pumpEventQueue();

      expect(policy.network, MediaNetwork.mobile);
      expect(policy.choose(verifiedLocal: false), MediaLocation.blocked);
      downloads.dispose();
    },
  );

  test(
    'a runner without the media host contract gives unavailable downloads',
    () async {
      final downloads = await createDownloads(MediaPolicy());

      expect(downloads.supported, isFalse);
    },
  );

  test(
    'covers live beside the download directory that the runner names',
    () async {
      answerContract();

      final covers = await createCovers();

      expect(
        (covers! as DiskCovers).root.path,
        '${directory.path}/bookfin-covers',
      );
    },
  );
}
