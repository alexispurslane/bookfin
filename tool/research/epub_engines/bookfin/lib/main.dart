import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/kept_page.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart' show PageSettings;
import 'package:bookfin/reader/epub/semantics.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/kept_pages.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/sync/device.dart';
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

  /// The frames since the current request: when each one had painted and
  /// composited, in Timeline microseconds, the page picture it painted, and
  /// the kept page's picture when it painted that instead.
  final _painted = <({int us, ui.Picture? picture, ui.Picture? kept})>[];

  /// Whether this process's book was prepared at download, as the app
  /// prepares each download when it completes (boo-sy2d).
  String _variant = 'standard';

  /// The background preparation at download, in Timeline microseconds.
  ({int start, int end})? _downloadPreparation;

  /// The kept pages, as the app keeps them (boo-sy2d).
  final _keptPages = KeptPages(engine: textEngineFingerprint);

  /// The kept page that the viewport draws until the pager shows a page, as
  /// the reading session hands it over, or null.
  KeptPage? _kept;

  /// The kept page that the current request read, and when it was handed
  /// to the viewport, in Timeline microseconds, or why it was not.
  KeptPage? _keptRead;
  int? _keptReadySource;
  String? _keptStatus;

  /// Whether the last write kept the target page.
  bool? _keptWritten;

  /// The engine's timings of frames since the current request.
  final _timings = <ui.FrameTiming>[];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_receiveFrames);
    // Registered after the renderer's own callback, so it runs once the
    // frame's layer tree went to the engine. The page's render object paints
    // the pager's shown picture during that frame's paint.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (mounted) {
        final shown = _pager?.shown.value;
        // The viewport paints the kept page only before the pager shows a
        // page, and only when it was laid out for the viewport's settings.
        final kept = shown == null && _kept?.settings == _viewportSettings
            ? _kept?.picture
            : null;
        _painted.add((us: Timeline.now, picture: shown?.picture, kept: kept));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _receiveFrames(List<ui.FrameTiming> frames) {
    _timings.addAll(frames);
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
      _variant = _configuration['variant'] as String? ?? 'standard';
      if (_variant == 'prepared_at_download') _steps = _steps.sublist(0, 1);
      await _calibrateClock();
      _shellReady = (await platform.invokeMethod<int>('clock'))!;
      if (_variant == 'prepared_at_download') {
        // What Downloads runs in the background when the download completes.
        final start = Timeline.now;
        await prepareDownloadedBook(_original, _sourceFile);
        _downloadPreparation = (start: start, end: Timeline.now);
        // The open comes later in the app. A short rest lets the
        // preparation's worker and its file write settle first.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      for (final (sequence, raw) in _steps.indexed) {
        final step = raw as Map;
        final operation = step['operation'] as String;
        setState(() => _status = 'Bookfin: $operation');
        final before = _pager?.shown.value?.picture;
        _painted.clear();
        _timings.clear();
        final startSource = Timeline.now;
        final start = _androidTime(startSource);
        switch (operation) {
          case 'fresh_open' || 'cached_reopen':
            await _open(reopen: operation == 'cached_reopen');
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
            await _keepShown();
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
        // The frames that painted since the request ran inside preparation.
        final framesInPreparation = _painted.length;
        if (!identical(_pager!.shown.value!.picture, picture)) {
          await _until(() => identical(_pager!.shown.value!.picture, picture));
        }
        final ready = (await platform.invokeMethod<int>('clock'))!;
        // Only a step that shows another page has a frame that draws it.
        // Every measured step shows another page.
        final changed = !identical(before, picture);
        if (!changed && step['measured'] == true) {
          throw StateError('The requested page was shown before the request');
        }
        final frame = changed
            ? await _firstFrameWith(
                (frame) => identical(frame.picture, picture),
                startSource,
              )
            : null;
        final kept = _keptRead;
        final keptReady = _keptReadySource;
        final keptFrame =
            operation == 'cached_reopen' &&
                kept != null &&
                keptReady != null &&
                _painted.any((frame) => identical(frame.kept, _keptPicture))
            ? await _firstFrameWith(
                (frame) => identical(frame.kept, _keptPicture),
                startSource,
              )
            : null;
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
          'variant': _variant,
          'cache': sequence != 0
              ? 'warm_document'
              : _variant == 'prepared_at_download'
              ? 'prepared_at_download'
              : 'fresh_document',
          if (_downloadPreparation case final prepared? when sequence == 0) ...{
            'download_preparation_start_source_us': prepared.start,
            'download_preparation_end_source_us': prepared.end,
            'download_preparation_start_ns': _androidTime(prepared.start),
            'download_preparation_end_ns': _androidTime(prepared.end),
          },
          // The pager of an open began with these settings before the
          // viewport presented any; its head start counts only if they match.
          if (operation == 'fresh_open' || operation == 'cached_reopen')
            'expected_settings_equal_shown': page.settings == _pageSettings(18),
          if (operation == 'paginate') 'kept_written': _keptWritten,
          if (operation == 'cached_reopen') ...{
            'kept_status': _keptStatus,
            if (kept != null) 'kept_depicts_page': kept.depicts(page),
            if (keptReady != null) ...{
              'kept_ready_source_us': keptReady,
              'kept_ready_ns': _androidTime(keptReady),
            },
            if (keptFrame != null) ...{
              'kept_drawn_source_us': keptFrame.timing.timestampInMicroseconds(
                ui.FramePhase.rasterFinish,
              ),
              'kept_drawn_ns': _androidTime(
                keptFrame.timing.timestampInMicroseconds(
                  ui.FramePhase.rasterFinish,
                ),
              ),
              'kept_drawn_scope':
                  'flutter_raster_finish_of_first_frame_with_kept_page',
              'kept_drawn_frame': {
                'number': keptFrame.timing.frameNumber,
                'painted_us': keptFrame.painted,
                for (final phase in ui.FramePhase.values)
                  '${phase.name}_us': keptFrame.timing.timestampInMicroseconds(
                    phase,
                  ),
              },
            },
          },
          'start_ns': start,
          'start_source_us': startSource,
          'engine_start_source_us': startSource,
          'engine_start_ns': start,
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
          'frames_in_preparation': framesInPreparation,
          if (frame != null) ...{
            'drawn_source_us': frame.timing.timestampInMicroseconds(
              ui.FramePhase.rasterFinish,
            ),
            'drawn_ns': _androidTime(
              frame.timing.timestampInMicroseconds(ui.FramePhase.rasterFinish),
            ),
            'drawn_scope': 'flutter_raster_finish_of_first_frame_with_page',
            'drawn_frame': {
              'number': frame.timing.frameNumber,
              'painted_us': frame.painted,
              for (final phase in ui.FramePhase.values)
                '${phase.name}_us': frame.timing.timestampInMicroseconds(phase),
            },
          },
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

  /// The first frame since [startSource] that [painted] the page, and the
  /// engine's timing of it: the one frame that began building after the
  /// frame before it had painted, and finished building before it painted.
  Future<({int painted, ui.FrameTiming timing})> _firstFrameWith(
    bool Function(({int us, ui.Picture? picture, ui.Picture? kept}) frame)
    painted,
    int startSource,
  ) async {
    await _until(() => _painted.any(painted));
    final index = _painted.indexWhere(painted);
    final paintedUs = _painted[index].us;
    final after = index == 0 ? startSource : _painted[index - 1].us;
    List<ui.FrameTiming> matching() => [
      for (final timing in _timings)
        if (timing.timestampInMicroseconds(ui.FramePhase.buildStart) > after &&
            timing.timestampInMicroseconds(ui.FramePhase.buildStart) <=
                paintedUs &&
            timing.timestampInMicroseconds(ui.FramePhase.buildFinish) <=
                paintedUs)
          timing,
    ];
    await _until(() => matching().isNotEmpty);
    final found = matching();
    if (found.length != 1) {
      throw StateError('${found.length} frame timings match the painted frame');
    }
    return (painted: paintedUs, timing: found.single);
  }

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

  /// The downloaded book of this process.
  VerifiedFile get _original => VerifiedFile(
    Uri.file(_configuration['path'] as String),
    _specification['sha256'] as String,
  );

  SourceFile get _sourceFile => SourceFile(
    itemId: 'benchmark',
    displayName: _specification['title'] as String,
    mediaSourceId: 'benchmark',
    revision: '1',
    container: 'epub',
    durationMs: 0,
    sizeBytes: _specification['actual_bytes'] as int,
  );

  /// The saved place of the book: the start of the target section, where
  /// every open opens. A kept page is kept for it.
  TextPosition get _place => TextPosition(
    editionId: 'benchmark',
    sourceKey: 'benchmark',
    revision: '1',
    anchor: 'section ${(_specification['target'] as Map)['index']}',
  );

  /// The settings that the viewport presents at [fontSize].
  PageSettings _pageSettings(double fontSize) =>
      PageSettings(width: 360, height: 640, fontSize: fontSize, night: false);

  PageSettings get _viewportSettings => _pageSettings(_textSize);

  ui.Picture? get _keptPicture => _keptRead?.picture;

  /// Opens the book at the target section, as the reading session does. A
  /// reopen first closes the open book, so the viewport shows the paper,
  /// and reads the page kept at the saved place beside the load. The
  /// viewport draws the kept page until the pager shows its first page.
  /// The pager starts its work with this phone's last page settings, as the
  /// app's pager does once one page was shown on the phone.
  Future<void> _open({required bool reopen}) async {
    final original = _original;
    _keptRead?.dispose();
    _keptRead = null;
    _keptReadySource = null;
    _keptStatus = null;
    if (reopen) {
      final old = _pager;
      setState(() => _pager = null);
      old?.dispose();
      _keptStatus = 'reading';
      unawaited(
        _keptPages.read(original, _place).then((kept) {
          if (!mounted || _pager?.shown.value != null) {
            kept?.dispose();
            _keptStatus = kept == null
                ? 'no kept page'
                : 'read after the true page showed';
            return;
          }
          if (kept == null) {
            _keptStatus = 'no kept page';
            return;
          }
          _keptStatus = 'shown';
          _keptRead = kept;
          _keptReadySource = Timeline.now;
          setState(() => _kept = kept);
        }, onError: (Object error) => _keptStatus = 'read failed: $error'),
      );
    }
    final loaded =
        await loadReadingDocument(original, _sourceFile) as EpubDocument;
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
      expected: _pageSettings(18),
      onPlace: (_) {},
      onWarning: (message) => throw StateError(message),
      // The session lets go of the kept page when the first page shows.
      onShow: (_) {
        if (_kept != null && mounted) setState(() => _kept = null);
      },
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

  /// Keeps the shown page for the saved place, as the session does when the
  /// reader closes, when an open at the place shows that page.
  Future<void> _keepShown() async {
    if (!_pager!.opensAtShown) {
      throw StateError('An open at the saved place does not show this page');
    }
    final body = KeptPage.encode(_pager!.shown.value!.page);
    _keptWritten = body != null;
    if (body != null) await _keptPages.write(_original, _place, body);
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
              child: _pager == null && _kept == null && _document == null
                  ? const SizedBox()
                  : EpubViewport(
                      pager: _pager,
                      kept: _kept,
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
