import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('epubbench/probe');

void main() {
  runApp(const MaterialApp(home: ProbeShell()));
}

class ProbeShell extends StatefulWidget {
  const ProbeShell({super.key});

  @override
  State<ProbeShell> createState() => _ProbeShellState();
}

class _ProbeShellState extends State<ProbeShell> {
  final _pageKey = GlobalKey();
  final _frames = <ui.FrameTiming>[];
  EpubPager? _pager;
  EpubAddress? _address;
  Map<String, dynamic>? _configuration;
  double _textSize = 18;
  bool _busy = true;
  String _status = 'Bookfin production EPUB engine. Unverified probe.';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_receiveFrames);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_initialize()),
    );
  }

  void _receiveFrames(List<ui.FrameTiming> frames) {
    _frames.addAll(frames);
  }

  Future<void> _initialize() async {
    try {
      _configuration = (await platform.invokeMapMethod<String, dynamic>(
        'configuration',
      ))!;
      await _perform('open');
    } catch (error, stack) {
      _failed(error, stack);
    }
  }

  Future<void> _open() async {
    final configuration = _configuration!;
    final specification =
        jsonDecode(configuration['specification'] as String) as Map;
    final loaded =
        await loadReadingDocument(
              VerifiedFile(
                Uri.file(configuration['path'] as String),
                specification['sha256'] as String,
              ),
              SourceFile(
                itemId: 'benchmark',
                displayName: specification['title'] as String,
                mediaSourceId: 'benchmark',
                revision: '1',
                container: 'epub',
                durationMs: 0,
                sizeBytes: specification['actual_bytes'] as int,
              ),
            )
            as EpubDocument;
    final firstPage = Completer<void>();
    final pager = EpubPager(
      loaded,
      onPlace: (address) => _address = address,
      onWarning: (message) => debugPrint('EPUB_PROBE_WARNING $message'),
    );
    void shown() {
      if (pager.shown.value != null && !firstPage.isCompleted) {
        firstPage.complete();
      }
    }

    pager.shown.addListener(shown);
    final old = _pager;
    setState(() => _pager = pager);
    old?.dispose();
    await firstPage.future.timeout(const Duration(seconds: 90));
    pager.shown.removeListener(shown);
    await pager.seek((specification['target'] as Map)['index'] as int, 0);
  }

  Future<void> _perform(String operation) async {
    setState(() {
      _busy = true;
      _status = 'Bookfin: $operation (unverified probe)';
    });
    try {
      final requested = await platform.invokeMethod<int>('clock');
      switch (operation) {
        case 'open' || 'reopen':
          await _open();
        case 'page_turn':
          await _pager!.move(true);
        case 'section_jump':
          await _pager!.seek(_pager!.shown.value!.page.section + 1, 0);
        case 'font_change':
          final pager = _pager!;
          final changed = Completer<void>();
          final nextSize = _textSize == 18 ? 20.0 : 18.0;
          void shown() {
            if (pager.shown.value?.page.settings.fontSize == nextSize &&
                !changed.isCompleted) {
              changed.complete();
            }
          }
          pager.shown.addListener(shown);
          setState(() => _textSize = nextSize);
          try {
            await changed.future.timeout(const Duration(seconds: 90));
          } finally {
            pager.shown.removeListener(shown);
          }
        default:
          throw ArgumentError.value(operation, 'operation');
      }
      final ready = await platform.invokeMethod<int>('clock');
      final shownAt = Timeline.now;
      SchedulerBinding.instance.scheduleFrame();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!_frames.any(
        (frame) =>
            frame.timestampInMicroseconds(ui.FramePhase.buildStart) >= shownAt,
      )) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('No rasterized frame after the requested page');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (!mounted) return;
      final box = _pageKey.currentContext!.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(Offset.zero);
      final density = View.of(context).devicePixelRatio;
      final page = _pager!.shown.value!.page;
      final anchor = page.startPlace;
      final paragraph = anchor == null ? null : page.dom.textAt(anchor)?.text;
      final metadata = <String, Object?>{
        'engine': 'bookfin',
        'book': _configuration!['book'],
        'operation': operation,
        'request_ns': requested,
        'engine_ready_ns': ready,
        'spine_index': page.section,
        'anchor_paragraph': paragraph,
        'address': _address?.toJson(),
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
      if (mounted) {
        setState(() {
          _busy = false;
          _status =
              'Captured probe. Destination and pixels still need validation.';
        });
      }
    } catch (error, stack) {
      _failed(error, stack);
    }
  }

  void _failed(Object error, StackTrace stack) {
    debugPrint('EPUB_PROBE_ERROR $error\n$stack');
    if (mounted) {
      setState(() {
        _busy = false;
        _status = 'Probe failed: $error';
      });
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
            Wrap(
              children: [
                for (final operation in [
                  'page_turn',
                  'section_jump',
                  'font_change',
                  'reopen',
                ])
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_perform(operation)),
                    child: Text(operation.replaceAll('_', ' ')),
                  ),
              ],
            ),
            SizedBox(
              key: _pageKey,
              width: 360,
              height: 640,
              child: _pager == null
                  ? const Center(child: Text('Loading public EPUB fixture'))
                  : EpubViewport(
                      pager: _pager!,
                      fontSize: _textSize,
                      night: false,
                      onTap: () {},
                      onTurn: (forward) {},
                      onLink: (link) {},
                      onCopy: (text) {},
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
