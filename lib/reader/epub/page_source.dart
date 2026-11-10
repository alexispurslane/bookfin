// The pages of one open book: its prepared sections, layout runs, page
// starts, laid pages, decoded images and embedded fonts.
//
// Preparing a section runs in a worker isolate, one worker call for each
// section. Layout runs on the UI isolate, in steps that a scheduler runs
// between frames, from the shown place outward until the whole book is
// laid out: every section knows its true page starts.
//
// A page cut depends only on the strip from its start down to one page
// height below it (layout.dart). So the page that starts at a page start is
// the same page whichever run cut it, and the cache keys a page by its
// section, its settings and its start. A dropped page comes back the same
// when a run lays it out again from its start.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../book_pages.dart';
import 'dom.dart';
import 'fonts.dart';
import 'layout.dart';
import 'page_maps.dart';
import 'paint.dart';
import 'prepare.dart';
import 'publication.dart';

/// Runs [step] once, between frames. An [urgent] step runs even while an
/// animation runs. Other steps wait for idle time.
typedef StepScheduler = void Function(
  void Function() step, {
  required bool urgent,
});

/// The number of a page among the true pages of its section, from 1, and
/// the number of true pages in the section, or null while the section's
/// main run has not ended.
typedef PageNumber = ({int number, int? count});

/// A request that stopped before its page was ready: its abandon future
/// completed, another page was shown, the source was disposed, or the
/// settings of its page were dropped.
class PageRequestStopped implements Exception {
  const PageRequestStopped(this.reason);
  final String reason;

  @override
  String toString() => 'PageRequestStopped: $reason';
}

/// The owner of the pages of one open book.
///
/// The order of work: a caller's urgent request goes first, such as the
/// anchored page that the reader opens or jumps to. Once a page is shown,
/// the work goes from it outward: its next and previous pages, then its
/// section's main run, then the next section's first page. Then two
/// directions go on at the same time, one through the sections after the
/// shown one in order (S+1, S+2, ...), the other through the sections
/// before it (S-1, S-2, ...). Each direction prepares one section at a
/// time in a worker call of its own, so neither waits for the other's
/// prepare, and their layout steps take turns. A direction ends at the
/// book's end, so the whole book is laid out if the reader stays. Each
/// show, settings change and dispose starts the order again or ends it.
///
/// Layout steps that a caller did not ask for urgently wait while an
/// animation runs and while the app is in the background. A direction
/// starts its next prepare only after its section's main run ended, so
/// that it pauses with them.
///
/// The whole book laid out keeps every section's page starts, not its
/// prepared text: once its main run ends, a section more than one section
/// away from the shown one lets go of its prepared text and its pages.
///
/// A book with kept page maps ([BookPageMaps]) reads the map of each
/// settings value when the settings come into use, beside the first page's
/// prepare. The map's true pages seed each section that no run started,
/// so the section counts as laid out: its page numbers and where its pages
/// start in its text are known at once, and the whole-book work neither
/// prepares nor lays it out. A place in a seeded section finds its page by
/// the pages' kept first places, with no line search ([keptLineStart]):
/// the source lays out that page, and the next one when the place lies
/// after everything that the page shows. Each page that a run cuts from a seeded start checks
/// that its first place is the kept one and that the next seeded start
/// follows it. The map also keeps the widths of each table's cells, which
/// a run from a start inside a table needs first, and each prepared
/// section of a seeded section reuses them ([reuseMeasures]). A run
/// measures each kept table row that it lays out again. The first page or
/// row that contradicts the map forgets it: the seeded pages and widths
/// drop, the file goes, and the whole book is laid out again. A section
/// whose main run ended reuses that run's widths in the same way when it
/// is prepared again.
/// Once every section's main run ended and no section is seeded, the source
/// keeps the map.
///
/// It keeps the work of the current page settings and of the previous
/// ones, so that a change back costs no worker call. The previous settings
/// are those of the shown page when the settings change, or the settings
/// before the change when they equal the new value or nothing is shown.
///
/// The source owns every page and picture that it returns. A page stays
/// usable until the cache drops it. The shown page and its two neighbors
/// never leave the cache, so show a page before keeping it.
///
/// Invariants, which [checkInvariants] checks:
/// - Every cached page belongs to a cached prepared section, of the current
///   or the previous settings, and its key is its own start.
/// - The true page starts of a section increase, and each page's following
///   start comes after it.
/// - No pinned page (the shown page and its neighbors) is out of the cache.
/// - Each cache is within its limit, or holds nothing that it may evict.
/// - A section has at most one main run and one anchored run, and only
///   while its prepared section is cached.
/// - A section that a kept map seeded has no main run, and its main run
///   counts as ended. Kept maps are read only for the current and the
///   previous settings.
/// - Every request of the work around the shown page is in progress.
/// - Each true page start has its first place and its visible start, and
///   a section whose main run ended lists them in the page index.
/// - The published page index is the current settings' one.
class PageSource {
  /// The pages of [publication]. [schedule] runs each layout step; it
  /// defaults to [scheduleBetweenFrames]. Each step lays out
  /// paragraphs until [budget] is spent, and then stops after the paragraph
  /// that crosses it. Set [settings] before the first request.
  PageSource(
    Publication publication, {
    StepScheduler? schedule,
    Duration budget = const Duration(milliseconds: 4),
    this._pageMaps,
  }) : _publication = publication,
       _schedule = schedule ?? scheduleBetweenFrames,
       _stepBudget = budget,
       _fontPrefix = 'bookfin-${publication.identity.substring(0, 12)}';

  // The limits of the design's cache table. E20 (tc-ptuo), which was to
  // tune them on the phone, was dropped; they stay at the values that the
  // design picked from host measurements.
  static const _maxPrepared = 6;
  static const _maxPreparedCharacters = 1500000;
  static const _maxPages = 24;
  static const _maxImageBytes = 32 * 1024 * 1024;

  /// Runs [step] as a Flutter task. A step that is not [urgent] waits while
  /// a frame is scheduled, for example while an animation runs, and while
  /// the app is in the background, where frames are disabled. It waits
  /// outside the task queue, for the end of the next frame. There it runs at
  /// once, unless a new frame is scheduled, and then it waits for the end of
  /// that frame. So it wakes the event loop at most once a frame, a frame
  /// waits for at most one idle step, and a waiting step holds no timer.
  ///
  /// IMPORTANT: Flutter's task queue runs one task for each turn of the
  /// event loop, but on an Android emulator a requested frame still waited
  /// for about five idle steps in a row, 20 to 44 ms (t7-bbv1). So an idle
  /// step does not run while a frame is scheduled.
  ///
  /// Both kinds of step use [Priority.animation], so that Flutter's default
  /// strategy never holds them in the queue. A held task makes the queue
  /// ask again at once with a zero timer, a busy loop between frames for
  /// as long as the animation runs.
  ///
  /// An animation that goes on schedules the next frame during each frame.
  /// The app's return from the background enables frames and schedules
  /// one. So a frame always comes after a step starts to wait, and the step
  /// runs at the end of the first frame after which no frame is scheduled
  /// and the app is in the foreground. A screen that asks for a frame at
  /// the end of every frame holds idle steps back, as an animation does
  /// (boo-2mn9).
  static void scheduleBetweenFrames(
    void Function() step, {
    required bool urgent,
  }) {
    final binding = SchedulerBinding.instance;
    bool held() =>
        !urgent && (binding.hasScheduledFrame || !binding.framesEnabled);
    void afterFrame(Duration _) {
      if (held()) {
        binding.addPostFrameCallback(afterFrame);
      } else {
        step();
      }
    }

    unawaited(
      binding.scheduleTask(() {
        if (held()) {
          binding.addPostFrameCallback(afterFrame);
        } else {
          step();
        }
      }, Priority.animation),
    );
  }

  final Publication _publication;
  final BookPageMaps? _pageMaps;
  final StepScheduler _schedule;
  final Duration _stepBudget;
  final String _fontPrefix;

  PageSettings? _settings;
  PageSettings? _previous;
  bool _disposed = false;

  /// Every section's layout in the current and previous settings, by
  /// section and settings. A layout keeps its page starts after the cache
  /// drops its prepared section.
  final _layouts = <(int, PageSettings), _SectionLayout>{};

  /// The layouts whose prepared section is cached, least recently used
  /// first.
  final _prepared = LinkedHashSet<_SectionLayout>.identity();

  /// The cached pages, least recently used first.
  final _pages = <_PageKey, _CachedPage>{};

  /// The shown page, and the pages that never leave the cache: the shown
  /// page and its neighbors.
  _PageKey? _shown;
  final _pinned = <_PageKey>{};

  /// The decoded images, least recently used first, and their size.
  final _images = <_ImageKey, ui.Image>{};
  int _imageBytes = 0;
  final _decoding = <_ImageKey, Future<ui.Image?>>{};
  final _broken = <_ImageKey>{};

  /// The images that a picture being drawn uses, with a count of drawings.
  final _drawing = <_ImageKey, int>{};

  /// The requests in progress: the callers' and the source's own work
  /// around the shown page.
  final _requests = <_Request>[];
  final _around = <_Request>[];
  int _order = 0;

  /// The number of times that the work around the shown page started
  /// again or ended. A direction ends when it changes.
  int _generation = 0;

  bool _urgentScheduled = false;
  bool _idleScheduled = false;

  /// The read of the kept page map of each settings value in use. Each one
  /// completes once the map seeded its sections, or with no map.
  final _reading = <PageSettings, Future<void>>{};

  int get _sectionCount => _publication.spine.length;

  PageSettings get _current =>
      _settings ?? (throw StateError('Set the page settings first.'));

  /// Pages for [value] from now on. The previous settings' prepared
  /// sections and page starts stay until the next change.
  set settings(PageSettings value) {
    if (_disposed) throw StateError('The page source is disposed.');
    final current = _settings;
    if (value == current) return;
    if (current != null) {
      final kept = _shown?.layout.settings ?? current;
      _previous = kept == value ? current : kept;
    }
    _settings = value;
    _stopAround(const PageRequestStopped('The page settings changed.'));
    for (final layout in [..._layouts.values]) {
      if (layout.settings != value && layout.settings != _previous) {
        _drop(layout);
      }
    }
    _reading.removeWhere((kept, _) => kept != value && kept != _previous);
    _readMap(value);
    _bookPages.value = _bookPagesIn(value);
  }

  /// Section [index] prepared for the current settings, in a worker.
  Future<PreparedSection> section(int index) {
    final layout = _layoutFor(index, _current);
    return _ask(_Rank.asked, null, (request) => _ready(layout, request));
  }

  /// The true page that holds [place] if the main run passed it; else, when
  /// [anchored], the page that starts at the line that holds it; else waits
  /// for the true page. [urgent] work goes first. [abandon] stops a wait,
  /// and the future fails with [PageRequestStopped].
  Future<LaidPage> pageAt(
    EpubPlace place, {
    required bool anchored,
    bool urgent = false,
    Future<void>? abandon,
  }) {
    final layout = _layoutFor(place.section, _current);
    return _ask(urgent ? _Rank.asked : _Rank.waiting, abandon, (request) async {
      final line = await _lineStart(layout, place, request);
      Future<LaidPage> resolve() async {
        if (!anchored) await _known(layout, line, request);
        return _resolve(layout, line, request);
      }

      final page = await resolve();
      // Only a page from a kept start that contradicted the kept map can
      // miss the line, and that page forgot the map.
      return _holds(page, line) ? page : resolve();
    });
  }

  /// The page cut after [page], the next section's first page, or null.
  ///
  /// After an anchored page that the main run passed, it is the true page
  /// that holds the line after [page], so a turn never skips text.
  Future<LaidPage?> after(LaidPage page) =>
      _ask(_Rank.asked, null, (request) => _after(page, request));

  /// The true page before [page] (waits for the main run), the previous
  /// section's last page, or null.
  Future<LaidPage?> before(LaidPage page) =>
      _ask(_Rank.asked, null, (request) => _before(page, request));

  /// Whether a main run cut [page]: a section's first page, or a page
  /// whose start the main run reached. An anchored page becomes true once
  /// the main run reaches its start, if that start is a true page start.
  bool isTrue(LaidPage page) {
    if (page.start == const PageStart(0, 0)) return true;
    final layout = _layouts[(page.section, page.settings)];
    return layout != null && layout.isTrueStart(page.start);
  }

  /// The number of [page] among the true pages of its section: the number
  /// of true page starts at or before its start. Null while the section's
  /// main run has not passed its start.
  PageNumber? numberOf(LaidPage page) {
    final layout = _layoutOf(page);
    if (page.start == const PageStart(0, 0)) {
      return (
        number: 1,
        count: layout?.mainDone ?? false ? layout!.starts.length : null,
      );
    }
    if (layout == null || !layout.knows(page.start)) return null;
    return (
      number: layout._search(page.start).$1 + 1,
      count: layout.mainDone ? layout.starts.length : null,
    );
  }

  /// Completes once the main run of [page]'s section passed [page]'s start,
  /// or reached the section end when [end]. It waits with the shown
  /// section's main run. [abandon] stops the wait, and the future fails
  /// with [PageRequestStopped].
  Future<void> mainRun(
    LaidPage page, {
    bool end = false,
    Future<void>? abandon,
  }) {
    final layout = _layoutOf(page) ?? _settingsChanged();
    return _ask(
      _Rank.shownRun,
      abandon,
      (request) => _known(layout, end ? null : page.start, request),
    );
  }

  /// The whole-book page index of the current settings: the true pages of
  /// each section whose main run ended. It notifies once a section is laid
  /// out and once the settings change, never once a page.
  ValueListenable<BookPages> get bookPages => _bookPages;
  late final _bookPages = ValueNotifier(_bookPagesIn(_settings));

  /// The number of [page] among the true pages of the whole book, and the
  /// book's page count, once every section of [page]'s settings is laid
  /// out. Null before then, and while the main run of [page]'s section has
  /// not passed its start.
  PageNumber? bookNumberOf(LaidPage page) {
    final number = numberOf(page);
    final index = _bookPagesIn(page.settings);
    final count = index.count;
    if (number == null || count == null) return null;
    return (
      number: index.numberOf(page.section, number.number - 1)!,
      count: count,
    );
  }

  /// Whether the main run of [section] ended in the current settings, so
  /// that every true page start of the section is known.
  bool laidOut(int section) => _layouts[(section, _current)]?.mainDone ?? false;

  /// Notifies when a page contradicted a kept page map, so that the true
  /// page starts that the map gave are dropped. A page number that the map
  /// gave can then be unknown until a main run passes the page again.
  Listenable get keptMapDropped => _keptMapDropped;

  /// The number of kept maps that pages contradicted.
  final _keptMapDropped = ValueNotifier(0);

  /// The number of line searches that requests started, for tests.
  @visibleForTesting
  int get lineSearches => _lineSearches;
  int _lineSearches = 0;

  /// The page that [show] showed last, while it is in the cache.
  LaidPage? get shown => _pages[_shown]?.page;

  /// The prepared section of [page], which must be in the cache. It stays
  /// prepared while [page] is shown or pinned.
  PreparedSection sectionOf(LaidPage page) => _cachedOf(page).layout.prepared!;

  /// A picture now, with outlines for images not decoded yet.
  ui.Picture draft(LaidPage page) {
    final cached = _cachedOf(page);
    final wanted = _imagesOf(page, 1);
    if (wanted.isEmpty) return cached.plain();
    return cached.draft ??= drawPage(page, {
      for (final key in _broken)
        if (wanted.containsKey(key.path)) key.path: null,
      for (final MapEntry(key: key, value: image) in _images.entries)
        if (wanted.containsKey(key.path)) key.path: image,
    });
  }

  /// A picture once the page's images are decoded at [scale] image pixels
  /// per layout pixel.
  Future<ui.Picture> picture(LaidPage page, {double scale = 1}) async {
    final cached = _cachedOf(page);
    final wanted = _imagesOf(page, scale);
    if (wanted.isEmpty) return cached.plain();
    if (cached.pictures[scale] case final drawn?) return drawn;
    final keys = wanted.values.toList();
    for (final key in keys) {
      _drawing[key] = (_drawing[key] ?? 0) + 1;
    }
    try {
      final images = await Future.wait(keys.map(_decode));
      if (_disposed || cached.disposed) {
        throw const PageRequestStopped('The page left the cache.');
      }
      if (cached.pictures[scale] case final drawn?) return drawn;
      cached.images.addAll(keys);
      return cached.pictures[scale] = drawPage(page, {
        for (final (index, key) in keys.indexed) key.path: images[index],
      });
    } finally {
      for (final key in keys) {
        if ((_drawing[key] = _drawing[key]! - 1) == 0) _drawing.remove(key);
      }
      if (!_disposed) _trim();
    }
  }

  /// The shown page: pin it and its neighbors, and plan work around it.
  ///
  /// The work goes from the shown place outward, in the order of the class
  /// comment, and replaces the work around the page shown before.
  void show(LaidPage page) {
    final cached = _cachedOf(page);
    final key = (layout: cached.layout, start: page.start);
    _stopAround(const PageRequestStopped('Another page is shown.'));
    _shown = key;
    _pinned
      ..clear()
      ..add(key);
    _touchPage(key);
    final layout = cached.layout;
    void neighbor(Future<LaidPage?> Function(_Request request) work) =>
        _aroundShown(_Rank.neighbor, work).then((result) {
          if (result != null && _shown == key) {
            if (_layoutOf(result) case final at?) {
              _pinned.add((layout: at, start: result.start));
            }
          }
        }, onError: (Object _) {});

    neighbor((request) => _after(page, request));
    neighbor((request) => _before(page, request));
    if (page.section + 1 < _sectionCount) {
      final next = _layoutFor(page.section + 1, layout.settings);
      _aroundShown(
        _Rank.nextStart,
        (request) => _page(next, const PageStart(0, 0), request),
      ).ignore();
    }
    _layOutFrom(layout);
    _trim();
  }

  /// Lays out the whole book from the shown section [shown] outward: its
  /// main run, then the two directions.
  void _layOutFrom(_SectionLayout shown) {
    _aroundShown(
      _Rank.shownRun,
      (request) => _known(shown, null, request),
    ).ignore();
    unawaited(_outward(shown, -1));
    unawaited(_outward(shown, 1));
  }

  /// Stops every request, and lets go of every page, run and image.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    for (final request in [..._requests]) {
      request.stop(const PageRequestStopped('The page source is disposed.'));
    }
    for (final layout in _layouts.values) {
      layout.disposeRuns();
    }
    for (final cached in _pages.values) {
      cached.dispose();
    }
    for (final image in _images.values) {
      image.dispose();
    }
    _layouts.clear();
    _prepared.clear();
    _pages.clear();
    _pinned.clear();
    _images.clear();
    _reading.clear();
    _shown = null;
    _bookPages.dispose();
    _keptMapDropped.dispose();
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    void check(bool holds, String message) {
      if (!holds) throw StateError('PageSource: $message');
    }

    for (final MapEntry(key: (index, settings), value: layout)
        in _layouts.entries) {
      check(
        layout.index == index && layout.settings == settings,
        'a layout is filed under another key',
      );
      check(
        settings == _settings || settings == _previous,
        'a layout belongs to dropped settings',
      );
      check(
        _prepared.contains(layout) == (layout.prepared != null),
        'the prepared sections and their order disagree',
      );
      final starts = layout.starts;
      for (var at = 1; at < starts.length; at++) {
        check(
          starts[at].compareTo(starts[at - 1]) > 0,
          'the page starts of section $index do not increase',
        );
      }
      check(
        layout.visibleStarts.length == layout.starts.length &&
            layout.firsts.length == layout.starts.length,
        'a true page start of section $index has no first place or no '
        'visible start',
      );
      if (layout.pages case final pages?) {
        check(
          pages.count == layout.starts.length &&
              listEquals(pages.visible?.starts, layout.visibleStarts),
          'the page index of section $index is not its true pages',
        );
      }
      for (final MapEntry(key: start, value: next)
          in layout.following.entries) {
        check(next.compareTo(start) > 0, 'a following start comes before');
      }
      if (layout.prepared == null) {
        check(
          layout.main == null && layout.anchored == null,
          'a section without its prepared section has a run',
        );
      }
      if (layout.seeded) {
        check(
          layout.mainDone && layout.main == null,
          'a section that a kept map seeded has a main run to go',
        );
        check(
          _reading.containsKey(settings),
          'a section was seeded with no read of a kept map',
        );
      }
      for (final run in [?layout.main, ?layout.anchored]) {
        run.run.checkInvariants();
      }
    }
    for (final layout in _prepared) {
      check(
        identical(_layouts[(layout.index, layout.settings)], layout),
        'a prepared section belongs to a dropped layout',
      );
    }
    for (final settings in _reading.keys) {
      check(
        settings == _settings || settings == _previous,
        'a kept map is read for dropped settings',
      );
    }
    for (final MapEntry(:key, value: cached) in _pages.entries) {
      final layout = key.layout;
      final page = cached.page;
      check(
        identical(_layouts[(layout.index, layout.settings)], layout),
        'a cached page belongs to a dropped layout',
      );
      check(layout.prepared != null, 'a cached page has no prepared section');
      check(
        page.section == layout.index &&
            page.settings == layout.settings &&
            page.start == key.start,
        'a cached page is filed under another key',
      );
      check(!cached.disposed, 'a cached page is disposed');
    }
    final published = _bookPages.value.parts;
    final index = _bookPagesIn(_settings).parts;
    check(
      published.length == index.length &&
          [for (var at = 0; at < index.length; at++) published[at] == index[at]]
              .every((same) => same),
      'the published page index is not the current settings\' one',
    );
    check(
      _around.every(_requests.contains),
      'a request around the shown page ended but is kept',
    );
    check(
      _shown == null || _pinned.contains(_shown),
      'the shown page is not pinned',
    );
    for (final key in _pinned) {
      check(_pages.containsKey(key), 'a pinned page left the cache');
    }
    check(
      _pages.length <= _maxPages || _pages.keys.every(_pinned.contains),
      'the page cache is over its limit',
    );
    final kept = _keptLayouts();
    check(
      _preparedWithin() || _prepared.every(kept.contains),
      'the prepared sections are over their limit',
    );
    final shownImages = _shownImages();
    check(
      _imageBytes <= _maxImageBytes ||
          _images.keys.every(
            (key) => shownImages.contains(key) || _drawing.containsKey(key),
          ),
      'the decoded images are over their limit',
    );
    var bytes = 0;
    for (final image in _images.values) {
      bytes += _bytesOf(image);
    }
    check(bytes == _imageBytes, 'the image bytes are miscounted');
  }

  // Requests.

  /// Runs [work] as a request of [rank], until [abandon] completes.
  Future<T> _ask<T>(
    _Rank rank,
    Future<void>? abandon,
    Future<T> Function(_Request request) work,
  ) => _start(rank, abandon, work).$2;

  (_Request, Future<T>) _start<T>(
    _Rank rank,
    Future<void>? abandon,
    Future<T> Function(_Request request) work,
  ) {
    if (_disposed) throw StateError('The page source is disposed.');
    final request = _Request(rank, _order++);
    _requests.add(request);
    abandon?.then(
      (_) =>
          request.stop(const PageRequestStopped('The request was abandoned.')),
    );
    Future<T> run() async {
      try {
        return await work(request);
      } finally {
        _requests.remove(request);
        _around.remove(request);
        request.need = null;
        if (!_disposed) _trim();
      }
    }

    return (request, run());
  }

  /// Runs [work] as the source's own request of [rank] around the shown
  /// page. The next show or settings change stops it.
  Future<T> _aroundShown<T>(
    _Rank rank,
    Future<T> Function(_Request request) work,
  ) {
    final (request, done) = _start(rank, null, work);
    _around.add(request);
    return done;
  }

  /// Stops the work around the shown page with [reason], and ends the
  /// directions.
  void _stopAround(PageRequestStopped reason) {
    _generation++;
    for (final request in [..._around]) {
      request.stop(reason);
    }
    _around.clear();
  }

  /// One direction of the work around the shown page: the main run of each
  /// section beyond [shown] in the direction of [step] (1 or -1), nearest
  /// first, until the book's end or until the work around the shown page
  /// starts again. Its first section is the one next to [shown].
  ///
  /// A section that cannot be prepared or laid out is passed by; the reader
  /// meets its error on a page of it. A section more than one section away
  /// from [shown] lets go of its prepared text once its main run ends,
  /// unless a pinned page or another request keeps it.
  Future<void> _outward(_SectionLayout shown, int step) async {
    final generation = _generation;
    for (
      var index = shown.index + step;
      index >= 0 && index < _sectionCount;
      index += step
    ) {
      if (_disposed || _generation != generation) return;
      final layout = _layoutFor(index, shown.settings);
      if (layout.mainDone) continue;
      try {
        await _aroundShown(
          _Rank.outward,
          (request) => _known(layout, null, request),
        );
      } on PageRequestStopped {
        return;
      } catch (_) {
        continue;
      }
      // A newer show can be near this section.
      if (_disposed || _generation != generation) return;
      if ((index - shown.index).abs() > 1 &&
          layout.prepared != null &&
          !_keptLayouts().contains(layout)) {
        _unprepare(layout);
      }
    }
  }

  Future<LaidPage?> _after(LaidPage page, _Request request) async {
    final layout = _layoutOf(page) ?? _settingsChanged();
    if (page.last) {
      if (page.section + 1 >= _sectionCount) return null;
      final next = _layoutFor(page.section + 1, layout.settings);
      return _page(next, const PageStart(0, 0), request);
    }
    final next = layout.following[page.start];
    if (next == null) throw StateError('No page follows this page.');
    return _resolve(layout, next, request);
  }

  Future<LaidPage?> _before(LaidPage page, _Request request) async {
    final layout = _layoutOf(page) ?? _settingsChanged();
    if (page.start == const PageStart(0, 0)) {
      if (page.section == 0) return null;
      final previous = _layoutFor(page.section - 1, layout.settings);
      await _known(previous, null, request);
      return _page(previous, previous.starts.last, request);
    }
    await _known(layout, page.start, request);
    return _page(layout, layout.trueStart(page.start, before: true)!, request);
  }

  /// The true page that holds [start] if the main run passed it, else the
  /// page that starts at it.
  Future<LaidPage> _resolve(
    _SectionLayout layout,
    PageStart start,
    _Request request,
  ) => _page(
    layout,
    layout.knows(start) ? layout.trueStart(start)! : start,
    request,
  );

  /// The page of [layout] that starts at [start], from the cache or laid
  /// out from that start.
  Future<LaidPage> _page(
    _SectionLayout layout,
    PageStart start,
    _Request request,
  ) async {
    final key = (layout: layout, start: start);
    while (true) {
      await _ready(layout, request);
      if (_pages[key] case final cached?) {
        _touchPage(key);
        return cached.page;
      }
      await _work(request, _PageNeed(layout, start));
    }
  }

  /// Waits until the main run of [layout] passed [through], or reached the
  /// section end when [through] is null.
  Future<void> _known(
    _SectionLayout layout,
    PageStart? through,
    _Request request,
  ) async {
    while (through == null ? !layout.mainDone : !layout.knows(through)) {
      await _ready(layout, request);
      await _work(request, _MainNeed(layout, through));
    }
  }

  /// The page start of the line that holds [place]. In a section that a
  /// kept map seeded, the kept first places find the page that holds it
  /// ([keptLineStart]), and only the pages that it looks at are laid out.
  /// Elsewhere, and once a page contradicts the map, a line search finds
  /// it.
  Future<PageStart> _lineStart(
    _SectionLayout layout,
    EpubPlace place,
    _Request request,
  ) async {
    final prepared = await _ready(layout, request);
    // The read of the kept page map ran beside the prepare, so it has
    // nearly always ended.
    await _reading[layout.settings];
    if (layout.seeded) {
      final line = await keptLineStart(
        prepared.dom,
        layout.starts,
        layout.firsts,
        place,
        (index) async {
          final page = await _page(layout, layout.starts[index], request);
          // A page that contradicted the map forgot it, and the seeded
          // pages with it.
          return layout.seeded ? page : null;
        },
      );
      if (line != null) return line;
    }
    final need = _LineNeed(layout, place);
    while (need.found == null) {
      await _ready(layout, request);
      await _work(request, need);
    }
    return need.found!;
  }

  /// The prepared section of [layout], from the cache or a worker.
  Future<PreparedSection> _ready(
    _SectionLayout layout,
    _Request request,
  ) async {
    request.layout = layout;
    while (true) {
      if (!identical(_layouts[(layout.index, layout.settings)], layout)) {
        _settingsChanged();
      }
      if (layout.prepared case final prepared?) {
        _prepared
          ..remove(layout)
          ..add(layout);
        return prepared;
      }
      await request.wait(also: layout.preparing ??= _prepare(layout));
    }
  }

  /// Asks for one step toward [need], and waits for the next step.
  Future<void> _work(_Request request, _Need need) {
    request.need = need;
    _plan();
    return request.wait();
  }

  Never _settingsChanged() =>
      throw const PageRequestStopped('The page settings changed.');

  // Steps.

  /// Schedules a task for each priority that has work and no task yet. An
  /// idle task does the first work of any rank when it runs.
  void _plan() {
    var urgent = false;
    var idle = false;
    for (final request in _requests) {
      if (request.need case final need? when need.layout.prepared != null) {
        if (request.rank.urgent) {
          urgent = true;
        } else {
          idle = true;
        }
      }
    }
    if (urgent && !_urgentScheduled) {
      _urgentScheduled = true;
      _schedule(() => _run(urgent: true), urgent: true);
    }
    if (idle && !_idleScheduled) {
      _idleScheduled = true;
      _schedule(() => _run(urgent: false), urgent: false);
    }
  }

  /// One task: one step for the first request in the order of work. An
  /// urgent task serves only urgent requests.
  void _run({required bool urgent}) {
    if (urgent) {
      _urgentScheduled = false;
    } else {
      _idleScheduled = false;
    }
    if (_disposed) return;
    _Request? first;
    for (final request in _requests) {
      final need = request.need;
      if (need == null || need.layout.prepared == null) continue;
      if (urgent && !request.rank.urgent) continue;
      if (first == null ||
          request.rank.index < first.rank.index ||
          (request.rank == first.rank && request.order < first.order)) {
        first = request;
      }
    }
    if (first != null) {
      final need = first.need!;
      // The two directions take turns: the request of one goes behind the
      // other's after each step.
      if (first.rank == _Rank.outward) first.order = _order++;
      try {
        _step(need);
      } catch (error, stack) {
        // A run that failed cannot go on.
        need.layout.disposeRuns();
        first.stop(error, stack);
      }
      _trim();
    }
    for (final request in [..._requests]) {
      request.wake();
    }
    _plan();
  }

  void _step(_Need need) {
    final layout = need.layout;
    final prepared = layout.prepared!;
    switch (need) {
      case _LineNeed():
        final search = need.search ??= () {
          _lineSearches++;
          return LineSearch(prepared, need.place);
        }();
        search.step(_stepBudget);
        need.found = search.found;
      case _PageNeed(:final start):
        final run = _runAt(layout, start);
        run.run.step(_stepBudget, want: 1);
        // A start comes from a page or from lineStart, so a run from it
        // cuts its first page there. Otherwise the request never ends.
        assert(
          run.run.pages.isEmpty || run.run.pages.first.start == run.from,
          'A run from ${run.from} cut its first page elsewhere.',
        );
        _take(layout, run);
      case _MainNeed():
        final run = layout.main ??= layout.startMain();
        run.run.step(_stepBudget);
        _take(layout, run);
    }
  }

  /// The run that cuts the page at [start] next: the main run or the
  /// anchored run when one stands there, else a new run. A new run is the
  /// main run when [start] is where the main run goes on, and otherwise it
  /// replaces the anchored run.
  _Run _runAt(_SectionLayout layout, PageStart start) {
    if (layout.main case final main? when main.run.next == start) return main;
    if (layout.anchored case final anchored? when anchored.run.next == start) {
      return anchored;
    }
    if (layout.main == null &&
        !layout.mainDone &&
        start == (layout.starts.lastOrNull ?? const PageStart(0, 0))) {
      return layout.main = layout.startMain();
    }
    layout.anchored?.run.dispose();
    return layout.anchored = _Run(
      LayoutRun(layout.prepared!, from: start),
      start,
      main: false,
    );
  }

  /// Takes the pages that [run] published since the last call: records
  /// their starts, caches those that someone wants, and disposes the rest.
  void _take(_SectionLayout layout, _Run run) {
    final pages = run.run.pages;
    final fresh = pages.sublist(run.taken);
    run.taken = pages.length;
    final ended = layout.mainDone;
    if (run.run.contradicted && layout.measures != null) _contradicted(layout);
    for (final (index, page) in fresh.indexed) {
      final next = page.last
          ? null
          : index + 1 < fresh.length
          ? fresh[index + 1].start
          : run.run.next;
      if (next != null) layout.following[page.start] = next;
      if (layout.seeded && !layout.agrees(page, next)) {
        _forgetMap(layout.settings);
      }
      if (run.main) {
        if (layout.starts.isEmpty ||
            page.start.compareTo(layout.starts.last) > 0) {
          // NOTE: A page counts the visible characters before its first
          // text or image, and the DOM also counts text that no line draws,
          // such as a title that the book's style hides. So the first page
          // of a section can count some, and a page can count more than the
          // next one. The index starts at 0 and never goes back.
          layout.visibleStarts.add(
            layout.starts.isEmpty
                ? 0
                : math.max(page.startVisible, layout.visibleStarts.last),
          );
          layout.firsts.add(page.startPlace);
          layout.starts.add(page.start);
        }
        if (page.last) {
          layout.measures = measuresOf(layout.prepared!);
          _finish(layout, length: layout.prepared!.dom.visibleLength);
        }
      }
    }
    if (!ended && layout.mainDone) {
      if (layout.settings == _settings) {
        _bookPages.value = _bookPagesIn(_settings);
      }
      _keepMap(layout.settings);
    }
    for (final page in fresh) {
      if (!run.main || _wanted(layout, page.start)) {
        _insert(layout, page);
      } else {
        page.dispose();
      }
    }
    if (run.run.done) {
      run.run.dispose();
      if (run.main) layout.main = null;
      if (identical(run, layout.anchored)) layout.anchored = null;
    }
    // At most one anchored run: drop it once the main run passed its start
    // and nothing needs it.
    final anchored = layout.anchored;
    if (anchored != null &&
        layout.knows(anchored.from) &&
        !_pinned.any(
          (key) =>
              identical(key.layout, layout) &&
              key.start.compareTo(anchored.from) >= 0 &&
              key.start.compareTo(anchored.run.next) < 0,
        ) &&
        !_requests.any(
          (request) => switch (request.need) {
            _PageNeed(layout: final at, :final start) =>
              identical(at, layout) && start == anchored.run.next,
            _ => false,
          },
        )) {
      anchored.run.dispose();
      layout.anchored = null;
    }
  }

  /// Marks the main run of [layout] as ended, so that its true page starts
  /// and their visible starts are all known. [length] is the section's
  /// number of visible characters. A section whose pages come from a kept
  /// page map ends here too, and then counts as laid out. The caller
  /// publishes the page index.
  void _finish(_SectionLayout layout, {required int length}) {
    layout.pages = (
      count: layout.starts.length,
      visible: (
        starts: UnmodifiableListView(layout.visibleStarts),
        length: length,
      ),
    );
  }

  /// The page index of [settings]: the true pages of each section whose
  /// main run ended in them.
  BookPages _bookPagesIn(PageSettings? settings) => BookPages([
    for (var index = 0; index < _sectionCount; index++)
      settings == null ? null : _layouts[(index, settings)]?.pages,
  ]);

  /// Whether a request waits for the page of [layout] at [start], or for a
  /// main run that this page lets it know about.
  bool _wanted(_SectionLayout layout, PageStart start) {
    for (final request in _requests) {
      switch (request.need) {
        case _PageNeed(layout: final at, start: final wanted)
            when identical(at, layout) && wanted == start:
          return true;
        case _MainNeed(layout: final at, :final through)
            when identical(at, layout):
          if (through == null) {
            if (layout.mainDone && layout.starts.last == start) return true;
          } else if (layout.knows(through) &&
              (layout.trueStart(through) == start ||
                  layout.trueStart(through, before: true) == start)) {
            return true;
          }
        default:
      }
    }
    return false;
  }

  // Kept page maps.

  /// Starts the read of the kept page map of [settings], unless it started
  /// while [settings] were in use.
  void _readMap(PageSettings settings) {
    final pageMaps = _pageMaps;
    if (pageMaps == null || _reading.containsKey(settings)) return;
    _reading[settings] = pageMaps
        .read(settings)
        .then(
          (sections) => _seed(settings, sections),
          // A map that cannot be read costs layout work only.
          onError: (Object _) {},
        );
  }

  /// Gives each section of [settings] that no run started the true pages
  /// that the kept map [sections] holds for it, so that the section counts
  /// as laid out. A map that does not fit the book is forgotten.
  void _seed(PageSettings settings, List<KeptSection>? sections) {
    if (sections == null || _disposed || !_reading.containsKey(settings)) {
      return;
    }
    if (!_fits(sections)) {
      unawaited(_pageMaps!.forget(settings));
      return;
    }
    var fits = true;
    for (final (index, kept) in sections.indexed) {
      final layout = _layoutFor(index, settings);
      if (layout.main != null ||
          layout.anchored != null ||
          layout.starts.isNotEmpty ||
          layout.following.isNotEmpty) {
        continue;
      }
      layout
        ..starts.addAll(kept.starts)
        ..firsts.addAll(kept.firsts)
        ..visibleStarts.addAll(kept.visible.starts)
        ..seeded = true
        ..measures = kept.measures;
      _finish(layout, length: kept.visible.length);
      if (layout.prepared case final prepared?
          when !reuseMeasures(prepared, kept.measures)) {
        fits = false;
      }
    }
    if (settings == _settings) _bookPages.value = _bookPagesIn(settings);
    if (!fits) _forgetMap(settings);
  }

  /// Whether [sections] can be this book's true pages: one complete
  /// section for each section of the spine, each from the section start,
  /// in increasing order, with visible starts from 0 as the page index
  /// holds them ([BookPages]). The map's format gives each page one first
  /// place and one visible start, and visible starts that never go back
  /// and stay within the section's length.
  bool _fits(List<KeptSection> sections) {
    if (sections.length != _sectionCount) return false;
    for (final section in sections) {
      final starts = section.starts;
      if (!section.complete ||
          starts.isEmpty ||
          starts.first != const PageStart(0, 0) ||
          section.visible.starts.first != 0) {
        return false;
      }
      for (var at = 1; at < starts.length; at++) {
        if (starts[at].compareTo(starts[at - 1]) <= 0) return false;
      }
    }
    return true;
  }

  /// Forgets the kept page map of [settings], which a page contradicted.
  /// Each section that it seeded drops its true pages, as if no run had
  /// reached them. Its file goes, and the whole book is laid out again
  /// from the shown page.
  void _forgetMap(PageSettings settings) {
    for (final layout in _layouts.values) {
      if (layout.settings == settings && layout.seeded) {
        _dropMeasures(layout);
        layout
          ..seeded = false
          ..pages = null
          ..starts.clear()
          ..firsts.clear()
          ..visibleStarts.clear();
      }
    }
    if (settings == _settings) _bookPages.value = _bookPagesIn(settings);
    unawaited(_pageMaps!.forget(settings));
    final shown = _shown?.layout;
    if (shown != null && shown.settings == settings) {
      // The directions passed the seeded sections by. New ones lay them
      // out.
      _generation++;
      _layOutFrom(shown);
    }
    _keptMapDropped.value++;
  }

  /// Handles kept measures of [layout] that do not fit its prepared section,
  /// or that a run found otherwise: they come from a kept page map, which
  /// is then forgotten, or from a main run that the text engine does not
  /// repeat, and then only they go.
  void _contradicted(_SectionLayout layout) {
    if (layout.seeded) {
      _forgetMap(layout.settings);
    } else {
      _dropMeasures(layout);
    }
  }

  /// Lets go of the measures of [layout], and takes them back from its
  /// prepared section, whose runs stop first.
  void _dropMeasures(_SectionLayout layout) {
    layout.measures = null;
    if (layout.prepared case final prepared?) {
      layout.disposeRuns();
      forgetMeasures(prepared);
    }
  }

  /// Keeps the page map of [settings] once every section's main run ended
  /// and no kept map seeded a section, so that no file holds these starts
  /// already.
  void _keepMap(PageSettings settings) {
    final pageMaps = _pageMaps;
    if (pageMaps == null) return;
    final sections = <KeptSection>[];
    for (var index = 0; index < _sectionCount; index++) {
      final layout = _layouts[(index, settings)];
      if (layout == null || !layout.mainDone || layout.seeded) return;
      sections.add(
        KeptSection(
          List.of(layout.starts),
          firsts: List.of(layout.firsts),
          // A copy, because the write encodes it after an await.
          visible: (
            starts: List.of(layout.visibleStarts),
            length: layout.pages!.visible!.length,
          ),
          complete: true,
          measures: layout.measures ?? const SectionMeasures(),
        ),
      );
    }
    unawaited(pageMaps.write(settings, sections));
  }

  /// Whether [page] shows the line that starts at [line].
  static bool _holds(LaidPage page, PageStart line) =>
      page.start == line ||
      (page.start.compareTo(line) < 0 &&
          line.compareTo(page.slices.lastOrNull?.at ?? page.start) <= 0);

  // Caches.

  _SectionLayout _layoutFor(int index, PageSettings settings) {
    if (_disposed) throw StateError('The page source is disposed.');
    RangeError.checkValidIndex(index, _publication.spine, 'section');
    return _layouts.putIfAbsent((
      index,
      settings,
    ), () => _SectionLayout(index, settings));
  }

  /// The layout that [page] belongs to, or null when its settings were
  /// dropped.
  _SectionLayout? _layoutOf(LaidPage page) =>
      _layouts[(page.section, page.settings)];

  _CachedPage _cachedOf(LaidPage page) {
    final layout = _layoutOf(page);
    final cached = layout == null
        ? null
        : _pages[(layout: layout, start: page.start)];
    if (cached == null || !identical(cached.page, page)) {
      throw ArgumentError.value(page, 'page', 'is not in the page cache');
    }
    return cached;
  }

  void _insert(_SectionLayout layout, LaidPage page) {
    assert(layout.prepared != null, 'A page of an unprepared section.');
    final key = (layout: layout, start: page.start);
    if (_pages.containsKey(key)) {
      // The cached page is the same page.
      page.dispose();
      return;
    }
    _pages[key] = _CachedPage(layout, page);
  }

  void _touchPage(_PageKey key) {
    final cached = _pages.remove(key);
    if (cached != null) _pages[key] = cached;
  }

  /// Prepares the section of [layout] in a worker call of its own,
  /// registers its fonts, and caches it. No section waits for another
  /// section's prepare.
  Future<PreparedSection> _prepare(_SectionLayout layout) async {
    try {
      final path = _publication.spine[layout.index];
      final prepared = await _prepareInWorker(
        layout.index,
        path,
        _publication.resources[path]!,
        _publication.bookStyles,
        _publication.imageSizes,
        _publication.language,
        _fontPrefix,
        _publication.mainTextSize,
        layout.settings,
      );
      if (prepared.fonts.isNotEmpty) {
        await BookFonts.load(
          prepared.fonts,
          (path) => _publication.resources[path],
          _fontPrefix,
        );
      }
      if (!_disposed &&
          identical(_layouts[(layout.index, layout.settings)], layout)) {
        layout.prepared = prepared;
        _prepared.add(layout);
        if (layout.measures case final measures?
            when !reuseMeasures(prepared, measures)) {
          _contradicted(layout);
        }
        _trim();
        _plan();
      }
      return prepared;
    } finally {
      layout.preparing = null;
    }
  }

  /// The size in pixels of the book's main text as pages of [settings]
  /// show it (see [shownMainTextSize]), measured in a worker on the
  /// sections that the book's main text size was measured on.
  Future<double> shownMainText(PageSettings settings) {
    if (settings.sizesMainText) return Future.value(settings.fontSize);
    final spine = _publication.spine;
    final samples = mainTextSamples([
      for (final path in spine) _publication.resources[path]!.length,
    ]);
    return _measureInWorker(
      samples,
      [for (final index in samples) spine[index]],
      [for (final index in samples) _publication.resources[spine[index]]!],
      _publication.bookStyles,
      _fontPrefix,
      settings,
    );
  }

  /// Measures the shown main text size of the sections in a worker isolate.
  /// It is static, so that the worker's closure holds only its arguments. A
  /// section that is not UTF-8 still counts what it can, so that the
  /// measurement never fails: preparing that section reports it.
  static Future<double> _measureInWorker(
    List<int> indices,
    List<String> paths,
    List<Uint8List> xhtml,
    Map<String, String> styleSheets,
    String fontPrefix,
    PageSettings settings,
  ) => Isolate.run(
    () => shownMainTextSize([
      for (var at = 0; at < indices.length; at++)
        SectionSource(
          index: indices[at],
          path: paths[at],
          xhtml: utf8.decode(xhtml[at], allowMalformed: true),
          fontPrefix: fontPrefix,
          styleSheets: styleSheets,
        ),
    ], settings),
  );

  /// Prepares one section in a worker isolate, whose exit hands the result
  /// over without a copy. It is static, so that the worker's closure holds
  /// only its arguments.
  static Future<PreparedSection> _prepareInWorker(
    int index,
    String path,
    Uint8List xhtml,
    Map<String, String> styleSheets,
    Map<String, (int, int)> imageSizes,
    String? language,
    String fontPrefix,
    double mainTextSize,
    PageSettings settings,
  ) => Isolate.run(
    () => prepareSections([
      SectionSource(
        index: index,
        path: path,
        xhtml: utf8.decode(xhtml),
        fontPrefix: fontPrefix,
        styleSheets: styleSheets,
        imageSizes: imageSizes,
        language: language,
        mainTextSize: mainTextSize,
      ),
    ], settings).single,
  );

  /// Drops [layout]: the settings that it belongs to are gone.
  void _drop(_SectionLayout layout) {
    _unprepare(layout);
    _layouts.remove((layout.index, layout.settings));
    for (final request in [..._requests]) {
      if (identical(request.layout, layout)) {
        request.stop(const PageRequestStopped('The page settings changed.'));
      }
    }
  }

  /// Lets go of [layout]'s prepared section, its runs and its pages. Its
  /// page starts stay.
  void _unprepare(_SectionLayout layout) {
    layout.disposeRuns();
    layout.prepared = null;
    _prepared.remove(layout);
    _pages.removeWhere((key, cached) {
      if (!identical(key.layout, layout)) return false;
      assert(!_pinned.contains(key), 'A pinned page left the cache.');
      cached.dispose();
      return true;
    });
  }

  /// The layouts that the cache must keep: those of the shown and pinned
  /// pages, and those that requests work in.
  Set<_SectionLayout> _keptLayouts() => Set.identity()
    ..addAll([for (final key in _pinned) key.layout])
    ..addAll([for (final request in _requests) ?request.layout]);

  bool _preparedWithin() {
    var characters = 0;
    for (final layout in _prepared) {
      characters += layout.prepared!.dom.visibleLength;
    }
    return _prepared.length <= _maxPrepared &&
        characters <= _maxPreparedCharacters;
  }

  /// Evicts the least recently used entries of each cache over its limit,
  /// except those that it must keep.
  void _trim() {
    final kept = _keptLayouts();
    while (!_preparedWithin()) {
      final oldest = _prepared.where((layout) => !kept.contains(layout));
      if (oldest.isEmpty) break;
      _unprepare(oldest.first);
    }
    while (_pages.length > _maxPages) {
      final oldest = _pages.keys.where((key) => !_pinned.contains(key));
      if (oldest.isEmpty) break;
      _pages.remove(oldest.first)!.dispose();
    }
    final shownImages = _shownImages();
    while (_imageBytes > _maxImageBytes) {
      final oldest = _images.keys.where(
        (key) => !shownImages.contains(key) && !_drawing.containsKey(key),
      );
      if (oldest.isEmpty) break;
      final image = _images.remove(oldest.first)!;
      _imageBytes -= _bytesOf(image);
      image.dispose();
    }
  }

  // Images.

  Set<_ImageKey> _shownImages() => _pages[_shown]?.images ?? const {};

  /// The images that [page] draws, by path, decoded at [scale].
  Map<String, _ImageKey> _imagesOf(LaidPage page, double scale) {
    final wanted = <String, _ImageKey>{};
    void add(String path, ui.Rect rect) => wanted[path] = (
      path: path,
      width: (rect.width * scale).ceil().clamp(1, 4096),
    );
    for (final piece in page.pieces) {
      for (final (box, held) in piece.inlines) {
        if (held is DrawnImage) add(held.path, box);
      }
    }
    for (final decoration in page.decorations) {
      if (decoration is ImageDecoration) add(decoration.path, decoration.rect);
    }
    return wanted;
  }

  /// The image of [key], decoded at its width. Null when it cannot decode;
  /// the page then draws its alt text.
  Future<ui.Image?> _decode(_ImageKey key) async {
    if (_images.remove(key) case final image?) {
      _images[key] = image;
      return image;
    }
    if (_broken.contains(key)) return null;
    return _decoding[key] ??= () async {
      try {
        final bytes = _publication.resources[key.path];
        if (bytes == null) throw StateError('The image is missing.');
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: key.width,
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        if (_disposed) {
          image.dispose();
          return null;
        }
        _images[key] = image;
        _imageBytes += _bytesOf(image);
        return image;
      } catch (_) {
        _broken.add(key);
        return null;
      } finally {
        _decoding.remove(key);
      }
    }();
  }

  static int _bytesOf(ui.Image image) => image.width * image.height * 4;
}

/// The order of work, from the shown place outward. A lower rank goes
/// first.
enum _Rank {
  /// A caller's urgent request: the shown page, a turn, or a deck page
  /// during a drag.
  asked,

  /// The shown page's next and previous pages.
  neighbor,

  /// A caller's request that is not urgent.
  waiting,

  /// The shown section's main run.
  shownRun,

  /// The next section's first page.
  nextStart,

  /// The main runs of the sections after and before the shown one, in two
  /// directions that take turns.
  outward;

  /// Whether its steps run while an animation runs.
  bool get urgent => index <= neighbor.index;
}

/// A request in progress, and the step that it waits for.
class _Request {
  _Request(this.rank, this.order);
  final _Rank rank;

  /// Earlier requests of one rank go first.
  int order;

  /// The step that the request waits for, or null when it waits for none.
  _Need? need;

  /// The layout that the request works in. The cache keeps its prepared
  /// section.
  _SectionLayout? layout;

  Completer<void>? _wake;
  (Object, StackTrace?)? _stopped;

  /// Waits until the next step ends, or [also] completes. Throws once the
  /// request is stopped.
  Future<void> wait({Future<void>? also}) {
    if (_stopped case (final error, final stack)) {
      return Future.error(error, stack);
    }
    final wake = _wake = Completer<void>();
    return also == null ? wake.future : Future.any([wake.future, also]);
  }

  /// Ends the wait after a step. The request asks again for what it still
  /// needs.
  void wake() {
    need = null;
    final wake = _wake;
    _wake = null;
    wake?.complete();
  }

  /// Ends the wait, and every later one, with [error].
  void stop(Object error, [StackTrace? stack]) {
    _stopped ??= (error, stack);
    need = null;
    final wake = _wake;
    _wake = null;
    wake?.completeError(error, stack);
  }
}

/// One step that a request waits for.
sealed class _Need {
  _Need(this.layout);
  final _SectionLayout layout;
}

/// The page start of the line that holds [place].
class _LineNeed extends _Need {
  _LineNeed(super.layout, this.place);
  final EpubPlace place;

  /// The search, which goes on over steps while it measures a table.
  LineSearch? search;
  PageStart? found;
}

/// The page that starts at [start].
class _PageNeed extends _Need {
  _PageNeed(super.layout, this.start);
  final PageStart start;
}

/// The main run past [through], or to the section end when it is null.
class _MainNeed extends _Need {
  _MainNeed(super.layout, this.through);
  final PageStart? through;
}

/// A layout run and the pages that the source took from it.
class _Run {
  _Run(this.run, this.from, {required this.main});
  final LayoutRun run;

  /// The start that the run started from.
  final PageStart from;

  /// Whether this is the section's main run, whose pages are true pages.
  final bool main;

  /// The number of its published pages that the source took.
  int taken = 0;
}

/// One section laid out for one page settings value: its prepared section,
/// its runs and what they found.
class _SectionLayout {
  _SectionLayout(this.index, this.settings);
  final int index;
  final PageSettings settings;

  /// The prepared section while the cache holds it, and its preparation in
  /// progress.
  PreparedSection? prepared;
  Future<PreparedSection>? preparing;

  /// The main run in progress. A main run that the cache stopped goes on
  /// from the last true page start.
  _Run? main;

  /// The run from a page start that the main run did not reach.
  _Run? anchored;

  /// The true page starts that the main run reached, in order, the first
  /// place of each of their pages ([LaidPage.startPlace]), and the number
  /// of the section's visible characters before each of them.
  final starts = <PageStart>[];
  final firsts = <EpubPlace?>[];
  final visibleStarts = <int>[];

  /// The section's true pages for the page index, once the main run ended
  /// or a kept page map seeded the section.
  PartPages? pages;

  /// Whether the main run ended, so that every true page start is known.
  bool get mainDone => pages != null;

  /// Whether the true pages came from a kept page map that no page
  /// contradicted yet. Then [mainDone] holds and no main run ran.
  bool seeded = false;

  /// What runs of the section measured that a run from a start inside a
  /// flow item needs first: the main run's once it ended, or the kept page
  /// map's. Each prepared section of it reuses them ([reuseMeasures]).
  SectionMeasures? measures;

  /// The start of the page after each page that a run cut, by the page's
  /// start. The section's last page has none.
  final following = <PageStart, PageStart>{};

  /// A main run from the last true page start, or from the section start.
  _Run startMain() {
    final from = starts.lastOrNull;
    return _Run(
      LayoutRun(prepared!, from: from),
      from ?? const PageStart(0, 0),
      main: true,
    );
  }

  /// Whether the main run passed [start], so that the true page that holds
  /// it is known.
  bool knows(PageStart start) =>
      mainDone || (starts.isNotEmpty && starts.last.compareTo(start) >= 0);

  bool isTrueStart(PageStart start) => _search(start).$2;

  /// Whether [page] agrees with the true pages, when the main run ended:
  /// the page that starts at a true page start has that page's first
  /// place, and is followed by the next true page start, or is the last
  /// page when [next] is null. A page from another start has no opinion.
  bool agrees(LaidPage page, PageStart? next) {
    final (at, exact) = _search(page.start);
    if (!exact) return true;
    return firsts[at] == page.startPlace &&
        next == (at + 1 < starts.length ? starts[at + 1] : null);
  }

  /// The last true page start at or before [start], or before it when
  /// [before]; null when none.
  PageStart? trueStart(PageStart start, {bool before = false}) {
    final (at, exact) = _search(start);
    final index = exact && before ? at - 1 : at;
    return index >= 0 ? starts[index] : null;
  }

  /// The index of the last start at or before [start], and whether it
  /// equals [start].
  (int, bool) _search(PageStart start) {
    var low = 0;
    var high = starts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (starts[middle].compareTo(start) <= 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final at = low - 1;
    return (at, at >= 0 && starts[at] == start);
  }

  void disposeRuns() {
    main?.run.dispose();
    anchored?.run.dispose();
    main = null;
    anchored = null;
  }
}

typedef _PageKey = ({_SectionLayout layout, PageStart start});
typedef _ImageKey = ({String path, int width});

/// A cached page and the pictures of it that the source drew.
class _CachedPage {
  _CachedPage(this.layout, this.page);
  final _SectionLayout layout;
  final LaidPage page;
  ui.Picture? draft;

  /// The picture with every image decoded, by scale. A page without images
  /// has one picture, at scale 0.
  final pictures = <double, ui.Picture>{};

  /// The images that its pictures draw.
  final images = <_ImageKey>{};
  bool disposed = false;

  ui.Picture plain() => pictures[0.0] ??= drawPage(page, const {});

  void dispose() {
    page.dispose();
    draft?.dispose();
    for (final picture in pictures.values) {
      picture.dispose();
    }
    disposed = true;
  }
}
