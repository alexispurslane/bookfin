// An on-demand host benchmark of the load of a book, as the reader loads
// it (boo-yjq6): the admission of the whole book, a fresh load that admits
// the book and keeps its record, and a cached load that reads the record.
// It is not part of Bookfin's normal test run, because its times come from
// a shared machine.
//
// In the dev shell, from the repository root, with the books of
// docs/plans/faster-book-open.md in one folder (prose.epub, long.epub,
// illustrated.epub, divine.epub, and wealth.azw3):
//
//   BOOKFIN_ADMISSION_BENCHMARK=<folder> flutter test \
//     test/reader/epub/admission_benchmark_test.dart
//
// It prints one line per book: the median of each measure over the rounds,
// in milliseconds. BOOKFIN_ADMISSION_ROUNDS sets the number of rounds (5).
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/derived_files.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _books = [
  'prose.epub',
  'long.epub',
  'illustrated.epub',
  'divine.epub',
  'wealth.azw3',
];

double _median(List<int> microseconds) {
  final sorted = [...microseconds]..sort();
  return sorted[sorted.length ~/ 2] / 1000;
}

void main() {
  final folder = Platform.environment['BOOKFIN_ADMISSION_BENCHMARK'];
  if (folder == null) {
    test(
      'the admission benchmark',
      () {},
      skip: 'set BOOKFIN_ADMISSION_BENCHMARK to a folder of books to run',
    );
    return;
  }
  final rounds = int.parse(
    Platform.environment['BOOKFIN_ADMISSION_ROUNDS'] ?? '5',
  );
  for (final name in _books) {
    test(name, () async {
      final original = File('$folder/$name');
      if (!original.existsSync()) {
        markTestSkipped('$folder/$name is not here.');
        return;
      }
      final directory = await Directory.systemTemp.createTemp('admission-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await original.copy('${directory.path}/complete');
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final container = name.split('.').last;
      final source = SourceFile(
        itemId: name,
        displayName: name,
        mediaSourceId: name,
        revision: '1',
        container: container,
        durationMs: null,
        sizeBytes: bytes.length,
      );
      final verified = VerifiedFile(file.uri, digest);
      final admit = <int>[];
      final fresh = <int>[];
      final cached = <int>[];
      // One round before the measured ones warms the JIT.
      for (var round = -1; round < rounds; round++) {
        final watch = Stopwatch();
        if (container == 'epub') {
          watch.start();
          Publication.admit(bytes, digest);
          if (round >= 0) admit.add(watch.elapsedMicroseconds);
        }
        for (final derived in [
          DerivedBookFiles.admittedDirectory(file),
          DerivedBookFiles.mobiDirectory(file),
        ]) {
          if (await derived.exists()) await derived.delete(recursive: true);
        }
        watch.reset();
        watch.start();
        final first = await loadReadingDocument(verified, source);
        if (round >= 0) fresh.add(watch.elapsedMicroseconds);
        await first.dispose();
        watch.reset();
        watch.start();
        final second = await loadReadingDocument(verified, source);
        if (round >= 0) cached.add(watch.elapsedMicroseconds);
        await second.dispose();
      }
      // ignore: avoid_print
      print(
        'ADMISSION_BENCHMARK $name '
        'admit=${admit.isEmpty ? '-' : _median(admit)} '
        'fresh=${_median(fresh)} cached=${_median(cached)} ms '
        '(median of $rounds)',
      );
    }, timeout: Timeout.none);
  }
}
