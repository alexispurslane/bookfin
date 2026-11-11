import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/semantics.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('epubbench/probe');

void main() => runApp(const MaterialApp(home: BenchmarkShell()));

class BenchmarkShell extends StatefulWidget {
  const BenchmarkShell({super.key});
  @override
  State<BenchmarkShell> createState() => _BenchmarkShellState();
}

class _BenchmarkShellState extends State<BenchmarkShell> {
  final _pageKey = GlobalKey();
  EpubPager? _pager;
  PageSource? _source;
  EpubDocument? _document;
  late Map<String, dynamic> _configuration;
  late Map<String, dynamic> _specification;
  late List<dynamic> _steps;
  double _textSize = 18;
  String _status = 'Preparing isolated Bookfin shell';
  Completer<void>? _raster;
  int _rasterAfter = 0;
  int _shellReady = 0;
  int _clockOffset = 0;
  int _clockUncertainty = 0;
  int _clockRoundTrip = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_receiveFrames);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _receiveFrames(List<ui.FrameTiming> frames) {
    if (_raster case final pending? when !pending.isCompleted) {
      if (frames.any(
        (frame) =>
            frame.timestampInMicroseconds(ui.FramePhase.buildStart) >=
            _rasterAfter,
      )) {
        pending.complete();
      }
    }
  }

  Future<void> _run() async {
    try {
      _configuration = (await platform.invokeMapMethod<String, dynamic>(
        'configuration',
      ))!;
      _specification =
          jsonDecode(_configuration['specification'] as String)
              as Map<String, dynamic>;
      _steps = jsonDecode(_configuration['workload'] as String) as List;
      await _calibrateClock();
      _shellReady = (await platform.invokeMethod<int>('clock'))!;
      for (final (sequence, raw) in _steps.indexed) {
        final step = raw as Map;
        final operation = step['operation'] as String;
        setState(() => _status = 'Bookfin: $operation');
        final startSource = Timeline.now;
        final start = _androidTime(startSource);
        switch (operation) {
          case 'fresh_open' || 'cached_reopen':
            await _open();
          case 'page_turn' || 'chapter_crossing':
            await _pager!.move(true);
          case 'prepare_crossing':
            await _size(18);
            await _pager!.seek(
              ((_specification['target'] as Map)['index'] as int) + 1,
              0,
            );
            await _pager!.move(false);
            if (_pager!.shown.value!.page.section !=
                (_specification['target'] as Map)['index']) {
              throw StateError('Previous page is not in the selected section');
            }
          case 'prepare_target':
            await _size(18);
            await _pager!.seek(
              (_specification['target'] as Map)['index'] as int,
              0,
            );
          case 'prepare_reopen':
            await _pager!.seek(
              ((_specification['target'] as Map)['index'] as int) + 1,
              0,
            );
          case 'font_change':
            await _size(20);
          case 'paginate':
            await _prepareCache();
          default:
            throw ArgumentError.value(operation);
        }
        if (!mounted) return;
        final page = _pager!.shown.value!.page;
        final operationReturnedSource = Timeline.now;
        final picture = await _source!.picture(
          page,
          scale: View.of(context).devicePixelRatio,
        );
        final preparationSource = Timeline.now;
        if (!identical(_pager!.shown.value!.picture, picture)) {
          await _until(() => identical(_pager!.shown.value!.picture, picture));
        }
        final ready = (await platform.invokeMethod<int>('clock'))!;
        if ((_configuration['run_id'] as String).startsWith('calibration-')) {
          _rasterAfter = Timeline.now;
          _raster = Completer<void>();
          SchedulerBinding.instance.scheduleFrame();
          await _raster!.future.timeout(const Duration(seconds: 10));
        }
        if (!mounted) return;
        final box = _pageKey.currentContext!.findRenderObject()! as RenderBox;
        final origin = box.localToGlobal(Offset.zero);
        final density = View.of(context).devicePixelRatio;
        final blocks = pageBlocks(page);
        final text = [
          for (final block in blocks)
            for (final span in block.spans)
              if (!span.image) span.label,
        ].join(' ');
        final metadata = <String, Object?>{
          'engine': 'bookfin',
          'book': _configuration['book'],
          'run_id': _configuration['run_id'],
          'round': _configuration['round'],
          'id': '${_configuration['run_id']}/$sequence',
          'sequence': sequence,
          'operation': operation,
          'case': step['case'],
          'measured': step['measured'],
          'warmup': (_configuration['run_id'] as String).startsWith(
            'calibration-',
          ),
          'cache': sequence == 0 ? 'fresh_document' : 'warm_document',
          'start_ns': start,
          'start_source_us': startSource,
          'operation_returned_source_us': operationReturnedSource,
          'preparation_source_us': preparationSource,
          'operation_returned_ns': _androidTime(operationReturnedSource),
          'preparation_ns': _androidTime(preparationSource),
          'preparation_event_id': '${_configuration['run_id']}/$sequence',
          'preparation_operation': operation,
          'preparation_scope': 'flutter_picture_and_decoded_page_images',
          'phase_clock': {
            'source': 'dart_timeline_us',
            'offset_ns': _clockOffset,
            'uncertainty_ns': _clockUncertainty,
            'calibration_round_trip_ns': _clockRoundTrip,
          },
          'engine_ready_ns': ready,
          'shell_ready_ns': _shellReady,
          'process_start_ns': _configuration['process_start_ns'],
          'book_sha256': _specification['sha256'],
          'spine_index': page.section,
          'location_format': 'epub_cfi',
          'location': cfiOf(
            _document!.publication.spineSteps[page.section],
            page.dom,
            page.startPlace!,
          ),
          'visible_text': text,
          'visible_images': [
            for (final block in blocks)
              for (final span in block.spans)
                if (span.image) span.label,
          ],
          'page_start': page.start.toString(),
          'section_last_page': page.last,
          'start_visible': page.startVisible,
          'end_visible': page.endVisible,
          'text_size_css_px': _textSize,
          'whole_book_paginated': _pager!.bookPages.value.complete,
          'book_page_count': _pager!.bookPages.value.count,
          'left_px': (origin.dx * density).round(),
          'top_px': (origin.dy * density).round(),
          'width_px': (box.size.width * density).round(),
          'height_px': (box.size.height * density).round(),
        };
        await platform.invokeMethod<String>('capture', jsonEncode(metadata));
      }
      await platform.invokeMethod<void>('done', _configuration['run_id']);
      setState(() => _status = 'Bookfin: complete ${_configuration['run_id']}');
    } catch (error, stack) {
      debugPrint('EPUB_PROBE_ERROR $error\n$stack');
      if (mounted) setState(() => _status = 'Workload failed: $error');
    }
  }

  int _androidTime(int micros) => micros * 1000 + _clockOffset;

  Future<void> _calibrateClock() async {
    var shortest = 1 << 62;
    for (var attempt = 0; attempt < 9; attempt++) {
      final before = Timeline.now * 1000;
      final native = (await platform.invokeMethod<int>('clock'))!;
      final after = Timeline.now * 1000;
      final roundTrip = after - before;
      if (roundTrip < shortest) {
        shortest = roundTrip;
        _clockOffset = native - (before + after) ~/ 2;
        _clockRoundTrip = roundTrip;
        _clockUncertainty = (roundTrip + 1) ~/ 2 + 1000;
      }
    }
  }

  Future<void> _open() async {
    final loaded =
        await loadReadingDocument(
              VerifiedFile(
                Uri.file(_configuration['path'] as String),
                _specification['sha256'] as String,
              ),
              SourceFile(
                itemId: 'benchmark',
                displayName: _specification['title'] as String,
                mediaSourceId: 'benchmark',
                revision: '1',
                container: 'epub',
                durationMs: 0,
                sizeBytes: _specification['actual_bytes'] as int,
              ),
            )
            as EpubDocument;
    final target = (_specification['target'] as Map)['index'] as int;
    final source = PageSource(loaded.publication, pageMaps: loaded.pageMaps);
    final pager = EpubPager(
      loaded,
      source: source,
      initial: EpubAddress(
        ReadingLocation(
          'epubcfi(${loaded.publication.spineSteps[target]}!/4)',
          loaded.publication.spine[target],
          '',
        ),
      ),
      onPlace: (_) {},
      onWarning: (message) => throw StateError(message),
    );
    final old = _pager;
    setState(() {
      _document = loaded;
      _source = source;
      _pager = pager;
      _textSize = 18;
    });
    old?.dispose();
    await _until(() => pager.shown.value != null);
    if (pager.shown.value!.page.section != target) {
      throw StateError('Fresh open missed selected section');
    }
  }

  Future<void> _size(double size) async {
    if (_textSize == size) return;
    setState(() => _textSize = size);
    await _until(() => _pager!.shown.value!.page.settings.fontSize == size);
  }

  Future<void> _until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Engine preparation timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> _prepareCache() async {
    await _until(() => _pager!.bookPages.value.complete);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final kept = await _document!.pageMaps!.read(
        _pager!.shown.value!.page.settings,
      );
      if (kept != null && kept.every((section) => section.complete)) return;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Page map was not persisted');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_receiveFrames);
    _pager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff6efe2),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status),
            SizedBox(
              key: _pageKey,
              width: 360,
              height: 640,
              child: _pager == null
                  ? const SizedBox()
                  : EpubViewport(
                      pager: _pager!,
                      fontSize: _textSize,
                      night: false,
                      onTap: () {},
                      onTurn: (_) {},
                      onLink: (_) {},
                      onCopy: (_) {},
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
