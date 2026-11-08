import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/navigation.dart' show ContentsEntry;

import 'document.dart';
import 'pdf.dart';

/// The pages of an open PDF, as the original page or as reflowed text.
///
/// The viewport draws what its owner gives it and reports what the person
/// chose. It causes no recognition or reflow change itself. The book stays
/// the owner of page text and recognition, and the owner keeps the reflow
/// choice. The viewport keeps only the shown page and its layout.
class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    required this.reflow,
    required this.onReflow,
    required this.onCancelRecognition,
    required this.onRetryRecognition,
    this.initial,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;
  final ValueChanged<PdfAddress> onAddress;

  /// Whether the page shows as reflowed text. The original page shows
  /// while the page has no text that matches the place.
  final bool reflow;

  /// Reports that the person chose Reflow text (true) or Original page
  /// (false).
  final ValueChanged<bool> onReflow;

  /// Reports that the viewport no longer waits for the text of the shown
  /// page: the person chose Cancel recognition, or left the page before its
  /// text arrived.
  final VoidCallback onCancelRecognition;

  /// Reports that the person asked to recognize the source page again. The
  /// viewport then asks the book for the page's text again.
  final ValueChanged<int> onRetryRecognition;
  @override
  State<PdfViewport> createState() => _PdfViewportState();
}

class _PdfViewportState extends State<PdfViewport>
    implements DocumentNavigator {
  final _scroll = ScrollController();
  PdfText? _text;
  ui.Image? _image;
  TextPainter? _layout;
  int _page = 1;
  late PdfAddress _address;
  bool _positionResolved = false;
  int _generation = 0;
  int? _drawingGeneration;
  int _search = 0;
  bool _loading = false;
  String? _failure;
  double? _layoutWidth;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    unawaited(_load(widget.initial ?? PdfAddress(1, 0)));
  }

  @override
  void didUpdateWidget(PdfViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) _layoutWidth = null;
    if (oldWidget.reflow != widget.reflow) {
      // A new layout scrolls to the place, and the original page draws once.
      if (widget.reflow) {
        _layoutWidth = null;
      } else {
        unawaited(_draw(_generation));
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _search++;
    _scroll.dispose();
    _image?.dispose();
    _layout?.dispose();
    super.dispose();
  }

  Future<void> _load(PdfAddress address, {bool lastViewport = false}) async {
    if (!widget.book.accepts(address)) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
    _search++;
    if (_loading) widget.onCancelRecognition();
    final generation = ++_generation;
    setState(() {
      _page = address.sourcePage;
      _address = address;
      _positionResolved = false;
      _loading = true;
      _failure = null;
      _text = null;
      _image?.dispose();
      _image = null;
      _layoutWidth = null;
    });
    try {
      final pendingText = widget.book.text(_page);
      await Future<void>.value();
      if (!mounted || generation != _generation) {
        await pendingText;
        return;
      }
      widget.onReady(this, [
        for (var page = 1; page <= widget.book.pageCount; page++)
          ContentsEntry('Source page $page', 'page:$page'),
      ]);
      unawaited(_draw(generation));
      final text = await pendingText;
      if (!mounted || generation != _generation) return;
      setState(() {
        _text = text;
        final resolved = widget.book.resolveAddress(address, text);
        _positionResolved = resolved != null;
        if (resolved != null) {
          _address = widget.book.addressFor(
            _page,
            text,
            lastViewport ? text.source.length : resolved.character,
          );
        }
        _loading = false;
      });
    } on Exception {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failure = 'Text could not be extracted. The original page is still available.';
      });
    }
    if (!mounted || generation != _generation) return;
    widget.onReady(this, [
      for (var page = 1; page <= widget.book.pageCount; page++)
        ContentsEntry('Source page $page', 'page:$page'),
    ]);
    _publish();
    if (!_usingText) await _draw(generation);
  }

  bool get _usingText => widget.reflow && _positionResolved;

  Future<void> _draw(int generation) async {
    if (_image != null ||
        !mounted ||
        generation != _generation ||
        _drawingGeneration == generation) {
      return;
    }
    _drawingGeneration = generation;
    try {
      final raster = await widget.book.render(
        _page,
        MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context),
      );
      if (!mounted || generation != _generation) return;
      final completed = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        raster.bgra,
        raster.width,
        raster.height,
        ui.PixelFormat.bgra8888,
        completed.complete,
      );
      final image = await completed.future;
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } on Exception {
      if (mounted && generation == _generation) {
        setState(
          () => _failure = 'The original page could not be drawn. Retry this source page or reopen the download.',
        );
      }
    } finally {
      if (_drawingGeneration == generation) _drawingGeneration = null;
    }
  }

  void _publish() {
    widget.onAddress(_address);
  }

  void _scrolled() {
    final layout = _layout;
    final text = _text;
    if (!_usingText || layout == null || text == null || !_scroll.hasClients) {
      return;
    }
    final offset = layout
        .getPositionForOffset(Offset(0, _scroll.offset))
        .offset;
    final character = offset < text.sourceOffsets.length
        ? text.sourceOffsets[offset]
        : text.source.length;
    if (character == _address.character) return;
    _address = widget.book.addressFor(_page, text, character);
    _publish();
  }

  @override
  Future<void> move(bool forward) async {
    if (_usingText && _scroll.hasClients) {
      final target =
          (_scroll.offset +
                  (forward ? 1 : -1) * _scroll.position.viewportDimension * .85)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      if ((target - _scroll.offset).abs() > 1) {
        _scroll.jumpTo(target);
        return;
      }
    }
    final page = _page + (forward ? 1 : -1);
    if (page >= 1 && page <= widget.book.pageCount) {
      await _load(PdfAddress(page, 0), lastViewport: !forward && _usingText);
    }
  }

  @override
  Future<void> display(ReaderAddress address) async {
    if (address is! PdfAddress) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
    await _load(address);
  }

  @override
  Future<void> contents(String href) async {
    if (!href.startsWith('page:')) {
      throw ArgumentError('Choose a PDF source page.');
    }
    await display(PdfAddress(int.parse(href.substring(5)), 0));
  }

  @override
  Future<void> configure({
    required double fontSize,
    required bool night,
  }) async {}

  @override
  Future<void> cancelSearch(int request) async {
    if (_search == request) _search++;
  }

  @override
  Future<ReaderSearchReport> search(String query, int request) async {
    _search = request;
    final hits = <ReaderHit>[];
    var skipped = 0;
    final pattern = RegExp(RegExp.escape(query.trim()), caseSensitive: false);
    if (query.trim().isEmpty) return const ReaderSearchReport([]);
    for (var page = 1; page <= widget.book.pageCount; page++) {
      if (!mounted || _search != request) return const ReaderSearchReport([]);
      try {
        final text = await widget.book.text(page);
        if (!mounted || _search != request) return const ReaderSearchReport([]);
        if (text.status != PdfTextStatus.candidate) {
          skipped++;
          continue;
        }
        for (final match in pattern.allMatches(text.text)) {
          hits.add(
            ReaderHit(
              widget.book.addressFor(
                page,
                text,
                text.sourceOffsets[match.start],
              ),
              'Source page $page: ${text.text.substring(math.max(0, match.start - 40), math.min(text.text.length, match.end + 80))}',
            ),
          );
          if (hits.length == 200) {
            return ReaderSearchReport(
              hits,
              error: 'Search stopped at 200 matches. Use a longer phrase.',
            );
          }
        }
      } on Exception {
        skipped++;
      }
    }
    return ReaderSearchReport(
      hits,
      error: skipped == 0
          ? null
          : 'Search skipped $skipped source pages without reliable text. Those original pages are still available.',
    );
  }

  Widget _reflowText() => LayoutBuilder(
    builder: (context, constraints) {
      final text = _text!;
      final style = TextStyle(
        fontSize: widget.fontSize,
        height: 1.55,
        color: Theme.of(context).colorScheme.onSurface,
      );
      final width = math.max(1.0, constraints.maxWidth - 40);
      if (_layoutWidth != width) {
        _layout?.dispose();
        _layout = TextPainter(
          text: TextSpan(text: text.text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        _layoutWidth = width;
        final index = text.sourceOffsets.indexWhere(
          (offset) => offset >= _address.character,
        );
        final target = _layout!
            .getOffsetForCaret(
              TextPosition(offset: index < 0 ? text.text.length : index),
              Rect.zero,
            )
            .dy;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _usingText && _scroll.hasClients) {
            _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
            // Placement can leave the scroll offset unchanged on a short page.
            _scrolled();
          }
        });
      }
      return SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(text.text, style: style, textScaler: TextScaler.noScaling),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            onPressed: () => widget.onReflow(false),
            child: const Text('Original page'),
          ),
          TextButton(
            onPressed: _loading ? null : () => widget.onReflow(true),
            child: const Text('Reflow text'),
          ),
        ],
      ),
      if (widget.book.textSupply != null)
        ValueListenableBuilder<bool>(
          valueListenable: widget.book.textSupply!.recognizing,
          builder: (context, recognizing, _) => Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                recognizing
                    ? 'Recognizing English text…'
                    : 'English scans only. Other languages are not supported.',
              ),
              if (recognizing)
                TextButton(
                  onPressed: () {
                    widget.onCancelRecognition();
                    _search++;
                    _generation++;
                    setState(() {
                      _loading = false;
                      _failure = 'Recognition canceled. The current page can finish in the background. The original page is available.';
                    });
                    _publish();
                    unawaited(_draw(_generation));
                  },
                  child: const Text('Cancel recognition'),
                ),
              if (!recognizing &&
                  widget.book.textSupply!.canRetry &&
                  !_loading &&
                  _text?.status != PdfTextStatus.candidate)
                TextButton(
                  onPressed: () {
                    widget.onRetryRecognition(_page);
                    unawaited(_load(_address));
                  },
                  child: Text(
                    _text?.status == PdfTextStatus.unreliable
                        ? 'Try English recognition'
                        : 'Retry recognition',
                  ),
                ),
            ],
          ),
        ),
      if (widget.reflow)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            (!_positionResolved && _address.character > 0 && !_loading
                    ? 'The saved text position is not available in this page text. Read the original page, or choose this source page in Contents to start its current text.'
                    : _text?.reason) ??
                (_usingText
                    ? 'Extracted text is not checked against the page. Pictures and page layout stay in the original page.'
                    : _failure ?? 'Checking source-page text.'),
          ),
        ),
      if (!widget.reflow &&
          widget.book.textSupply != null &&
          _text?.reason != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_text!.reason!),
        ),
      if (_failure != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(_failure!)),
      Expanded(
        child: _usingText
            ? _reflowText()
            : _image == null
            ? Center(
                child: _failure == null
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: () => unawaited(_load(_address)),
                        child: const Text('Retry source page'),
                      ),
              )
            : Semantics(
                label: 'Original source page $_page',
                image: true,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: RawImage(image: _image, fit: BoxFit.contain),
                  ),
                ),
              ),
      ),
    ],
  );
}
