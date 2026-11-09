// An on-demand benchmark of the time from opening a real book to its first
// drawn page, on a device (boo-rw7u). It prints each result with the tag
// OPEN_BENCHMARK, as one JSON object per line.
//
// One launch measures one book. The host serves the book and a plan,
// plan.json, from one directory on port 8781, for example:
//
//   python3 -m http.server 8781 --bind 127.0.0.1 --directory <directory>
//   adb -s <device> reverse tcp:8781 tcp:8781
//
// The app keeps a copy of the book in its own storage, in a folder of its
// own, as a real download is, and reads it from there. As Downloads does, it
// hashes the copy once, and the reader takes that digest.
//
// The plan names the book, its container (epub or azw3), and the places
// that the runs use, as [section, progress] pairs:
//
//   {"book": "se-poetry.epub", "container": "epub", "place": [2, 0.5],
//    "turnFrom": 3, "jumpFrom": 5, "jumpTo": [2, 0.5], "warm": 5}
//
// A launch whose plan names a place without a known address only finds the
// saved addresses of the plan's places, as a reader who left the book there
// would have saved them, and keeps them in the app's cache directory. It
// also prints the size of each section. Each later launch measures, three
// seconds after the app's first frame (te-k1l3):
//
// - open: from reading the downloaded file to the first drawn page at the
//   saved place. The parts are admission (the read of the admitted book
//   that the first open kept, t7-rcyp), the pager's work up to the shown
//   page (prepare and anchored layout), and the first frame that draws it.
// - admitFull: after the runs, a full admission and the write of its
//   record, as at the first open after a download. For a MOBI, its kept
//   conversion is admitted again.
// - turn: a turn into the next section right after the book opens at the
//   last page of section turnFrom, while that section is not prepared yet.
// - jump: a scrub to jumpTo, after the book opened at jumpFrom and its
//   work around the shown page ended.
// - parts: the prepare of each section above in a worker, split into the
//   hop, the hyphenation patterns' load and the work; the same work in a
//   worker that prepared before, and the copy of its result through a port;
//   the font registration; and the layout and picture of the section's
//   middle page on a page source of its own.
//
// The first open, turn and jump of a launch are cold: the first in the
// process. Then each runs [warm] more times on new pagers.
//
// Build and run it as a profile build on a device that no one else uses:
//
//   flutter build apk --profile -t tool/reader/open_benchmark.dart
//   adb -s <device> install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s <device> logcat -d | grep OPEN_BENCHMARK
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/derived_files.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/hyphenate.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The host's server of the plan and the books, through `adb reverse`.
const _inbox = 'http://127.0.0.1:8781';

Future<List<int>> _fetch(String name) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse('$_inbox/$name')))
        .close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} for $name');
    }
    return [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
}

void main() => runApp(const MaterialApp(home: _Benchmark()));

class _Benchmark extends StatefulWidget {
  const _Benchmark();

  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark> {
  EpubPager? _pager;

  /// The settings of the last shown page: the viewport's page area.
  PageSettings? _settings;
  String _status = 'Measuring';

  /// The SHA-256 of the downloaded copy, as Downloads keeps it.
  late final String _digest;

  /// Every frame's timing that the engine reported, in arrival order.
  final _frames = <ui.FrameTiming>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_main()));
  }

  void _log(Map<String, Object?> result) =>
      debugPrint('OPEN_BENCHMARK ${jsonEncode(result)}');

  Future<void> _main() async {
    try {
      await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
      await Future<void>.delayed(const Duration(seconds: 3));
      final plan = jsonDecode(utf8.decode(await _fetch('plan.json'))) as Map;
      final book = plan['book'] as String;
      // The download, in the app's own storage as a real download is.
      final local = File('${Directory.systemTemp.path}/rw7u/$book/$book');
      if (!await local.exists()) {
        await local.parent.create(recursive: true);
        await local.writeAsBytes(await _fetch(book), flush: true);
      }
      final path = local.path;
      _digest = await Isolate.run(
        () async => (await sha256.bind(File(path).openRead()).first).toString(),
      );
      final addresses = File('${local.path}.addresses.json');
      final known = await addresses.exists()
          ? jsonDecode(await addresses.readAsString()) as Map
          : <String, Object?>{};
      if (_targets(plan).any((at) => !known.containsKey('${at.$1}:${at.$2}'))) {
        await _calibrate(plan, local, addresses);
      } else {
        await _measure(plan, local, known);
      }
      _log({'done': book});
      if (mounted) setState(() => _status = 'Done');
    } catch (error, stack) {
      _log({'error': '$error', 'stack': '$stack'});
    }
  }

  Future<EpubDocument> _load(Map plan, File local) async =>
      await loadReadingDocument(
        VerifiedFile(local.uri, _digest),
        SourceFile(
          itemId: 'bench',
          displayName: plan['book'] as String,
          mediaSourceId: 'bench',
          revision: '1',
          durationMs: null,
          container: plan['container'] as String,
          sizeBytes: await local.length(),
        ),
      ) as EpubDocument;

  List<(int, double)> _targets(Map plan) {
    (int, double) pair(Object? value) =>
        (((value as List)[0] as num).toInt(), (value[1] as num).toDouble());
    return [
      pair(plan['place']),
      (plan['turnFrom'] as int, 1.0),
      (plan['jumpFrom'] as int, 0.0),
    ];
  }

  /// Finds the saved address of each place of [plan], as a reader who left
  /// the book there would have saved it.
  Future<void> _calibrate(Map plan, File local, File addresses) async {
    // The first load of a MOBI also converts it.
    final start = Timeline.now;
    final document = await _load(plan, local);
    final admit = Timeline.now - start;
    final publication = document.publication;
    _log({
      'book': plan['book'],
      'firstAdmit': _ms(admit),
      'sections': [
        for (final path in publication.spine)
          publication.resources[path]!.length,
      ],
    });
    final found = <String, Object?>{};
    EpubAddress? last;
    final pager = EpubPager(
      document,
      onPlace: (address) => last = address,
      onWarning: (_) {},
    );
    await _showPager(pager);
    for (final (section, progress) in _targets(plan)) {
      await pager.seek(section, progress);
      found['$section:$progress'] = last!.toJson();
    }
    await _hide();
    pager.dispose();
    await addresses.writeAsString(jsonEncode(found));
    _log({'calibrated': plan['book'], 'addresses': found.length});
  }

  Future<void> _measure(Map plan, File local, Map addresses) async {
    final [place, turnFrom, jumpFrom] = _targets(plan);
    ReaderAddress address((int, double) target, EpubDocument document) =>
        document.decodeAddress(
          (addresses['${target.$1}:${target.$2}'] as Map)
              .cast<String, dynamic>(),
        );
    final warm = (plan['warm'] as int?) ?? 5;
    final jumpTo = plan['jumpTo'] as List;
    for (var run = 0; run <= warm; run++) {
      final cold = run == 0;

      // Open at the saved place.
      final start = Timeline.now;
      final document = await _load(plan, local);
      final admitted = Timeline.now;
      var pager = EpubPager(
        document,
        initial: address(place, document),
        onPlace: (_) {},
        onWarning: (_) {},
      );
      final (shown, drawn) = await _showPager(pager);
      _log({
        'kind': 'open',
        'book': plan['book'],
        'cold': cold,
        'admit': _ms(admitted - start),
        'toShown': _ms(shown - admitted),
        'toDrawn': _ms(drawn - shown),
        'total': _ms(drawn - start),
      });
      await _hide();
      pager.dispose();

      // A turn into the next section before it is prepared.
      pager = EpubPager(
        document,
        initial: address(turnFrom, document),
        onPlace: (_) {},
        onWarning: (_) {},
      );
      // The turn starts as soon as the page is shown, before the next
      // section's prepare can end.
      await _showPager(pager, draw: false);
      var moves = 0;
      var turned = Timeline.now;
      while (pager.shown.value!.page.section == turnFrom.$1) {
        turned = Timeline.now;
        await pager.move(true);
        moves++;
      }
      final turnShown = Timeline.now;
      final turnDrawn = await _drawnAfter(turnShown);
      _log({
        'kind': 'turn',
        'book': plan['book'],
        'cold': cold,
        'moves': moves,
        'toShown': _ms(turnShown - turned),
        'toDrawn': _ms(turnDrawn - turnShown),
        'total': _ms(turnDrawn - turned),
      });
      await _hide();
      pager.dispose();

      // A jump to a far section, once the work around the shown page ended.
      pager = EpubPager(
        document,
        initial: address(jumpFrom, document),
        onPlace: (_) {},
        onWarning: (_) {},
      );
      await _showPager(pager);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      // A turn inside a laid-out section, for comparison.
      final within = Timeline.now;
      await pager.move(true);
      final withinShown = Timeline.now;
      final withinDrawn = await _drawnAfter(withinShown);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final jumped = Timeline.now;
      await pager.seek(
        (jumpTo[0] as num).toInt(),
        (jumpTo[1] as num).toDouble(),
      );
      final jumpShown = Timeline.now;
      final jumpDrawn = await _drawnAfter(jumpShown);
      _log({
        'kind': 'jump',
        'book': plan['book'],
        'cold': cold,
        'toShown': _ms(jumpShown - jumped),
        'toDrawn': _ms(jumpDrawn - jumpShown),
        'total': _ms(jumpDrawn - jumped),
        'laidTurn': _ms(withinDrawn - within),
      });
      await _hide();
      pager.dispose();
    }

    // Full admissions, as at the first open after a download.
    for (var run = 0; run < 3; run++) {
      await DerivedBookFiles.admittedDirectory(local).delete(recursive: true);
      final start = Timeline.now;
      await _load(plan, local);
      _log({
        'kind': 'admitFull',
        'book': plan['book'],
        'admit': _ms(Timeline.now - start),
      });
    }

    // The parts, on their own, after the runs.
    final document = await _load(plan, local);
    final sections = {
      place.$1,
      turnFrom.$1 + 1,
      turnFrom.$1 - 1,
      (jumpTo[0] as num).toInt(),
    };
    for (final section in sections) {
      if (section < 0 || section >= document.publication.spine.length) {
        continue;
      }
      await _parts(plan, document, section);
    }
  }

  /// Measures the parts of preparing [section] and of showing its first
  /// page.
  Future<void> _parts(Map plan, EpubDocument document, int section) async {
    final publication = document.publication;
    final path = publication.spine[section];
    final xhtml = publication.resources[path]!;
    final styles = publication.bookStyles;
    final sizes = publication.imageSizes;
    final language = publication.language;
    final settings = _settings!;
    SectionSource source() => SectionSource(
      index: section,
      path: path,
      xhtml: utf8.decode(xhtml),
      fontPrefix: 'bookfin-probe',
      styleSheets: styles,
      imageSizes: sizes,
      language: language,
    );

    // A hop that carries the same arguments and does no work.
    var mark = Timeline.now;
    await Isolate.run(() => xhtml.length + styles.length + sizes.length);
    final hop = Timeline.now - mark;

    // A new worker, as each call is today: the hyphenation patterns load
    // first.
    mark = Timeline.now;
    final (hyphenation, work, prepared) = await Isolate.run(() {
      final watch = Stopwatch()..start();
      Hyphenator.forLanguage(language)?.breaks('representation');
      final hyphenation = watch.elapsedMicroseconds;
      watch.reset();
      final prepared = prepareSections([source()], settings).single;
      return (hyphenation, watch.elapsedMicroseconds, prepared);
    });
    final call = Timeline.now - mark;

    // A worker that prepared before, as a long-lived worker would be. It
    // sends its result through a port, which copies it, because only the
    // worker's exit hands a result over without a copy.
    final port = ReceivePort();
    await Isolate.spawn((SendPort reply) {
      Hyphenator.forLanguage(language)?.breaks('representation');
      prepareSections([source()], settings);
      final watch = Stopwatch()..start();
      final prepared = prepareSections([source()], settings).single;
      reply.send((watch.elapsedMicroseconds, Timeline.now, prepared));
    }, port.sendPort);
    final (reused, sent, _) = await port.first as (int, int, PreparedSection);
    final copy = Timeline.now - sent;

    // The book's faces, registered under a new name.
    mark = Timeline.now;
    await BookFonts.load(
      prepared.fonts,
      (font) => publication.resources[font],
      'bookfin-probe-${Timeline.now}',
    );
    final fonts = Timeline.now - mark;

    // The page source's own prepare, layout and picture of the section's
    // middle page.
    final pages = PageSource(publication)..settings = settings;
    mark = Timeline.now;
    final dom = (await pages.section(section)).dom;
    final ready = Timeline.now - mark;
    mark = Timeline.now;
    final page = await pages.pageAt(
      placeAt(dom, section, 0.5),
      anchored: true,
      urgent: true,
    );
    final layout = Timeline.now - mark;
    pages.show(page);
    mark = Timeline.now;
    pages.draft(page);
    final picture = Timeline.now - mark;
    pages.dispose();

    _log({
      'kind': 'parts',
      'book': plan['book'],
      'section': section,
      'characters': prepared.dom.visibleLength,
      'flowItems': prepared.flow.length,
      'faces': prepared.fonts.length,
      'emptyHop': _ms(hop),
      'workerCall': _ms(call),
      'hyphenationLoad': _ms(hyphenation),
      'prepare': _ms(work),
      'prepareReused': _ms(reused),
      'copyBack': _ms(copy),
      'fonts': _ms(fonts),
      'sourcePrepare': _ms(ready),
      'anchoredLayout': _ms(layout),
      'picture': _ms(picture),
    });
  }

  /// Shows [pager] in a viewport, and returns when its first page was
  /// shown and, when [draw], when the frame that drew it finished.
  Future<(int, int)> _showPager(EpubPager pager, {bool draw = true}) async {
    final shown = Completer<int>();
    void listener() {
      if (pager.shown.value != null && !shown.isCompleted) {
        shown.complete(Timeline.now);
      }
    }

    pager.shown.addListener(listener);
    setState(() => _pager = pager);
    final at = await shown.future;
    pager.shown.removeListener(listener);
    _settings = pager.shown.value!.page.settings;
    return (at, draw ? await _drawnAfter(at) : at);
  }

  Future<void> _hide() async {
    setState(() => _pager = null);
    await WidgetsBinding.instance.endOfFrame;
  }

  /// When the raster thread finished the first frame that started to build
  /// after [mark], on the clock of [Timeline.now].
  Future<int> _drawnAfter(int mark) async {
    SchedulerBinding.instance.scheduleFrame();
    for (var wait = 0; wait < 500; wait++) {
      for (final frame in _frames) {
        if (frame.timestampInMicroseconds(ui.FramePhase.buildStart) >= mark) {
          return frame.timestampInMicroseconds(ui.FramePhase.rasterFinish);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('No frame was drawn after the page was shown.');
  }

  static double _ms(int micros) => (micros / 100).round() / 10;

  @override
  Widget build(BuildContext context) {
    final pager = _pager;
    return Scaffold(
      body: SafeArea(
        child: pager == null
            ? Center(child: Text(_status))
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 56),
                child: EpubViewport(
                  key: ObjectKey(pager),
                  pager: pager,
                  fontSize: 20,
                  night: false,
                  onTap: () {},
                  onTurn: (_) {},
                  onLink: (_) {},
                  onCopy: (_) {},
                ),
              ),
      ),
    );
  }
}
