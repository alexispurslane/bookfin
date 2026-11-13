import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_crop.dart';
import 'book_survey.dart';
import 'document.dart';
import 'page_swipes.dart';
import 'pdf.dart';
import 'pdf_text_view.dart';
import 'pdf_word_view.dart';
import 'selection.dart';
import 'word_selection.dart';

/// The pages of an open PDF, as originals, page words or reading text.
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
/// one size and place from page to page. Except when [trimMargins] changes,
/// a page keeps its crop while it shows: a crop that becomes known later
/// applies from the next page shown. A page that a turn shows takes the
/// crop known at once. A page that a jump, a scrub or the opening of the book shows waits up to
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
    required this.onRefinedAddress,
    required this.view,
    required this.onCancelRecognition,
    required this.onTap,
    required this.onTurn,
    this.initial,
    this.trimMargins = true,
  });
  final PdfBook book;
  final double fontSize;
  final PdfAddress? initial;
  final void Function(DocumentNavigator, List<ContentsEntry>) onReady;

  /// Reports a changed page, screen or address. An unchanged place gives
  /// no repeat report. A page whose text or words arrive
  /// promptly reports once, with the place as they name it. A page that
  /// still waits for them 50 ms after it began to show reports the page
  /// itself then, so the owner can save the page while a scanned page is
  /// recognized.
  final ValueChanged<PdfAddress> onAddress;

  /// Reports the place of the last [onAddress] report again, on the same
  /// page and the same screen of it, as the text of the page names it once
  /// that text arrives. The text of a page that no longer shows reports
  /// nothing.
  final ValueChanged<PdfAddress> onRefinedAddress;

  /// The session's chosen PDF view. The original page shows while the
  /// chosen view waits for words or text that match the place.
  final PdfPageView view;

  /// Whether original pages and deck cards show their known content crop.
  /// A change redraws the shown original page, without changing its place
  /// or the reflowed content. Crops that arrive later still wait for a turn.
  final bool trimMargins;

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

class _TextScreen {
  _TextScreen(this.page, this.text, this.layout, this.index);

  final int page;
  final PdfText text;
  final PdfTextScreens layout;
  int index;
}

class _PdfViewportState extends State<PdfViewport>
    implements DocumentNavigator {
  final _wordSelection = GlobalKey();
  final _selectionArea = GlobalKey<SelectionAreaState>();
  bool _selectedAtDown = false;
  WordSelection? get _selection =>
      (_wordSelection.currentContext?.findRenderObject()
              as RenderWordSelectable?)
          ?.selection;

  void _copy() {
    if (_selection?.text case final text?) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
  }

  void _tap() {
    if (_selectedAtDown) {
      _selectionArea.currentState?.selectableRegion.clearSelection();
    } else {
      widget.onTap();
    }
  }

  /// The zoom and pan of the original page.
  final _zoom = TransformationController();
  late final PdfWordScreens _words;
  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;
  PdfText? _text;
  ui.Image? _image;
  _TextScreen? _textScreen;
  int _page = 1;

  /// Whether a turn showed the page, so that it takes only a crop known at
  /// once.
  bool _turned = false;
  late PdfAddress _address;
  bool _positionResolved = false;
  int _generation = 0;
  int _drawRevision = 0;
  (int, int)? _drawingRequest;
  int _search = 0;

  /// Counts the requests for the shown page's text, so that an answer to an
  /// older request is dropped.
  int _textRequest = 0;

  /// Whether the shown page waits for its text.
  bool _loading = false;

  /// Whether the last request for the shown page's text failed.
  bool _textFailed = false;

  /// Whether content from the requested page has appeared in a frame.
  /// Loading indicators and a retained word screen from an earlier page
  /// cannot make the requested address eligible for persistence.
  bool _pageShown = false;

  /// Finishes navigation after its first content frame, or when that
  /// request is abandoned or its original page cannot be drawn.
  Completer<void> _appearance = Completer<void>();

  /// Whether the shown page reported its place since it loaded.
  bool _placeReported = false;

  /// The last reported address and screen. The screen distinguishes turns
  /// within a page whose text still names every screen as character zero.
  ({PdfAddress address, Object? screen})? _reported;

  /// Reports the page-level place of the shown page when its text or its
  /// words are late (see [_reportWhenLate]), or null.
  Timer? _latePlace;

  /// The longest time that a page shows without a report of its place.
  ///
  /// The text layer of a page answers in a few milliseconds, also when the
  /// text outline holds PDFium for one slice of about 8 ms. Such a page
  /// reports once, with its full place: a page-level report before it would
  /// double the saves and the synced records of every page turn (boo-s11s).
  /// Recognition takes seconds. 50 ms is several times the first and far
  /// below the second, and it leaves the save half of the 100 ms after
  /// which a stopped app must not lose the page.
  static const _placeWait = Duration(milliseconds: 50);

  /// Why the original page could not be drawn, or null.
  String? _failure;

  /// The last measured text area, in logical pixels. A turn can lay out a
  /// newly loaded page at this size before the next frame measures it again.
  Size? _textSize;

  @override
  void initState() {
    super.initState();
    _words = PdfWordScreens(
      widget.book,
      onPlace: (place) {
        _pageShown = true;
        _address = place;
        _publish();
        if (!_appearance.isCompleted) _appearance.complete();
      },
      onRefinedPlace: (place) {
        _address = place;
        _refine();
      },
      onGiveUp: () => unawaited(_requestText(_generation, _address)),
    );
    _words.showing.addListener(_wordStateChanged);
    _words.waitingForText.addListener(_wordStateChanged);
    unawaited(_load(widget.initial ?? PdfAddress(1, 0)));
  }

  @override
  void didUpdateWidget(PdfViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trimMargins != widget.trimMargins) {
      _drawRevision++;
      _failure = null;
      _zoom.value = Matrix4.identity();
      unawaited(_draw(_generation, replace: true));
    }
    if (oldWidget.view != widget.view) {
      // A new layout shows the place, and the original page draws once.
      // The owner hears of the change after this build, because its
      // reports change what the owner shows.
      final generation = _generation;
      final view = widget.view;
      _textRequest++;
      void after(VoidCallback report) =>
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == _generation && view == widget.view) {
              report();
            }
          });
      if (view != PdfPageView.original) {
        _loading = true;
        _clearTextScreen();
        after(() {
          _words.leave();
          unawaited(
            view == PdfPageView.pageWords
                ? _startWords(generation, _address)
                : _requestText(generation, _address),
          );
        });
      } else {
        final wasLoading = _loading;
        after(() {
          _words.leave();
          if (wasLoading) widget.onCancelRecognition();
          _textRequest++;
          setState(() => _loading = false);
          _publish();
          unawaited(_draw(generation));
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    if (!_appearance.isCompleted) _appearance.complete();
    _search++;
    _latePlace?.cancel();
    _words.showing.removeListener(_wordStateChanged);
    _words.waitingForText.removeListener(_wordStateChanged);
    _words.dispose();
    _zoom.dispose();
    _image?.dispose();
    _clearTextScreen();
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
    if (!_appearance.isCompleted) _appearance.complete();
    final appearance = _appearance = Completer<void>();
    _latePlace?.cancel();
    _zoom.value = Matrix4.identity();
    setState(() {
      _page = address.sourcePage;
      _turned = turned;
      _address = address;
      _placeReported = false;
      _pageShown = false;
      _positionResolved = false;
      _failure = null;
      _text = null;
      _image?.dispose();
      _image = null;
      _clearTextScreen();
    });
    if (widget.view == PdfPageView.pageWords) {
      await _startWords(generation, address, lastViewport: lastViewport);
    } else {
      _words.leave();
      await _requestText(generation, address, lastViewport: lastViewport);
    }
    if (!mounted || generation != _generation) return;
    if (!_usingText) await _draw(generation);
    await appearance.future;
  }

  /// Opens the shown page, whose place is [address], in the word view, and
  /// falls back to its text when it has no words to show.
  ///
  /// While an earlier word screen stays on the display, the place does not
  /// advance: the first word screen of the page reports it. With no word
  /// screen to keep, the original page shows while the words are on their
  /// way, so words that are late let the page report its place first
  /// ([_reportWhenLate]).
  Future<void> _startWords(
    int generation,
    PdfAddress address, {
    bool lastViewport = false,
  }) async {
    final request = ++_textRequest;
    bool current() =>
        mounted &&
        generation == _generation &&
        request == _textRequest &&
        widget.view == PdfPageView.pageWords;
    _words.open(address, last: lastViewport);
    await Future<void>.value();
    if (!current()) return;
    widget.onReady(this, _contents());
    unawaited(_draw(generation));
    if (await _words.shows(address.sourcePage)) return;
    if (!current()) return;
    await _requestText(generation, address, lastViewport: lastViewport);
  }

  /// Asks the book for the text of the shown page, whose place is
  /// [address]: the text for reading in reflow, and only the text layer on
  /// the original page. Then it resolves the place in the text and reports
  /// it. With [lastViewport], that place is the end of the page.
  ///
  /// The page shows while its text is on its way, and recognition takes
  /// seconds. So a text that is late lets the page report its place first,
  /// as it is known without the text ([_reportWhenLate], engine rule 3).
  /// The place in the text is then a refinement of the reported place.
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
      final pendingText = widget.view != PdfPageView.original
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
        _clearTextScreen();
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
    if (_placeReported) {
      // Only this page's own request reaches here ([current]), so the
      // refinement never names a page other than the reported one.
      _refine();
    } else {
      _publish();
    }
  }

  /// Called only while building page content that will enter this frame,
  /// never while constructing the word view's unused waiting widget.
  /// The first completed frame starts the allowance for late text.
  void _pageInFrame() {
    if (_pageShown) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _pageShown) return;
      if (_usingWords && _words.screen.value != null) return;
      _pageShown = true;
      if (_loading) {
        _reportWhenLate(generation);
      } else {
        _publish();
      }
      if (!_appearance.isCompleted) _appearance.complete();
    });
  }

  /// Reports the place of the shown page, the page of [generation], once
  /// [_placeWait] passed, unless the page reports its place before then.
  /// The place is then the page as it is known without its text or words.
  void _reportWhenLate(int generation) {
    if (_placeReported || (_latePlace?.isActive ?? false)) return;
    _latePlace = Timer(_placeWait, () {
      if (mounted && generation == _generation) _publish();
    });
  }

  List<ContentsEntry> _contents() => [
    for (var page = 1; page <= widget.book.pageCount; page++)
      ContentsEntry('Source page $page', 'page:$page'),
  ];

  bool get _usingWords => widget.view == PdfPageView.pageWords && _words.covers;

  bool get _usingText =>
      widget.view != PdfPageView.original && !_usingWords && _positionResolved;

  void _wordStateChanged() {
    if (!mounted) return;
    setState(() {
      _loading =
          _usingWords && (!_words.showing.value || _words.waitingForText.value);
    });
  }

  Future<void> _draw(int generation, {bool replace = false}) async {
    final request = (generation, _drawRevision);
    bool current() => mounted && request == (_generation, _drawRevision);
    if ((_image != null && !replace) ||
        !current() ||
        _drawingRequest == request) {
      return;
    }
    _drawingRequest = request;
    final width =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    try {
      final crop = _turned
          ? _crops?.cropOf(_page)
          : await _crops?.cropWithin(_page, _cropWait);
      if (!current()) return;
      final image = await _drawPage(widget.book, _page, width, crop);
      if (!current()) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _failure = null;
      });
    } on Exception {
      if (current()) {
        setState(
          () => _failure = 'The original page could not be drawn. Retry this source page or reopen the download.',
        );
        if (!_appearance.isCompleted) _appearance.complete();
      }
    } finally {
      if (_drawingRequest == request) _drawingRequest = null;
    }
  }

  /// The longest time that a page shown by a jump waits for its crop.
  static const _cropWait = Duration(milliseconds: 300);

  /// The survey whose crops the original pages and the deck cards show, or
  /// null to show whole pages.
  BookSurvey? get _crops => widget.trimMargins ? widget.book.survey : null;

  @override
  void reportPendingPlace() {
    // A retained word screen is still the place on screen while the
    // requested page waits for its words.
    if (!_pageShown ||
        _placeReported ||
        (widget.view == PdfPageView.pageWords &&
            !_words.showing.value &&
            _words.screen.value != null)) {
      return;
    }
    _publish();
  }

  /// The layout and screen index that show, or null for an original page.
  Object? get _shownScreen {
    final words = _words.screen.value;
    if (_usingWords && words != null) {
      return (words.column.column, words.screen);
    }
    final text = _textScreen;
    if (_usingText && text != null) return (text.layout, text.index);
    return null;
  }

  void _publish() {
    if (!_pageShown) return;
    _latePlace?.cancel();
    _placeReported = true;
    final previous = _reported, screen = _shownScreen;
    if (previous != null &&
        previous.screen == screen &&
        mapEquals(previous.address.toJson(), _address.toJson())) {
      return;
    }
    _reported = (address: _address, screen: screen);
    widget.onAddress(_address);
  }

  void _refine() {
    _reported = (address: _address, screen: _shownScreen);
    widget.onRefinedAddress(_address);
  }

  void _textPlace() {
    final shown = _textScreen!;
    final text = shown.text;
    final offset = shown.layout.firstCharacter(shown.index);
    final character = offset < text.sourceOffsets.length
        ? text.sourceOffsets[offset]
        : text.source.length;
    _address = widget.book.addressFor(shown.page, text, character);
  }

  void _clearTextScreen() {
    _textScreen?.layout.dispose();
    _textScreen = null;
  }

  _TextScreen _layText(Size size) {
    final text = _text!;
    final style = TextStyle(
      fontFamily: 'Source Serif 4',
      fontFamilyFallback: const ['Noto Serif'],
      fontSize: widget.fontSize,
      height: 1.55,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final shown = _textScreen;
    if (shown != null &&
        shown.page == _page &&
        identical(shown.text, text) &&
        shown.layout.size == size &&
        shown.layout.style == style) {
      return shown;
    }
    _clearTextScreen();
    final layout = PdfTextScreens(text: text.text, style: style, size: size);
    final index = text.sourceOffsets.indexWhere(
      (offset) => offset >= _address.character,
    );
    final screen = _TextScreen(
      _page,
      text,
      layout,
      layout.screenAt(index < 0 ? text.text.length : index),
    );
    _textScreen = screen;
    final placed = _address.toJson();
    _textPlace();
    // A layout whose shown screen begins at the place as it is already
    // named, such as the first screen of a page after a turn, has nothing
    // new to report.
    if (mapEquals(placed, _address.toJson())) return screen;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          identical(_textScreen, screen) &&
          _usingText) {
        _publish();
      }
    });
    return screen;
  }

  @override
  Future<void> move(bool forward) async {
    if (_usingWords && _words.turn(forward)) return;
    if (_usingText) {
      var size = _textSize;
      if (size == null) {
        final generation = _generation;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || generation != _generation || !_usingText) return;
        size = _textSize;
      }
      if (size == null) return;
      final shown = _layText(size);
      final screen = shown.index + (forward ? 1 : -1);
      if (screen >= 0 && screen < shown.layout.count) {
        setState(() {
          shown.index = screen;
          _textPlace();
        });
        _publish();
        return;
      }
    }
    final page = _page + (forward ? 1 : -1);
    if (page >= 1 && page <= widget.book.pageCount) {
      await _load(
        PdfAddress(page, 0),
        lastViewport: !forward && widget.view != PdfPageView.original,
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
      final size = Size(
        math.max(1.0, constraints.maxWidth - 40),
        math.max(1.0, constraints.maxHeight - 24),
      );
      _textSize = size;
      final shown = _layText(size);
      _pageInFrame();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: PdfTextView(screens: shown.layout, screen: shown.index),
      );
    },
  );

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
  Widget _shownPage() {
    if (_usingText) return _reflowText();
    final failure = switch (_failure) {
      null => null,
      final message => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          TextButton(
            onPressed: () {
              setState(() => _failure = null);
              unawaited(_draw(_generation, replace: true));
            },
            child: const Text('Retry source page'),
          ),
        ],
      ),
    };
    if (_image == null) {
      return Center(child: failure ?? const CircularProgressIndicator());
    }
    final page = Builder(
      builder: (_) {
        _pageInFrame();
        return Semantics(
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
      },
    );
    return failure == null
        ? page
        : Column(
            children: [
              failure,
              Expanded(child: page),
            ],
          );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    // The page, its quiet line and its text keep their own nodes.
    explicitChildNodes: true,
    onScrollLeft: () => widget.onTurn(true),
    onScrollRight: () => widget.onTurn(false),
    child: PageSwipes(
      onTurn: widget.onTurn,
      swipes: () => !_zoomed && !(_selection?.selecting ?? false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The page's own semantics turn pages. The screen offers the
        // controls to a screen reader.
        excludeFromSemantics: true,
        onTap: _usingWords ? null : _tap,
        child: Listener(
          onPointerDown: (_) {
            _selectedAtDown = _selection?.selecting ?? false;
            if (_usingWords) _words.touch();
          },
          child: _view(),
        ),
      ),
    ),
  );

  /// The shown page in the chosen view.
  Widget _view() {
    if (_usingWords) {
      return ReaderCopyArea(
        area: _selectionArea,
        onCopy: _copy,
        child: ReaderTapArea(
          onTap: (_) => _tap(),
          child: PdfWordView(
            screens: _words,
            selectionKey: _wordSelection,
            fontSize: widget.fontSize,
            waiting: _wordWaiting(),
            onLayout: _words.lay,
          ),
        ),
      );
    }
    if (widget.view == PdfPageView.original || _usingText) return _shownPage();
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

  Widget _wordWaiting() => Stack(
    children: [
      Positioned.fill(child: _shownPage()),
      const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: LinearProgressIndicator(minHeight: 2),
      ),
    ],
  );
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
