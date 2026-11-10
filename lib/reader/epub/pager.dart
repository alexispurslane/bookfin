// The pager of one open EPUB or MOBI book: the owner of the shown place and
// the shown page.
//
// The reader session asks it to move, as it asks any DocumentNavigator. The
// pager asks the page source for the page, shows it, and then reports the
// page's saved address through onPlace. The viewport draws the shown page
// and presents the page settings. The pager adds little logic of its own:
// the page source lays out pages, and places.dart converts places.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../foundation/hop.dart';
import '../book_pages.dart';
import '../document.dart';
import 'dom.dart';
import 'layout.dart';
import 'page_source.dart';
import 'paint.dart';
import 'places.dart';
import 'prepare.dart';
import 'publication.dart';
import 'search.dart';

/// The page on screen and its recorded picture.
class ShownPage {
  const ShownPage(this.page, this.picture);
  final LaidPage page;

  /// The page's picture. The page source owns it, and it stays usable while
  /// the page is shown.
  final ui.Picture picture;
}

/// A link on the shown page: its destination, relative to the package
/// document's directory, and whether it is a note reference
/// ([isNoteReference]).
typedef EpubLink = ({String href, bool noteref});

/// A note laid out for the note sheet: one page that holds the note's
/// flow, and its picture, which draws no paper. Its owner disposes it.
class LaidNote {
  LaidNote._(this.page, this.picture, this._images);
  final LaidPage page;
  final ui.Picture picture;
  final Iterable<ui.Image> _images;

  void dispose() {
    picture.dispose();
    page.dispose();
    for (final image in _images) {
      image.dispose();
    }
  }
}

/// The owner of the shown place and the shown page of one open book.
///
/// The shown place is where the person is in the book: the place that the
/// last navigation went to, or the first place of the page that the last
/// turn showed. A change of the page settings keeps it.
///
/// The verbs that move run one at a time, in the order of the calls, so
/// that each one starts from the page that the one before showed.
///
/// Invariants, which [checkInvariants] checks:
/// - The shown page belongs to the current settings, and the page source
///   shows it, so it is pinned.
/// - The shown page holds the shown place, or starts at the line that holds
///   it. A page that shows no place keeps the place of the page before.
/// - The pager holds the prepared section of the shown page.
/// - The published page number, where known, is the shown page's, unless a
///   dropped kept page map gave the shown page a higher one.
class EpubPager implements DocumentNavigator {
  /// The pager of [document]. It opens at [initial] once the first
  /// [present] gives it page settings. [onPlace] receives each new place of
  /// the shown page. [onWarning] receives a message for the person.
  /// [onShow] hears each new shown page: with the visible characters of the
  /// page before when the person turned forward from that page, else with
  /// null.
  ///
  /// The pager owns [source], which defaults to a page source of the book
  /// with its kept page maps, and disposes it. [hop] runs each batch of a
  /// search in another isolate.
  EpubPager(
    EpubDocument document, {
    this._initial,
    required this._onPlace,
    required this._onWarning,
    this._onShow,
    PageSource? source,
    this._hop = compute,
  }) : _publication = document.publication,
       _source =
           source ??
           PageSource(document.publication, pageMaps: document.pageMaps) {
    _source.bookPages.addListener(_renumber);
    _source.keptMapDropped.addListener(_recount);
  }

  static const _mismatch =
      'The saved place does not match this text. Reading starts at the '
      'beginning.';
  static const _failure =
      'This chapter could not be displayed. Use Contents or retry the '
      'download.';

  final Publication _publication;
  final ValueChanged<EpubAddress> _onPlace;
  final ValueChanged<String> _onWarning;
  final ValueChanged<int?>? _onShow;
  final PageSource _source;
  final IsolateHop _hop;

  /// The saved place to open at, until a page for it or for the book's
  /// start is shown.
  ReaderAddress? _initial;

  /// The settings of the shown page, and the settings that the viewport
  /// presented last.
  PageSettings? _settings;
  PageSettings? _wanted;

  /// Whether a job that applies [_wanted] waits in the queue.
  bool _presenting = false;

  /// Completes at the first [present]. The verbs that go to a place wait
  /// for it, because a place needs page settings to be shown.
  final _presented = Completer<void>();

  final _shown = ValueNotifier<ShownPage?>(null);
  EpubPlace? _place;

  /// The prepared section of the shown page.
  PreparedSection? _section;

  /// The end of the last job in the queue.
  Future<void> _queue = Future.value();

  /// How many requests to show a destination ([display], [contents] and
  /// [seek]) the pager received. A page turn asked before such a request
  /// does not show its page, so the destination's place is the first place
  /// that the pager reports after the request (see [DocumentNavigator]).
  int _destinations = 0;

  /// The search request in progress, or null.
  int? _search;

  Future<List<SearchSection>>? _searchSections;
  bool _disposed = false;

  /// The page on screen with its picture, or null before the first page is
  /// shown.
  ValueListenable<ShownPage?> get shown => _shown;

  /// The number of the shown page and a page count. Once every section of
  /// the shown page's settings is laid out, they count the pages of the
  /// whole book. Before then, they count the pages of the shown page's
  /// section, as far as the section's main run knows them: the number is
  /// null until the main run passes the shown page's start, and the count
  /// until the main run ends. While a page stays shown, neither goes back.
  /// The reader shows "Page N", then "Page N of M".
  ValueListenable<PageNumber?> get pageNumber => _number;
  final _number = ValueNotifier<PageNumber?>(null);

  /// The whole-book page index of the current page settings, which the
  /// scrub bar spaces the book's pages by. It notifies once a section is
  /// laid out and once the settings change.
  ValueListenable<BookPages> get bookPages => _source.bookPages;

  /// Where the shown page ends: its section and the text progress of its
  /// last place, or null before the first page and for a page that shows
  /// no place. The shown page owns its end, and the address that the pager
  /// reports at a saved place has none, so the chapter arrows read it here.
  BookPlace? get shownEnd {
    final page = _shown.value?.page;
    final section = _section;
    final end = page?.endPlace ?? page?.startPlace;
    if (page == null || section == null || end == null) return null;
    return (part: page.section, progress: progressAt(section.dom, end));
  }

  /// The size of the book's main text on the shown page, as a factor of the
  /// text size that the page was laid out for ([PageSettings.fontSize]), or
  /// null before a page is shown. It is 1 when the reader's text size sizes
  /// the main text. Otherwise a book that fixes its own type sizes shows its
  /// main text at its own size. It measures in a worker.
  Future<double?> shownMainTextRatio() async {
    final settings = _shown.value?.page.settings;
    if (settings == null) return null;
    return await _source.shownMainText(settings) / settings.fontSize;
  }

  /// Completes when the shown page changes, which stops the waits for its
  /// number.
  Completer<void>? _counting;

  /// Asks for pages for [settings]: the viewport's size, the text size and
  /// the theme. It keeps the shown place and reports nothing. It notifies
  /// [shown] later, never during the call. The width, the height and the
  /// text size must be finite and above 0.
  void present(PageSettings settings) {
    if (_disposed) throw StateError('The pager is disposed.');
    bool positive(double value) => value > 0 && value.isFinite;
    if (!positive(settings.width) ||
        !positive(settings.height) ||
        !positive(settings.fontSize)) {
      throw ArgumentError.value(
        settings,
        'settings',
        'needs a page area and a text size',
      );
    }
    _wanted = settings;
    if (!_presented.isCompleted) _presented.complete();
    if (_presenting) return;
    _presenting = true;
    unawaited(
      _run(_apply).catchError((Object error) {
        if (!_disposed && error is! PageRequestStopped) _onWarning(_failure);
      }),
    );
  }

  /// The destination of the link under [point] of the shown page, relative
  /// to the package document's directory, or null. [point] is in logical
  /// pixels from the page's top left corner.
  EpubLink? linkAt(ui.Offset point) {
    final shown = _shown.value;
    final section = _section;
    if (shown == null || section == null) return null;
    final page = shown.page;
    if (point.dy < 0 || point.dy >= page.height) return null;
    final y = page.top + point.dy;
    for (final slice in page.slices) {
      if (y < slice.top || y >= slice.bottom) continue;
      for (final line in [slice, ...slice.cellSlices]) {
        final piece = line.piece;
        if (piece == null) continue;
        final local = ui.Offset(point.dx - piece.x, y - piece.y);
        final position = piece.paragraph.getPositionForOffset(local);
        final unit = position.affinity == ui.TextAffinity.downstream
            ? position.offset
            : position.offset - 1;
        if (unit < 0 || unit >= piece.map.length) continue;
        final boxes = piece.paragraph.getBoxesForRange(unit, unit + 1);
        if (!boxes.any((box) => box.toRect().contains(local))) continue;
        final place =
            piece.map.textPlaceAt(unit) ?? piece.map.placeAtUnit(unit);
        return place == null ? null : _linkOf(section, place);
      }
    }
    return null;
  }

  /// The note that [link] shows over the page, laid out [width] pixels
  /// wide with the shown page's text size and theme, or null when the link
  /// jumps instead (see [noteOf]), or when no flow item shows its note,
  /// such as a note that the book's style hides. It moves no place and
  /// reports nothing.
  ///
  /// The note leaves out its back links: a link that the book marks as one
  /// ([isBackLink]), or that points at a link to the note.
  ///
  /// The note's flow lays out in steps between frames. Its images are
  /// decoded at the screen's pixel ratio before it is drawn.
  Future<LaidNote?> note(EpubLink link, {required double width}) async {
    if (_settings == null) throw StateError('No page is shown yet.');
    if (!(width > 0 && width.isFinite)) {
      throw ArgumentError.value(width, 'width', 'must be above 0');
    }
    final (index, fragment) = _destinationOf(link.href);
    final prepared = await _source.section(index);
    final target = fragment == null ? null : prepared.dom.elementById(fragment);
    final note = noteOf(target, reference: link.noteref);
    final excerpt = note == null
        ? null
        : prepared.excerpt(
            note,
            PageSettings(
              width: width,
              height: _noteHeight,
              fontSize: prepared.settings.fontSize,
              night: prepared.settings.night,
              sizesMainText: prepared.settings.sizesMainText,
            ),
            omit: [
              for (final back in _linksIn(note))
                if (isBackLink(back) ||
                    await _pointsBack(back, index, (index, fragment)))
                  back,
            ],
          );
    if (excerpt == null) return null;
    final run = LayoutRun(excerpt);
    try {
      while (!run.done) {
        run.step(_noteStep);
        // The next step waits for the event loop, so frames go on.
        if (!run.done) await Future<void>.delayed(Duration.zero);
        if (_disposed) throw StateError('The pager is disposed.');
      }
    } finally {
      run.dispose();
    }
    final page = run.pages.single;
    final scale =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
    final images = await decodeImages(
      [page],
      (path) => _publication.resources[path],
      scale: scale,
    );
    return LaidNote._(
      page,
      drawPage(page, images, paper: false),
      images.values,
    );
  }

  /// The page height that a note lays out on, so that one page holds it.
  static const _noteHeight = 1e6;

  /// The time that one step of a note's layout takes at most, about a
  /// quarter of a frame.
  static const _noteStep = Duration(milliseconds: 4);

  /// Turns to the page after or before the shown page, and reports it. At
  /// the book's ends it does nothing, and so does a turn that a later
  /// request to show a destination supersedes.
  @override
  Future<void> move(bool forward) {
    final destinations = _destinations;
    return _run(() async {
      final shown = _shown.value;
      if (shown == null) return;
      final steps = await _spineSteps();
      final page = forward
          ? await _source.after(shown.page)
          : await _source.before(shown.page);
      if (page == null || destinations != _destinations) return;
      _show(
        page,
        page.startPlace ?? _place!,
        steps,
        report: true,
        read: forward ? shown.page : null,
      );
    });
  }

  /// Shows the page of [address], and reports it. Throws when the address
  /// is not in this book or its quote does not match the text.
  @override
  Future<void> display(ReaderAddress address) async {
    _destinations++;
    await _presented.future;
    return _run(() async {
      final steps = await _spineSteps();
      final place = await _resolve(address);
      if (place == null) {
        throw ArgumentError.value(address, 'address', 'is not in this text');
      }
      await _go(place, steps);
    });
  }

  /// Shows the destination [href], relative to the package document's
  /// directory, with an optional fragment, and reports it. Throws when it
  /// names no section of the spine or no element.
  @override
  Future<void> contents(String href) async {
    _destinations++;
    await _presented.future;
    return _run(() async {
      final steps = await _spineSteps();
      final (index, fragment) = _destinationOf(href);
      final dom = (await _source.section(index)).dom;
      final place = destination(dom, index, fragment);
      if (place == null) {
        throw ArgumentError.value(href, 'href', 'names no element');
      }
      await _go(place, steps);
    });
  }

  /// Shows the page that holds the place [progress] of the way through the
  /// text of section [part], and reports it.
  @override
  Future<void> seek(int part, double progress) async {
    RangeError.checkValidIndex(part, _publication.spine, 'part');
    if (!(progress >= 0 && progress <= 1)) {
      throw ArgumentError.value(progress, 'progress', 'must be from 0 to 1');
    }
    _destinations++;
    await _presented.future;
    return _run(() async {
      final steps = await _spineSteps();
      final dom = (await _source.section(part)).dom;
      await _go(placeAt(dom, part, progress), steps);
    });
  }

  /// Draws the true page that holds [place], [width] pixels wide, without
  /// moving the shown page.
  ///
  /// The page holds the visible characters from its first one up to the
  /// first one of the next true page. Its start is the text progress of its
  /// first character, and its end is the middle of its last one, or 1 for
  /// the section's last page with text. Its neighbors are the middle of the
  /// character before it and of the character after it, or the end of the
  /// previous section and the start of the next one. So exactly one page
  /// holds each neighbor, and a page that shows no text, such as a lone
  /// image, is no neighbor.
  @override
  Future<PagePreview> preview(
    BookPlace place,
    double width,
    Future<void> abandon,
  ) async {
    RangeError.checkValidIndex(place.part, _publication.spine, 'part');
    if (!(width > 0 && width <= 4096)) {
      throw ArgumentError.value(width, 'width', 'must be from 0 to 4096');
    }
    if (_settings == null) throw StateError('No page is shown yet.');
    final part = place.part;
    final dom = (await _source.section(part)).dom;
    final page = await _source.pageAt(
      placeAt(dom, part, place.progress),
      anchored: false,
      urgent: true,
      abandon: abandon,
    );
    final settings = page.settings;
    final ratio = width / settings.width;
    final drawn = _source.picture(page, scale: ratio);
    final following = page.last ? null : await _source.after(page);
    final picture = await drawn;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(ratio)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    final ui.Image image;
    try {
      image = await scaled.toImage(
        width.round(),
        (settings.height * ratio).round(),
      );
    } finally {
      scaled.dispose();
    }

    final total = dom.visibleLength;
    final first = page.startVisible;
    final end = following?.startVisible ?? total;
    final sections = _publication.spine.length;
    return PagePreview(
      part: part,
      start: total == 0 || first == 0 ? 0 : first / total,
      end: total == 0 || end >= total ? 1 : (end - .5) / total,
      image: image,
      previous: total > 0 && first > 0
          ? (part: part, progress: (first - .5) / total)
          : part > 0
          ? (part: part - 1, progress: 1)
          : null,
      next: end < total
          ? (part: part, progress: (end + .5) / total)
          : part + 1 < sections
          ? (part: part + 1, progress: 0)
          : null,
    );
  }

  /// Searches the book for [query] in batches of sections in worker
  /// isolates. A [cancelSearch] of [request] stops it between batches, with
  /// an empty report.
  @override
  Future<ReaderSearchReport> search(String query, int request) async {
    _search = request;
    final sections = await (_searchSections ??= _spineSteps().then(
      (steps) => [
        for (final (index, path) in _publication.spine.indexed)
          SearchSection(
            index: index,
            path: path,
            xhtml: _publication.resources[path]!,
            spine: steps[index],
          ),
      ],
    ));
    return searchBook(
      sections,
      query,
      _publication.contents,
      _publication.packagePath,
      isCurrent: () => !_disposed && _search == request,
      hop: _hop,
    );
  }

  @override
  Future<void> cancelSearch(int request) async {
    if (_search == request) _search = null;
  }

  /// Stops the searches and the work in progress, and lets go of every
  /// page.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _search = null;
    if (!_presented.isCompleted) _presented.complete();
    _counting?.complete();
    _source.bookPages.removeListener(_renumber);
    _shown.dispose();
    _number.dispose();
    _source.keptMapDropped.removeListener(_recount);
    _source.dispose();
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    if (_disposed) return;
    void check(bool holds, String message) {
      if (!holds) throw StateError('EpubPager: $message');
    }

    _source.checkInvariants();
    final shown = _shown.value;
    if (shown == null) {
      check(_section == null, 'a section is held without a shown page');
      check(_number.value == null, 'a page number without a shown page');
      return;
    }
    final page = shown.page;
    check(page.settings == _settings, 'the shown page has other settings');
    check(
      identical(_source.shown, page),
      'the page source does not show the shown page',
    );
    final section = _section;
    check(
      section != null &&
          section.index == page.section &&
          section.settings == page.settings,
      'the held section is not the shown page\'s',
    );
    final number = _number.value;
    final known = _numberOf(page);
    check(
      _numberHeld ||
          number == null ||
          (number.number == known?.number &&
              (number.count == null || number.count == known?.count)),
      'the page number is not the shown page\'s',
    );
    if (page.startPlace == null) return;
    final place = _place!;
    check(place.section == page.section, 'the shown place is elsewhere');
    final line = lineStart(section!, place);
    check(
      page.start == line ||
          (page.start.compareTo(line) < 0 &&
              line.compareTo(page.slices.last.at) <= 0),
      'the shown page does not hold the shown place',
    );
  }

  /// Runs [job] after every job before it.
  Future<T> _run<T>(Future<T> Function() job) {
    final done = _queue.then((_) {
      if (_disposed) throw StateError('The pager is disposed.');
      return job();
    });
    _queue = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// Shows the page for the settings that the viewport presented last, at
  /// the shown place, or opens the book.
  Future<void> _apply() async {
    _presenting = false;
    final settings = _wanted!;
    if (settings == _settings) return;
    final steps = await _spineSteps();
    _source.settings = settings;
    final place = _place;
    if (place != null) {
      final page = await _source.pageAt(place, anchored: true, urgent: true);
      _show(page, place, steps);
      return;
    }
    // Open the book.
    final initial = _initial;
    if (initial is EpubAddress) {
      if (await _resolve(initial) case final place?) {
        final page = await _source.pageAt(place, anchored: true, urgent: true);
        _show(page, place, steps);
        _initial = null;
        _onPlace(initial);
        return;
      }
    }
    final dom = (await _source.section(0)).dom;
    final start = EpubPlace(0, dom.body.order, 0);
    final page = await _source.pageAt(start, anchored: true, urgent: true);
    _show(page, start, steps, report: initial == null);
    _initial = null;
    if (initial != null) _onWarning(_mismatch);
  }

  /// Shows the page that holds [place], and reports it.
  Future<void> _go(EpubPlace place, List<String> steps) async {
    final page = await _source.pageAt(place, anchored: true, urgent: true);
    _show(page, place, steps, report: true);
  }

  /// The place of [address] in this book, when its quote matches the text
  /// there.
  Future<EpubPlace?> _resolve(ReaderAddress address) async {
    if (address is! EpubAddress) return null;
    final location = address.location;
    final index = _publication.spine.indexOf(location.resource);
    if (index < 0) return null;
    final dom = (await _source.section(index)).dom;
    final place = placeOf(dom, index, location.cfi);
    return place != null && quoteMatches(dom, place, location.quote)
        ? place
        : null;
  }

  /// Shows [page] at [place], and reports the page's address when
  /// [report]. [steps] are the spine steps of the book's CFIs. [read] is the
  /// page that the person turned forward from, if any.
  void _show(
    LaidPage page,
    EpubPlace place,
    List<String> steps, {
    bool report = false,
    LaidPage? read,
  }) {
    if (_disposed) throw StateError('The pager is disposed.');
    _source.show(page);
    final section = _source.sectionOf(page);
    _settings = page.settings;
    _section = section;
    _place = place;
    _shown.value = ShownPage(page, _source.draft(page));
    _sharpen(page);
    _count(page);
    _onShow?.call(read == null ? null : read.endVisible - read.startVisible);
    final start = page.startPlace;
    if (!report || start == null) return;
    final dom = section.dom;
    final path = _publication.spine[page.section];
    final end = page.endPlace ?? start;
    _onPlace(
      EpubAddress(
        pageLocation(
          steps[page.section],
          path,
          dom,
          start,
          end,
          chapterTitle(
            dom,
            firstVisible(dom, start, end),
            _publication.contents,
            _publication.packagePath,
            path,
          ),
        ),
      ),
    );
  }

  /// Shows [page] again with its images, once they are decoded at the
  /// screen's pixel ratio.
  void _sharpen(LaidPage page) {
    final scale =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
    unawaited(
      _source.picture(page, scale: scale).then(
        (picture) {
          final shown = _shown.value;
          if (!_disposed &&
              shown != null &&
              identical(shown.page, page) &&
              !identical(shown.picture, picture)) {
            _shown.value = ShownPage(page, picture);
          }
        },
        // A page that left the cache is no longer shown.
        onError: (Object _) {},
      ),
    );
  }

  /// The number of [page] in the whole book once the whole book is laid out
  /// in its settings, else in its section.
  PageNumber? _numberOf(LaidPage page) =>
      _source.bookNumberOf(page) ?? _source.numberOf(page);

  /// Publishes the shown page's number again once the page index changes.
  /// It reads the index of the page's own settings, so an index of new
  /// settings changes nothing until a page of them is shown.
  void _renumber() {
    if (_shown.value case final shown? when !_disposed) _publish(shown.page);
  }

  /// Counts the shown page again, after a page contradicted the kept page
  /// map that gave its number.
  void _recount() {
    if (_shown.value case final shown? when !_disposed) _count(shown.page);
  }

  /// Publishes the number of [page], and again each time the main run of
  /// its section learns more, while [page] is shown. The page index tells
  /// [_renumber] when the whole book is laid out.
  void _count(LaidPage page) {
    _counting?.complete();
    _counting = null;
    _publish(page);
    final known = _source.numberOf(page);
    if (known?.count != null) return;
    final stop = _counting = Completer<void>();
    void update() {
      if (!_disposed && identical(_shown.value?.page, page)) _publish(page);
    }

    unawaited(() async {
      try {
        if (known == null) {
          await _source.mainRun(page, abandon: stop.future);
          update();
        }
        await _source.mainRun(page, end: true, abandon: stop.future);
        update();
      } on PageRequestStopped {
        // Another page is shown, or the settings changed.
      }
    }());
  }

  /// Publishes the number of [page]. While a page stays shown, its number
  /// and its count never go back. Only a kept page map that a page
  /// contradicted can lower them: its starts drop, and the book is laid out
  /// again. The higher number then stays until another page is shown.
  void _publish(LaidPage page) {
    final number = _numberOf(page);
    final published = _number.value;
    _numberHeld =
        identical(page, _numbered) &&
        published != null &&
        (number == null ||
            number.number < published.number ||
            (number.count ?? 0) < (published.count ?? 0));
    if (_numberHeld) return;
    _numbered = page;
    _number.value = number;
  }

  /// The page whose number [pageNumber] holds, and whether it holds a
  /// higher number than the page's, which a dropped kept map gave.
  LaidPage? _numbered;
  bool _numberHeld = false;

  /// The spine index and the decoded fragment, or null for none, of
  /// [href], relative to the package document's directory. Throws when it
  /// names no section of the spine.
  (int, String?) _destinationOf(String href) =>
      _hrefTarget(_publication.packagePath, href) ??
      (throw ArgumentError.value(href, 'href', 'is not a section of the book'));

  /// The section index and the fragment that [href] names, relative to the
  /// book file at [base], or null when it names no section of the book.
  (int, String?)? _hrefTarget(String base, String href) {
    final Uri url;
    try {
      url = Uri(scheme: 'https', host: 'book', path: '/$base').resolve(href);
    } on FormatException {
      return null;
    }
    final index = url.scheme == 'https' && url.host == 'book' && !url.hasQuery
        ? _publication.spine.indexOf(url.pathSegments.join('/'))
        : -1;
    if (index < 0) return null;
    final fragment = url.hasFragment && url.fragment.isNotEmpty
        ? Uri.decodeComponent(url.fragment)
        : null;
    return (index, fragment);
  }

  /// The `a` elements with an href at or inside [element], in document
  /// order.
  static Iterable<DomElement> _linksIn(DomElement element) sync* {
    if (element.name == 'a' && element.attributes['href'] != null) {
      yield element;
    }
    for (final child in element.elements) {
      yield* _linksIn(child);
    }
  }

  /// Whether [link], in section [section], points at a link to
  /// [destination]: a link at, around or inside the element that it names.
  Future<bool> _pointsBack(
    DomElement link,
    int section,
    (int, String?) destination,
  ) async {
    final target = _hrefTarget(
      _publication.spine[section],
      link.attributes['href']!,
    );
    if (target == null) return false;
    final (index, fragment) = target;
    if (fragment == null) return false;
    final named = (await _source.section(index)).dom.elementById(fragment);
    if (named == null) return false;
    final base = _publication.spine[index];
    bool leads(DomElement element) =>
        _hrefTarget(base, element.attributes['href']!) == destination;
    for (DomElement? around = named; around != null; around = around.parent) {
      if (around.name == 'a' && around.attributes['href'] != null) {
        return leads(around);
      }
    }
    return _linksIn(named).any(leads);
  }

  /// The nearest link that holds [place], or null when none does.
  EpubLink? _linkOf(PreparedSection section, EpubPlace place) {
    final node = section.dom.nodeAt(place.node);
    var element = node is DomText ? node.parent : node as DomElement;
    while (element != null &&
        !(element.name == 'a' && element.attributes['href'] != null)) {
      element = element.parent;
    }
    if (element == null) return null;
    final Uri url;
    try {
      url = Uri(
        scheme: 'https',
        host: 'book',
        path: '/${_publication.spine[section.index]}',
      ).resolve(element.attributes['href']!);
    } on FormatException {
      return null;
    }
    if (url.scheme != 'https' || url.host != 'book' || url.hasQuery) {
      return null;
    }
    final directory = _publication.packagePath.split('/')..removeLast();
    final parts = [...url.pathSegments];
    while (directory.isNotEmpty &&
        parts.isNotEmpty &&
        directory.first == parts.first) {
      directory.removeAt(0);
      parts.removeAt(0);
    }
    return (
      href:
          '${[...directory.map((_) => '..'), ...parts.map(Uri.encodeComponent)].join('/')}'
          '${url.hasFragment ? '#${url.fragment}' : ''}',
      noteref: isNoteReference(element),
    );
  }

  /// The spine step of each section's CFIs, which admission found.
  Future<List<String>> _spineSteps() async => _publication.spineSteps;
}
