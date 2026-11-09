// An on-demand benchmark of the native pager's scrub deck pages on a
// device. It opens a made-up book of six long sections, shows its first
// page, and then draws every deck page of the book in order, as a drag over
// the whole book would. It prints the time of each page from the request to
// the drawn image, split into pages in a section and first pages of a new
// section, with the tag DECK_BENCHMARK.
//
// The book opens OPEN_AFTER_MS milliseconds (3000 by default) after the
// app's first frame is drawn, as a book opens in an app that is running.
// In about the first second after the process starts, the engine compiles
// its shader programs on the raster thread, and Android's own start work
// competes for the processor. A deck page drawn in that time waits for
// both: on an emulator, 0.1 to 0.8 s for the first page (te-k1l3). To
// measure that case, open the book at the first frame:
//
//   flutter build apk --profile -t tool/reader/deck_benchmark.dart \
//     --dart-define=OPEN_AFTER_MS=0
//
// Build and run it as a profile build on a device that no one else uses:
//
//   flutter build apk --profile -t tool/reader/deck_benchmark.dart
//   adb -s <device> install -r build/app/outputs/flutter-apk/app-profile.apk
//
// Start the app on the device, and read the result from the log:
//
//   adb -s <device> logcat -d | grep DECK_BENCHMARK
import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';

import '../showcase_media.dart' as media;

/// The time from the app's first frame to the book's opening.
const _openAfter = Duration(
  milliseconds: int.fromEnvironment('OPEN_AFTER_MS', defaultValue: 3000),
);

void main() => runApp(const MaterialApp(home: _Benchmark()));

class _Benchmark extends StatefulWidget {
  const _Benchmark();

  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark> {
  String _result = 'Measuring';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_measure()));
  }

  Future<void> _measure() async {
    final view = View.of(context);
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await Future<void>.delayed(_openAfter);
    final chapters = [
      for (var section = 0; section < 6; section++)
        (
          'Section ${section + 1}',
          [
            for (var paragraph = 0; paragraph < 60; paragraph++)
              List.generate(
                6,
                (sentence) =>
                    'Part $section paragraph $paragraph sentence $sentence. '
                    'The reader followed the shoreline and watched the small '
                    'boats return.',
              ).join(' '),
          ],
        ),
    ];
    final publication = Publication.admit(
      media.epub('bench', 'Deck Benchmark', 'Bookfin', chapters),
    );
    // The window can have no size yet in the first frame.
    while (view.physicalSize.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final size = view.physicalSize / view.devicePixelRatio;
    final pager = EpubPager(
      EpubDocument(publication),
      onPlace: (_) {},
      onWarning: (_) {},
    );
    final shown = Completer<void>();
    pager.shown.addListener(() {
      if (pager.shown.value != null && !shown.isCompleted) shown.complete();
    });
    pager.present(
      PageSettings(
        width: size.width,
        height: size.height,
        fontSize: 20,
        night: false,
      ),
    );
    await shown.future;

    final width = (size.width * view.devicePixelRatio / 3).roundToDouble();
    final abandon = Completer<void>().future;
    final inSection = <Duration>[];
    final newSection = <Duration>[];
    final watch = Stopwatch()..start();
    var preview = await pager.preview((part: 0, progress: 0), width, abandon);
    final first = watch.elapsed;
    final opening = [first];
    var drawn = 2;
    var slowest = (0, Duration.zero);
    for (var next = preview.next; next != null; next = preview.next) {
      final part = preview.part;
      preview.image.dispose();
      watch.reset();
      preview = await pager.preview(next, width, abandon);
      final elapsed = watch.elapsed;
      (preview.part == part ? inSection : newSection).add(elapsed);
      if (opening.length < 6) opening.add(elapsed);
      if (elapsed > slowest.$2) slowest = (drawn, elapsed);
      drawn++;
    }
    preview.image.dispose();
    pager.dispose();

    String times(List<Duration> times) {
      times.sort();
      return '${times.length} pages, median '
          '${times[times.length ~/ 2].inMilliseconds} ms, p90 '
          '${times[times.length * 9 ~/ 10].inMilliseconds} ms, slowest '
          '${times.last.inMilliseconds} ms';
    }

    final result =
        'opened ${_openAfter.inMilliseconds} ms after the first frame; '
        'card width $width px; first page ${first.inMilliseconds} ms; '
        'first six pages ${opening.map((time) => time.inMilliseconds).join(', ')} ms; '
        'in a section: ${times(inSection)}; '
        'first page of a new section: ${times(newSection)}; the slowest '
        'is deck page ${slowest.$1}';
    debugPrint('DECK_BENCHMARK $result');
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(_result)),
    ),
  );
}
