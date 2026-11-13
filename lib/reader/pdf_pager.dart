import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'book_crop.dart';
import 'book_survey.dart';
import 'document.dart';
import 'pdf.dart';
import 'pdf_text_view.dart';
import 'pdf_word_view.dart';
import 'word_pages.dart';

class _TextScreen {
  _TextScreen(this.page, this.text, this.layout, this.index);

  final int page;
  final PdfText text;
  final PdfTextScreens layout;
  int index;
}

/// Navigation and prepared page content for one open PDF.
///
/// ReaderSession creates this owner once at book open and disposes it before
/// the book. Views can come and go without cancelling its navigation or text.
/// PdfBook still owns document text, recognition and page data. This pager
/// owns requests, search, layouts, rasters and the place eligible for saving.
///
/// Invariants:
/// - A request's address belongs to its requested source page.
/// - Only a completed content frame makes that request eligible for publication.
/// - Pending reports and appearance waits belong to the current request.
/// - Report suppression compares both address and screen: incomplete word
///   addresses can be equal on distinct screens.
/// - Disposal invalidates requests and releases timers, waits and images.
/// Check these on demand with [checkInvariants]; public navigation guards
/// remain active in release builds.
class PdfPager extends ChangeNotifier implements DocumentNavigator {
  /// Opens [initial], or source page 1, and requests its text. Raster work
  /// starts after [layout] provides the view's measurements.
  /// `onAddress` reports a changed place after content appears; late text
  /// gets 50 ms before a page-level report. `onRefinedAddress` names that
  /// same place when text arrives, without creating another reading move.
  /// `onCancelRecognition` tells the owner to stop recognition when the
  /// requested page or chosen view no longer needs it.
  PdfPager(
    this._book, {
    PdfAddress? initial,
    this._view = PdfPageView.original,
    this._trimMargins = true,
    required this._onAddress,
    required this._onRefinedAddress,
    required this._onCancelRecognition,
  }) {
    _words = PdfWordScreens(
      _book,
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
    unawaited(_load(initial ?? PdfAddress(1, 0)));
  }

  final PdfBook _book;
  final ValueChanged<PdfAddress> _onAddress;
  final ValueChanged<PdfAddress> _onRefinedAddress;
  final VoidCallback _onCancelRecognition;
  PdfPageView _view;
  bool _trimMargins;

  /// Notifications concern only page content, never document attachment or
  /// contents entries. The viewport subscribes here; the session's saved
  /// place and book map have their own signals.
  Listenable get pageChanges => this;

  /// The requested page's view, source-page number and request identity.
  /// A request identity is valid only for this pager's lifetime.
  PdfPageView get view => _view;
  int get page => _page;
  int get generation => _generation;
  bool get trimMargins => _trimMargins;

  /// Content ready for drawing. Readiness alone is not proof of appearance.
  ui.Image? get image => _image;
  bool get usingWords => _usingWords;
  bool get usingText => _usingText;
  bool get loading => _loading;
  String? get failure => _failure;
  String? get reflowProblem => _reflowProblem;
  PdfWordScreens get words => _words;
  ValueListenable<bool>? get recognizing => _book.textSupply?.recognizing;
  ({PdfTextScreens layout, int index})? get textScreen => switch (_textScreen) {
    final shown? => (layout: shown.layout, index: shown.index),
    null => null,
  };

  /// Accepts measured raster width (device pixels), text area (logical
  /// pixels), and style from the view. Layout is synchronous so the caller
  /// can draw it in this frame; document work runs asynchronously.
  void layout(double rasterWidth, Size textSize, TextStyle style) {
    if (_disposed) return;
    if (!rasterWidth.isFinite ||
        rasterWidth <= 0 ||
        !textSize.width.isFinite ||
        !textSize.height.isFinite ||
        textSize.width <= 0 ||
        textSize.height <= 0) {
      throw ArgumentError('Choose a positive finite PDF viewport size.');
    }
    _rasterWidth = rasterWidth;
    _textSize = textSize;
    _textStyle = style;
    if (_usingText) _layText(textSize);
    if (_image == null && _failure == null) unawaited(_draw(_generation));
  }

  /// Retries drawing this source page without changing its reading place.
  void retryPage() {
    if (_disposed) return;
    _failure = null;
    unawaited(_draw(_generation, replace: true));
    notifyListeners();
  }

  void _change(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  late final PdfWordScreens _words;
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
  /// request is abandoned or both its raster and usable text are unavailable.
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

  bool _disposed = false;
  double? _rasterWidth;
  TextStyle? _textStyle;

  /// Applies the session's choices. It does not store preferences itself.
  /// A margin change redraws the original page and affects later previews.
  /// Otherwise a shown page keeps its crop until the next navigation:
  /// turns use a known crop at once; opening and jumps wait up to 300 ms.
  void configure({required PdfPageView view, required bool trimMargins}) {
    if (_disposed) return;
    if (_trimMargins != trimMargins) {
      _trimMargins = trimMargins;
      _drawRevision++;
      _failure = null;
      unawaited(_draw(_generation, replace: true));
    }
    if (_view != view) {
      _view = view;
      final generation = _generation;
      _textRequest++;
      if (view != PdfPageView.original) {
        _loading = true;
        _clearTextScreen();
        _words.leave();
        unawaited(
          view == PdfPageView.pageWords
              ? _startWords(generation, _address)
              : _requestText(generation, _address),
        );
      } else {
        final wasLoading = _loading;
        _words.leave();
        if (wasLoading) _onCancelRecognition();
        _textRequest++;
        _change(() => _loading = false);
        _publish();
        unawaited(_draw(generation));
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (!_appearance.isCompleted) _appearance.complete();
    _search++;
    _latePlace?.cancel();
    _words.showing.removeListener(_wordStateChanged);
    _words.waitingForText.removeListener(_wordStateChanged);
    _words.dispose();
    _image?.dispose();
    _clearTextScreen();
    super.dispose();
  }

  Future<void> _load(
    PdfAddress address, {
    bool lastViewport = false,
    bool turned = false,
  }) async {
    if (_disposed) return;
    if (!_book.accepts(address)) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
    _search++;
    if (_loading) _onCancelRecognition();
    final generation = ++_generation;
    if (!_appearance.isCompleted) _appearance.complete();
    final appearance = _appearance = Completer<void>();
    _latePlace?.cancel();
    _change(() {
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
    if (_view == PdfPageView.pageWords) {
      await _startWords(generation, address, lastViewport: lastViewport);
    } else {
      _words.leave();
      await _requestText(generation, address, lastViewport: lastViewport);
    }
    if (_disposed || generation != _generation) return;
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
        !_disposed &&
        generation == _generation &&
        request == _textRequest &&
        _view == PdfPageView.pageWords;
    _words.open(address, last: lastViewport);
    await Future<void>.value();
    if (!current()) return;
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
        !_disposed && generation == _generation && request == _textRequest;
    _change(() {
      _loading = true;
      _textFailed = false;
    });
    try {
      final pendingText = _view != PdfPageView.original
          ? _book.text(_page)
          : _book.textLayer(_page);
      await Future<void>.value();
      if (!current()) {
        await pendingText;
        return;
      }
      unawaited(_draw(generation));
      final text = await pendingText;
      if (!current()) return;
      _change(() {
        _text = text;
        _clearTextScreen();
        final resolved = _book.resolveAddress(address, text);
        _positionResolved = resolved != null;
        if (resolved != null) {
          _address = _book.addressFor(
            _page,
            text,
            lastViewport ? text.source.length : resolved.character,
          );
        }
        _loading = false;
      });
    } on Exception {
      if (!current()) return;
      _change(() {
        _loading = false;
        _textFailed = true;
      });
    }
    if (!current()) return;
    if (_placeReported) {
      // Only this page's own request reaches here ([current]), so the
      // refinement never names a page other than the reported one.
      _refine();
    } else {
      _publish();
    }
    _finishUnavailablePage();
  }

  /// Ends a failed request only when neither its image nor its text can
  /// appear. A raster failure cannot end a jump whose text is still on
  /// its way: that text must get its frame and History report first.
  void _finishUnavailablePage() {
    if (_failure != null &&
        !_loading &&
        !_usingText &&
        !_usingWords &&
        !_appearance.isCompleted) {
      _appearance.complete();
    }
  }

  /// Accepts a completed content frame for [generation]. The viewport must
  /// report only content it actually drew, never a completed raster or a
  /// loading indicator. [words] identifies the exact prepared word screen
  /// drawn in that frame. An old view's queued report cannot advance a new page.
  void appeared(int generation, {WordScreen? words}) {
    if (_disposed || generation != _generation) return;
    if (words != null) {
      if (_usingWords) _words.appeared(words);
      return;
    }
    if (_pageShown) return;
    if (_usingWords && _words.screen.value != null) return;
    _pageShown = true;
    if (_loading) {
      _reportWhenLate(generation);
    } else {
      _publish();
    }
    if (!_appearance.isCompleted) _appearance.complete();
  }

  /// Reports the place of the shown page, the page of [generation], once
  /// [_placeWait] passed, unless the page reports its place before then.
  /// The place is then the page as it is known without its text or words.
  void _reportWhenLate(int generation) {
    if (_placeReported || (_latePlace?.isActive ?? false)) return;
    _latePlace = Timer(_placeWait, () {
      if (!_disposed && generation == _generation) _publish();
    });
  }

  bool get _usingWords => _view == PdfPageView.pageWords && _words.covers;

  bool get _usingText =>
      _view != PdfPageView.original && !_usingWords && _positionResolved;

  void _wordStateChanged() {
    if (_disposed) return;
    _change(() {
      _loading =
          _usingWords && (!_words.showing.value || _words.waitingForText.value);
    });
  }

  Future<void> _draw(int generation, {bool replace = false}) async {
    final request = (generation, _drawRevision);
    bool current() => !_disposed && request == (_generation, _drawRevision);
    if ((_image != null && !replace) ||
        !current() ||
        _drawingRequest == request) {
      return;
    }
    _drawingRequest = request;
    final width = _rasterWidth;
    if (width == null) {
      _drawingRequest = null;
      return;
    }
    try {
      final crop = _turned
          ? _crops?.cropOf(_page)
          : await _crops?.cropWithin(_page, _cropWait);
      if (!current()) return;
      final image = await _drawPage(_book, _page, width, crop);
      if (!current()) {
        image.dispose();
        return;
      }
      _change(() {
        _image?.dispose();
        _image = image;
        _failure = null;
      });
    } on Exception {
      if (current()) {
        _change(
          () => _failure = 'The original page could not be drawn. Retry this source page or reopen the download.',
        );
        _finishUnavailablePage();
      }
    } finally {
      if (_drawingRequest == request) _drawingRequest = null;
    }
  }

  /// The longest time that a page shown by a jump waits for its crop.
  static const _cropWait = Duration(milliseconds: 300);

  /// The survey whose crops the original pages and the deck cards show, or
  /// null to show whole pages.
  BookSurvey? get _crops => _trimMargins ? _book.survey : null;

  @override
  void reportPendingPlace() {
    // Only this request's completed content frame sets _pageShown. Prepared
    // words cannot hide an original page's pending report or advance it.
    if (!_pageShown || _placeReported) return;
    _publish();
  }

  /// The layout and screen index that show, or null for an original page.
  Object? get _shownScreen {
    final words = _words.appearedScreen;
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
    _onAddress(_address);
  }

  void _refine() {
    _reported = (address: _address, screen: _shownScreen);
    _onRefinedAddress(_address);
  }

  void _textPlace() {
    final shown = _textScreen!;
    final text = shown.text;
    final offset = shown.layout.firstCharacter(shown.index);
    final character = offset < text.sourceOffsets.length
        ? text.sourceOffsets[offset]
        : text.source.length;
    _address = _book.addressFor(shown.page, text, character);
  }

  void _clearTextScreen() {
    _textScreen?.layout.dispose();
    _textScreen = null;
  }

  _TextScreen _layText(Size size) {
    final text = _text!;
    final style = _textStyle!;
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
      if (!_disposed &&
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
    if (_disposed) return;
    if (_usingWords && _words.turn(forward)) return;
    if (_usingText) {
      var size = _textSize;
      if (size == null) {
        final generation = _generation;
        await WidgetsBinding.instance.endOfFrame;
        if (_disposed || generation != _generation || !_usingText) return;
        size = _textSize;
      }
      if (size == null) return;
      final shown = _layText(size);
      final screen = shown.index + (forward ? 1 : -1);
      if (screen >= 0 && screen < shown.layout.count) {
        _change(() {
          shown.index = screen;
          _textPlace();
        });
        _publish();
        return;
      }
    }
    final page = _page + (forward ? 1 : -1);
    if (page >= 1 && page <= _book.pageCount) {
      await _load(
        PdfAddress(page, 0),
        lastViewport: !forward && _view != PdfPageView.original,
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
      image: await _drawPage(_book, part + 1, width, crop),
      previous: part > 0 ? (part: part - 1, progress: 0) : null,
      next: part + 1 < _book.pageCount ? (part: part + 1, progress: 0) : null,
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
    for (var page = 1; page <= _book.pageCount; page++) {
      if (_disposed || _search != request) return const ReaderSearchReport([]);
      try {
        final text = await _book.text(page);
        if (_disposed || _search != request) {
          return const ReaderSearchReport([]);
        }
        // Only a page that Bookfin failed to read may hide matches. A page
        // without text, or whose text cannot be put in order, is quiet.
        if (text.status != PdfTextStatus.candidate) {
          if (text.status == PdfTextStatus.failed) skipped++;
          continue;
        }
        for (final match in pattern.allMatches(text.text)) {
          hits.add(
            ReaderHit(
              _book.addressFor(page, text, text.sourceOffsets[match.start]),
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

  /// Checks related navigation state in every build, only when requested.
  void checkInvariants() {
    if (!_book.accepts(_address) ||
        _address.sourcePage != _page ||
        (_placeReported && !_pageShown) ||
        ((_latePlace?.isActive ?? false) && (!_pageShown || _placeReported)) ||
        (_disposed &&
            (!_appearance.isCompleted || (_latePlace?.isActive ?? false)))) {
      throw StateError('PDF pager navigation state is inconsistent.');
    }
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
