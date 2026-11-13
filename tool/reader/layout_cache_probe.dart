// An on-demand probe of a disk cache of page starts on a device (boo-ystu,
// docs/research/epub-layout-cache.md). It prints each result with the tag
// LAYOUT_CACHE_PROBE, as one JSON object per line.
//
// The host serves the books and a plan, plan.json, from one directory on
// port 8781, for example:
//
//   python3 -m http.server 8781 --bind 127.0.0.1 --directory <directory>
//   adb -s <device> reverse tcp:8781 tcp:8781
//
// The plan names the EPUB files and the page settings:
//
//   {"books": ["pg-84-frankenstein.epub"], "width": 412, "height": 671,
//    "fontSize": 20}
//
// For each book, one launch prepares every section in a worker, as the page
// source does, and lays out each section's main run on the UI isolate. It
// prints the time of each, the number of pages, and the SHA-256 of the page
// starts in the survey's JSON form (test/research/epub_layout_cache_test.dart),
// so that the host can compare them with its own. It writes the starts in
// the survey's binary form to a file (a temporary file, then a rename) and
// reads them back, and prints both times. When a file from an earlier launch
// exists, it first compares the starts of that file with the fresh ones:
// the check of determinism across launches on the device. Then it lays out
// one page from each tenth true page start and prints the median time.
// When the plan has "dump": true, it also prints each section's starts.
//
// Build and run it as a profile build on a device that no one else uses:
//
//   flutter build apk --profile -t tool/reader/layout_cache_probe.dart
//   adb -s <device> install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s <device> logcat -d | grep LAYOUT_CACHE_PROBE
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// The host's server of the plan and the books, through `adb reverse`.
const _inbox = 'http://127.0.0.1:8781';

Future<Uint8List> _fetch(String name) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse('$_inbox/$name')))
        .close();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} for $name');
    }
    final bytes = BytesBuilder(copy: false);
    await response.forEach(bytes.add);
    return bytes.takeBytes();
  } finally {
    client.close();
  }
}

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String _status = 'Measuring';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_main()));
  }

  void _log(Map<String, Object?> result) =>
      debugPrint('LAYOUT_CACHE_PROBE ${jsonEncode(result)}');

  Future<void> _main() async {
    try {
      await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
      await Future<void>.delayed(const Duration(seconds: 3));
      final plan = jsonDecode(utf8.decode(await _fetch('plan.json'))) as Map;
      final settings = PageSettings(
        width: (plan['width'] as num).toDouble(),
        height: (plan['height'] as num).toDouble(),
        fontSize: (plan['fontSize'] as num).toDouble(),
        night: false,
      );
      for (final book in (plan['books'] as List).cast<String>()) {
        await _book(book, settings, dump: plan['dump'] == true);
      }
      _log({'done': true});
      if (mounted) setState(() => _status = 'Done');
    } catch (error, stack) {
      _log({'error': '$error', 'stack': '$stack'});
    }
  }

  Future<void> _book(
    String book,
    PageSettings settings, {
    required bool dump,
  }) async {
    final directory = Directory('${Directory.systemTemp.path}/ystu');
    await directory.create(recursive: true);
    final local = File('${directory.path}/$book');
    if (!await local.exists()) {
      await local.writeAsBytes(await _fetch(book), flush: true);
    }
    final publication = Publication.admit(await local.readAsBytes());
    final spine = publication.spine;
    var prepareMs = 0.0;
    var layoutMs = 0.0;
    var slowestSectionMs = 0.0;
    final starts = <List<PageStart>>[];
    final samples = <double>[];
    for (var index = 0; index < spine.length; index++) {
      final path = spine[index];
      final xhtml = publication.textFiles[path]!;
      final styles = publication.bookStyles;
      final sizes = publication.imageSizes;
      final language = publication.language;
      var watch = Stopwatch()..start();
      final prepared = await Isolate.run(
        () => prepareSections([
          SectionSource(
            index: index,
            path: path,
            xhtml: utf8.decode(xhtml),
            styleSheets: styles,
            imageSizes: sizes,
            language: language,
          ),
        ], settings).single,
      );
      prepareMs += _ms(watch);
      watch = Stopwatch()..start();
      final run = LayoutRun(prepared);
      while (!run.done) {
        run.step(const Duration(milliseconds: 8));
      }
      final took = _ms(watch);
      layoutMs += took;
      if (took > slowestSectionMs) slowestSectionMs = took;
      final section = [for (final page in run.pages) page.start];
      starts.add(section);
      if (dump) {
        _log({
          'dump': book,
          'section': index,
          'starts': [
            for (final start in section) ...[
              start.item,
              start.line,
              start.part,
            ],
          ],
        });
      }
      for (final page in run.pages) {
        page.dispose();
      }
      run.dispose();
      for (var at = 0; at < section.length; at += 10) {
        watch = Stopwatch()..start();
        final one = LayoutRun(
          prepared,
          from: section[at],
          measurements: run.measurements,
        )..step(const Duration(days: 1), want: 1);
        samples.add(_ms(watch));
        for (final page in one.pages) {
          page.dispose();
        }
        one.dispose();
      }
      // Frames go on between sections.
      await Future<void>.delayed(Duration.zero);
    }
    final json = jsonEncode([
      for (final section in starts)
        [
          for (final start in section) ...[start.item, start.line, start.part],
        ],
    ]);
    final file = File('${local.path}.starts');
    final launchSame = await file.exists()
        ? _same(_decodeStarts(await file.readAsBytes()), starts)
        : null;
    var watch = Stopwatch()..start();
    final binary = _encodeStarts(starts);
    final temporary = File('${file.path}.new');
    await temporary.writeAsBytes(binary, flush: true);
    await temporary.rename(file.path);
    final writeMs = _ms(watch);
    watch = Stopwatch()..start();
    final read = _decodeStarts(await file.readAsBytes());
    final readMs = _ms(watch);
    samples.sort();
    _log({
      'book': book,
      'sections': spine.length,
      'pages': starts.fold<int>(0, (total, each) => total + each.length),
      'prepareMs': prepareMs,
      'layoutMs': layoutMs,
      'slowestSectionLayoutMs': slowestSectionMs,
      'pageFromStartMedianMs': samples.isEmpty
          ? null
          : samples[samples.length ~/ 2],
      'pageFromStartMaxMs': samples.lastOrNull,
      'startsSha256': sha256.convert(utf8.encode(json)).toString(),
      'binaryBytes': binary.length,
      'writeMs': writeMs,
      'readAndDecodeMs': readMs,
      'readBack': _same(read, starts),
      'sameAsLastLaunch': launchSame,
    });
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(_status)));
}

double _ms(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

bool _same(List<List<PageStart>> a, List<List<PageStart>> b) =>
    jsonEncode([
      for (final section in a) ['$section'],
    ]) ==
    jsonEncode([
      for (final section in b) ['$section'],
    ]);

/// The survey's binary form: each section's count, then each start's item
/// step from the previous start, its line (a step from the previous line in
/// the same item), and its part, as unsigned variable-length integers.
Uint8List _encodeStarts(List<List<PageStart>> sections) {
  final out = BytesBuilder();
  void put(int value) {
    while (value >= 0x80) {
      out.addByte((value & 0x7f) | 0x80);
      value >>= 7;
    }
    out.addByte(value);
  }

  put(sections.length);
  for (final starts in sections) {
    put(starts.length);
    var item = 0;
    var line = 0;
    for (final start in starts) {
      put(start.item - item);
      put(start.item == item ? start.line - line : start.line);
      put(start.part);
      item = start.item;
      line = start.line;
    }
  }
  return out.takeBytes();
}

List<List<PageStart>> _decodeStarts(Uint8List bytes) {
  var at = 0;
  int take() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  final count = take();
  return [
    for (var section = 0; section < count; section++)
      () {
        final length = take();
        var item = 0;
        var line = 0;
        return [
          for (var index = 0; index < length; index++)
            () {
              final itemStep = take();
              final lineValue = take();
              final part = take();
              line = itemStep == 0 ? line + lineValue : lineValue;
              item += itemStep;
              return PageStart(item, line, part);
            }(),
        ];
      }(),
  ];
}
