// Downloads prepares each saved ebook for reading once its download
// completes, and again at each launch, so that the reader's first open of
// it finds the work done (boo-sy2d). The preparation writes files derived
// from the download, so Downloads holds the download while it runs: a
// removal waits for it, and other reads do not (t4-3o9f).
import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transfer_test.dart' show MediaFixture;

void main() {
  late MediaFixture fixture;
  late Directory root;
  late MediaPolicy policy;
  final opened = <LocalDownloads>[];

  /// The preparations that Downloads asked for, in order: the source and
  /// the verified file of each.
  late List<(SourceFile, VerifiedFile)> prepared;

  /// What each preparation waits for before it ends, when set.
  Completer<void>? gate;

  /// Downloads under [root] that prepare each saved ebook as the tests
  /// record it.
  Future<LocalDownloads> open() async {
    final downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
      prepare: (original, source) async {
        prepared.add((source, original));
        await gate?.future;
      },
    );
    opened.add(downloads);
    await downloads.bind(fixture.session(), fixture.books);
    return downloads;
  }

  /// Ends [downloads], as the app's exit does.
  Future<void> close(LocalDownloads downloads) async {
    opened.remove(downloads);
    downloads.dispose();
    await downloads.idle;
  }

  setUp(() async {
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-prepared-');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    prepared = [];
    gate = null;
  });

  tearDown(() async {
    if (gate case final gate? when !gate.isCompleted) gate.complete();
    for (final downloads in opened) {
      downloads.dispose();
      await downloads.idle;
    }
    opened.clear();
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });

  /// The saved file of the one preparation that Downloads asked for.
  File saved() => File.fromUri(prepared.single.$2.uri);

  group('preparing saved ebooks', () {
    test('a downloaded ebook is prepared once, with the file that Downloads '
        'verified', () async {
      final downloads = await open();
      await downloads.request(fixture.text);
      await downloads.idle;

      expect(prepared, hasLength(1));
      final (source, original) = prepared.single;
      expect(source.key, fixture.text.files.single.key);
      final local = await downloads.localFile(fixture.text.files.single);
      expect(original.uri, local);
      expect(await File.fromUri(original.uri).readAsBytes(), fixture.payload);
    });

    test('a downloaded audiobook is not prepared', () async {
      final downloads = await open();
      await downloads.request(fixture.audio);
      await downloads.idle;

      expect(downloads.status(fixture.audio).phase, DownloadPhase.downloaded);
      expect(prepared, isEmpty);
    });

    test('each saved ebook is prepared again at the next launch', () async {
      final first = await open();
      await first.request(fixture.text);
      await first.request(fixture.audio);
      await first.idle;
      await close(first);
      prepared.clear();

      final next = await open();
      await next.idle;

      expect(
        [for (final (source, _) in prepared) source.key],
        [fixture.text.files.single.key],
      );
    });

    test('the download is ready to read while it is prepared', () async {
      gate = Completer<void>();
      final downloads = await open();
      await downloads.request(fixture.text);
      await _until(() => prepared.isNotEmpty);

      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      final read = await downloads.readLocalFile(
        fixture.text.files.single,
        (original) async => original.digest,
      );
      expect(read, isNotNull);
    });

    test(
      'a removal of the download waits until its preparation ends',
      () async {
        gate = Completer<void>();
        final downloads = await open();
        await downloads.request(fixture.text);
        await _until(() => prepared.isNotEmpty);
        final file = saved();

        var removed = false;
        final removal = downloads
            .remove(fixture.text)
            .then((_) => removed = true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(removed, isFalse);
        expect(await file.exists(), isTrue);

        gate!.complete();
        await removal;
        expect(await file.parent.exists(), isFalse);
      },
    );

    test(
      'a read of another download does not wait for a preparation',
      () async {
        final first = await open();
        await first.request(fixture.text);
        await first.request(fixture.audio);
        await first.idle;
        await close(first);
        prepared.clear();
        gate = Completer<void>();

        final next = await open();
        await _until(() => prepared.isNotEmpty);
        final read = await next
            .readLocalFile(
              fixture.audio.files.first,
              (original) async => original.digest,
            )
            .timeout(const Duration(seconds: 5));
        expect(read, isNotNull);
        expect(gate!.isCompleted, isFalse);
      },
    );

    test('a preparation that fails leaves the download whole', () async {
      final downloads = LocalDownloads(
        root: root,
        freeBytes: () async => 1000000,
        policy: policy,
        prepare: (original, source) async =>
            throw const FormatException('This EPUB is damaged.'),
      );
      opened.add(downloads);
      await downloads.bind(fixture.session(), fixture.books);
      await downloads.request(fixture.text);
      await downloads.idle;

      expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
      expect(downloads.status(fixture.text).message, isNull);
    });
  });

  group('work that a read holds', () {
    test(
      'a removal waits for the work that a read of the download holds',
      () async {
        final downloads = await open();
        await downloads.request(fixture.text);
        await downloads.idle;
        final held = Completer<void>();
        File? file;
        await downloads.readLocalFile(fixture.text.files.single, (original) {
          file = File.fromUri(original.uri);
          unawaited(original.hold(() => held.future));
          return Future.value();
        });

        var removed = false;
        final removal = downloads
            .remove(fixture.text)
            .then((_) => removed = true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(removed, isFalse);
        expect(await file!.exists(), isTrue);

        held.complete();
        await removal;
        expect(await file!.parent.exists(), isFalse);
      },
    );

    test('work that a read holds after a removal began does not run', () async {
      final downloads = await open();
      await downloads.request(fixture.text);
      await downloads.idle;
      final reading = Completer<void>();
      final removing = Completer<void>();
      var ran = false;
      final read = downloads.readLocalFile(fixture.text.files.single, (
        original,
      ) async {
        reading.complete();
        await removing.future;
        await original.hold(() async => ran = true);
      });
      await reading.future;
      final removal = downloads.remove(fixture.text);
      removing.complete();
      await read;
      await removal;

      expect(ran, isFalse);
    });

    test('a hold after the read and its held work ended is refused', () async {
      final downloads = await open();
      await downloads.request(fixture.text);
      await downloads.idle;
      late VerifiedFile lent;
      await downloads.readLocalFile(fixture.text.files.single, (
        original,
      ) async {
        lent = original;
        await original.hold(() async {});
      });

      expect(() => lent.hold(() async {}), throwsStateError);
    });

    test(
      'a file that Downloads did not lend runs its held work at once',
      () async {
        var ran = false;
        await VerifiedFile(
          Uri.file('/nowhere/complete'),
          'digest',
        ).hold(() async => ran = true);
        expect(ran, isTrue);
      },
    );
  });
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
