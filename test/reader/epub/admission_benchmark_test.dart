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
//
// It also times each EPUB's pager, from its construction to the shown page
// at the plan's section, when the reader's first layout presents the page
// settings 12 ms after the construction, about the settings wait that the
// plan measured on the phone. It does so without and with this phone's
// last page settings ([EpubPager]'s expected settings).
import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/derived_files.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler;

/// The books, and the section that each opens at, as the plan's device
/// runs open them.
const _books = {
  'prose.epub': 4,
  'long.epub': 59,
  'illustrated.epub': 5,
  'divine.epub': 8,
  'wealth.azw3': 20,
};

/// The time in microseconds from a new pager of [document] at the start of
/// section [index] to its shown page, when the page settings come 12 ms
/// after the pager, and the pager [knows] them from the start.
Future<int> _pagerOpen(
  EpubDocument document,
  int index, {
  required bool knows,
}) async {
  final publication = document.publication;
  final scheduler = TestScheduler();
  final watch = Stopwatch()..start();
  final pager = EpubPager(
    document,
    source: PageSource(publication, schedule: scheduler.schedule),
    initial: EpubAddress(
      ReadingLocation(
        'epubcfi(${publication.spineSteps[index]}!/4)',
        publication.spine[index],
        '',
      ),
    ),
    expected: knows ? readerPage : null,
    onPlace: (_) {},
    onWarning: (message) => throw StateError(message),
  );
  final shown = Completer<void>();
  pager.shown.addListener(() {
    if (!shown.isCompleted) shown.complete();
  });
  await Future<void>.delayed(const Duration(milliseconds: 12));
  pager.present(readerPage);
  await scheduler.until(shown.future);
  final time = watch.elapsedMicroseconds;
  pager.dispose();
  return time;
}

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
  setUpAll(loadReaderFont);
  for (final MapEntry(key: name, value: section) in _books.entries) {
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
      final unknown = <int>[];
      final known = <int>[];
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
        for (final knows in [false, true]) {
          final time = await _pagerOpen(
            second as EpubDocument,
            section,
            knows: knows,
          );
          if (round >= 0) (knows ? known : unknown).add(time);
        }
        await second.dispose();
      }
      // ignore: avoid_print
      print(
        'ADMISSION_BENCHMARK $name '
        'admit=${admit.isEmpty ? '-' : _median(admit)} '
        'fresh=${_median(fresh)} cached=${_median(cached)} ms; pager to '
        'the shown page ${_median(unknown)} -> ${_median(known)} ms with '
        'the last page settings (median of $rounds)',
      );
    }, timeout: Timeout.none);
  }
}
