import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'book_crop.dart';
import 'book_survey.dart';
import 'document.dart';
import 'page_swipes.dart';
import 'pdf.dart';

/// The pages of an open PDF, as the original page or as reflowed text.
///
/// The original view asks the book only for the page's text layer, so it
/// never starts recognition. The reflow view asks the book for the page's
/// text for reading, which recognizes a page without a usable text layer.
/// While that runs, the original page shows under a thin progress line.
/// When reflow cannot work on the shown page, the original page shows under
/// one quiet line that says why. Nothing covers the page.
///
/// The book owns page text and recognition. The owner keeps the reflow
/// choice and offers its control. The viewport keeps only the shown page
/// and its layout.
///
/// The original page shows its crop (see [BookSurvey]), so its text keeps
/// one size and place from page to page. A page never changes its crop
/// while it shows: a crop that becomes known later applies from the next
/// page shown. A page that a turn shows takes the crop known at once. A
/// page that a jump, a scrub or the opening of the book shows waits up to
/// 300 ms for its crop. A page without a crop shows whole.
///
/// Like every reader view, it reports a tap on the page through [onTap]
/// and a swipe across it through [onTurn]. A swipe on a zoomed original
/// page moves the page instead.
class PdfViewport extends StatefulWidget {
  const PdfViewport({
    super.key,
    required this.book,
    required this.fontSize,
    required this.onReady,
    required this.onAddress,
    required this.reflow,
    required this.onCancelRecognition,
    required this.onTap,
    required this.onTurn,
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

  /// Reports that the viewport no longer waits for the text of the shown
  /// page: the person left the page, or chose the original page, before
  /// its text arrived.
  final VoidCallback onCancelRecognition;

  /// A tap on the page that hit no control on it.
  final VoidCallback onTap;

  /// A swipe, or a screen reader's scroll action, that asks for the next
  /// page (true) or the previous one.
  final ValueChanged<bool> onTurn;
  @override
  State<PdfViewport> createState() => _PdfViewportState();
}

class _PdfViewportState extends State<PdfViewport>
    implements DocumentNavigator {
  final _scroll = ScrollController();

  /// The zoom and pan of the original page.
  final _zoom = TransformationController();
  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;
  PdfText? _text;
  ui.Image? _image;
  TextPainter? _layout;
  int _page = 1;

  /// Whether a turn showed the page, so that it takes only a crop known at
  /// once.
  bool _turned = false;
  late PdfAddress _address;
  bool _positionResolved = false;
  int _generation = 0;
  int? _drawingGeneration;
  int _search = 0;

  /// Counts the requests for the shown page's text, so that an answer to an
  /// older request is dropped.
  int _textRequest = 0;

  /// Whether the shown page waits for its text.
  bool _loading = false;

  /// Whether the last request for the shown page's text failed.
  bool _textFailed = false;

  /// Why the original page could not be drawn, or null.
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
      // The owner hears of the change after this build, because its
      // reports change what the owner shows.
      final generation = _generation;
      void after(VoidCallback report) =>
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == _generation) report();
          });
      if (widget.reflow) {
        _layoutWidth = null;
        // A page without a usable text layer needs its text for reading.
        // It waits from this frame on, so no false reason shows.
        if (_text?.status != PdfTextStatus.candidate || _textFailed) {
          _loading = true;
          after(() => unawaited(_requestText(generation, _address)));
        }
      } else {
        if (_loading) after(_stopWaiting);
        unawaited(_draw(_generation));
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _search++;
    _scroll.dispose();
    _zoom.dispose();
    _image?.dispose();
    _layout?.dispose();
    super.dispose();
  }

  Future<void> _load(
    PdfAddress address, {
    bool lastViewport = false,
    bool turned = false,
  }) async {
    if (!widget.book.accepts(address)) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
    _search++;
    if (_loading) widget.onCancelRecognition();
    final generation = ++_generation;
    _zoom.value = Matrix4.identity();
    setState(() {
      _page = address.sourcePage;
      _turned = turned;
      _address = address;
      _positionResolved = false;
      _failure = null;
      _text = null;
      _image?.dispose();
      _image = null;
      _layoutWidth = null;
    });
    await _requestText(generation, address, lastViewport: lastViewport);
    if (!mounted || generation != _generation) return;
    if (!_usingText) await _draw(generation);
  }

  /// Asks the book for the text of the shown page, whose place is
  /// [address]: the text for reading in reflow, and only the text layer on
  /// the original page. Then it resolves the place in that text and
  /// publishes it. With [lastViewport], the place is the end of the page.
  Future<void> _requestText(
    int generation,
    PdfAddress address, {
    bool lastViewport = false,
  }) async {
    final request = ++_textRequest;
    bool current() =>
        mounted && generation == _generation && request == _textRequest;
    setState(() {
      _loading = true;
      _textFailed = false;
    });
    try {
      final pendingText = widget.reflow
          ? widget.book.text(_page)
          : widget.book.textLayer(_page);
      await Future<void>.value();
      if (!current()) {
        await pendingText;
        return;
      }
      widget.onReady(this, _contents());
      unawaited(_draw(generation));
      final text = await pendingText;
      if (!current()) return;
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
      if (!current()) return;
      setState(() {
        _loading = false;
        _textFailed = true;
      });
    }
    if (!current()) return;
    widget.onReady(this, _contents());
    _publish();
  }

  List<ContentsEntry> _contents() => [
    for (var page = 1; page <= widget.book.pageCount; page++)
      ContentsEntry('Source page $page', 'page:$page'),
  ];

  bool get _usingText => widget.reflow && _positionResolved;

  Future<void> _draw(int generation) async {
    if (_image != null ||
        !mounted ||
        generation != _generation ||
        _drawingGeneration == generation) {
      return;
    }
    _drawingGeneration = generation;
    final width =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    try {
      final crop = _turned
          ? _crops?.cropOf(_page)
          : await _crops?.cropWithin(_page, _cropWait);
      if (!mounted || generation != _generation) return;
      final image = await _drawPage(widget.book, _page, width, crop);
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

  /// The longest time that a page shown by a jump waits for its crop.
  static const _cropWait = Duration(milliseconds: 300);

  /// The survey whose crops the original pages and the deck cards show, or
  /// null to show whole pages.
  // NOTE: Every page and deck card takes its crop from this survey, so the
  // Trim margins switch of tb-nkz5 turns crops off here.
  BookSurvey? get _crops => widget.book.survey;

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
      await _load(
        PdfAddress(page, 0),
        lastViewport: !forward && _usingText,
        turned: true,
      );
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
  Future<void> seek(int part, double progress) =>
      display(PdfAddress(part + 1, 0));

  /// A PDF page is a whole part of the book, so its neighbors are the source
  /// pages before and after it. A page draws in well under a tenth of a
  /// second, so it does not stop when abandoned. It shows the page's crop
  /// when it is known, and never waits for one.
  @override
  Future<PagePreview> preview(
    BookPlace place,
    double width,
    Future<void> abandon,
  ) async {
    final part = place.part;
    final crop = _crops?.cropOf(part + 1);
    return PagePreview(
      part: part,
      start: 0,
      end: 1,
      image: await _drawPage(widget.book, part + 1, width, crop),
      previous: part > 0 ? (part: part - 1, progress: 0) : null,
      next: part + 1 < widget.book.pageCount
          ? (part: part + 1, progress: 0)
          : null,
    );
  }

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
        // Only a page that Bookfin failed to read may hide matches. A page
        // without text, or whose text cannot be put in order, is quiet.
        if (text.status != PdfTextStatus.candidate) {
          if (text.status == PdfTextStatus.failed) skipped++;
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
          : skipped == 1
          ? 'Search could not read 1 source page. Its original page is still available.'
          : 'Search could not read $skipped source pages. Their original pages are still available.',
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

  /// Stops waiting for the shown page's text. Recognition can still finish
  /// in the background, and its text is then cached.
  void _stopWaiting() {
    widget.onCancelRecognition();
    _search++;
    _textRequest++;
    setState(() => _loading = false);
    _publish();
  }

  /// Why reflow cannot show the shown page, in one quiet line, when the
  /// person can act on it. It is null while the page reflows, while its
  /// text is still on its way, and when the page's own content does not
  /// reflow, because the original page is then the page to read.
  String? get _reflowProblem {
    if (_loading) return null;
    if (_textFailed) return 'The text of this page could not be read.';
    final text = _text;
    if (text == null) return null;
    return switch (text.status) {
      PdfTextStatus.failed => text.reason,
      PdfTextStatus.absent || PdfTextStatus.unreliable => null,
      PdfTextStatus.candidate =>
        _positionResolved
            ? null
            : 'The saved place does not match the text of this page.',
    };
  }

  /// The original page, the reflowed text, or what stands in their place.
  Widget _shownPage() => _usingText
      ? _reflowText()
      : _image == null
      ? Center(
          child: switch (_failure) {
            null => const CircularProgressIndicator(),
            final failure => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(failure, textAlign: TextAlign.center),
                ),
                TextButton(
                  onPressed: () => unawaited(_load(_address)),
                  child: const Text('Retry source page'),
                ),
              ],
            ),
          },
        )
      : Semantics(
          label: 'Original source page $_page',
          image: true,
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: RawImage(image: _image, fit: BoxFit.contain),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    // The page, its quiet line and its text keep their own nodes.
    explicitChildNodes: true,
    onScrollLeft: () => widget.onTurn(true),
    onScrollRight: () => widget.onTurn(false),
    child: PageSwipes(
      onTurn: widget.onTurn,
      swipes: () => !_zoomed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The page's own semantics turn pages. The screen offers the
        // controls to a screen reader.
        excludeFromSemantics: true,
        onTap: widget.onTap,
        child: _view(),
      ),
    ),
  );

  /// The shown page in the chosen view.
  Widget _view() {
    if (!widget.reflow || _usingText) return _shownPage();
    // The reflow view shows the original page while the text is on its way,
    // when the page's own content does not reflow, and when reflow failed
    // on the page. Only a failure puts a quiet line above it.
    final problem = _reflowProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              problem,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else if (widget.book.textSupply case final supply?)
          ValueListenableBuilder<bool>(
            valueListenable: supply.recognizing,
            builder: (_, recognizing, _) => recognizing && _loading
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    semanticsLabel: 'Recognizing the text of this page',
                  )
                : const SizedBox.shrink(),
          ),
        Expanded(child: _shownPage()),
      ],
    );
  }
}

/// Source page [page] of [book], drawn [width] pixels wide: the whole page,
/// or only its [crop]. A crop draws from the page drawn wider by the
/// inverse of the crop's share of the page width, within the book's render
/// limits, so the crop gets the [width] pixels.
Future<ui.Image> _drawPage(
  PdfBook book,
  int page,
  double width,
  PageBox? crop,
) async {
  final raster = await book.render(
    page,
    crop == null ? width : width / (crop.right - crop.left),
  );
  final columns = raster.width, rows = raster.height;
  // Page units are fractions of the page width.
  var left = 0, top = 0, right = columns, bottom = rows;
  if (crop != null) {
    left = (crop.left * columns).floor().clamp(0, columns - 1);
    top = (crop.top * columns).floor().clamp(0, rows - 1);
    right = (crop.right * columns).ceil().clamp(left + 1, columns);
    bottom = (crop.bottom * columns).ceil().clamp(top + 1, rows);
  }
  final drawn = Completer<ui.Image>();
  // The image reads the crop's rows in place from the page's pixels, so
  // cropping runs no pixel loop on this isolate.
  ui.decodeImageFromPixels(
    Uint8List.sublistView(raster.bgra, (top * columns + left) * 4),
    right - left,
    bottom - top,
    ui.PixelFormat.bgra8888,
    drawn.complete,
    rowBytes: columns * 4,
  );
  return drawn.future;
}
