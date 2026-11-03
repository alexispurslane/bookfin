import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/navigation.dart' show ContentsEntry;

import 'document.dart';
import 'pdf.dart';

class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    this.initial,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;
  final ValueChanged<PdfAddress> onAddress;
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
  int _character = 0;
  int _generation = 0;
  int? _drawingGeneration;
  int _search = 0;
  bool _reflow = false;
  bool _loading = true;
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
  }

  @override
  void dispose() {
    widget.book.textSupply?.cancel();
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
    widget.book.textSupply?.cancel();
    final generation = ++_generation;
    setState(() {
      _page = address.sourcePage;
      _character = address.character;
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
        _character = lastViewport
            ? text.source.length
            : _character.clamp(0, text.source.length);
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

  bool get _usingText => _reflow && _text?.status == PdfTextStatus.candidate;

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
    final source = _text?.source ?? '';
    final character = _character.clamp(0, source.length);
    widget.onAddress(
      PdfAddress(
        _page,
        character,
        pageCount: widget.book.pageCount,
        quote: source.substring(
          character,
          math.min(source.length, character + 160),
        ),
      ),
    );
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
    if (character == _character) return;
    _character = character;
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
              PdfAddress(
                page,
                text.sourceOffsets[match.start],
                pageCount: widget.book.pageCount,
                quote: text.text.substring(
                  match.start,
                  math.min(text.text.length, match.start + 160),
                ),
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
          (offset) => offset >= _character,
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
            onPressed: () {
              setState(() => _reflow = false);
              unawaited(_draw(_generation));
            },
            child: const Text('Original page'),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                    _reflow = true;
                    _layoutWidth = null;
                  }),
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
                    widget.book.textSupply!.cancel();
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
                  !_loading &&
                  _text?.status != PdfTextStatus.candidate)
                TextButton(
                  onPressed: () {
                    widget.book.textSupply!.retry(_page);
                    unawaited(_load(PdfAddress(_page, _character)));
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
      if (_reflow)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _text?.reason ??
                (_usingText
                    ? 'Extracted text is not checked against the page. Pictures and page layout stay in the original page.'
                    : _failure ?? 'Checking source-page text.'),
          ),
        ),
      if (!_reflow && widget.book.textSupply != null && _text?.reason != null)
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
                        onPressed: () =>
                            unawaited(_load(PdfAddress(_page, _character))),
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
