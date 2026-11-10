// The background survey of a PDF's pages, for the book crop (tb-lnak). See
// docs/plans/pdf-word-image-reflow.md, "The survey".
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'book_crop.dart';
import 'book_crop.dart' as crops_ show cropOf;
import 'pdf.dart';
import 'survey_files.dart';

/// What a survey does next (see [nextSurveyStep]).
sealed class SurveyStep {
  const SurveyStep();
}

/// Survey source page [page].
final class SurveyPage extends SurveyStep {
  const SurveyPage(this.page);
  final int page;
  @override
  bool operator ==(Object other) => other is SurveyPage && other.page == page;
  @override
  int get hashCode => page.hashCode;
  @override
  String toString() => 'SurveyPage($page)';
}

/// Freeze the book profile from the pages surveyed so far.
final class FreezeProfile extends SurveyStep {
  const FreezeProfile();
  @override
  String toString() => 'FreezeProfile()';
}

/// Nothing is left to do in this session: every page is surveyed, or the
/// rest failed and waits for the next open.
final class SurveyRested extends SurveyStep {
  const SurveyRested();
  @override
  String toString() => 'SurveyRested()';
}

/// The greatest number of body pages of each side in the sample.
const _sampleSize = 32;

/// What the survey of a book of [pageCount] pages does next, when the reader
/// opened it at page [from]. [surveyed] holds each surveyed page and
/// whether it is a body page, and [skipped] the pages that failed in this
/// session. [frozen] says whether the profile froze.
///
/// 1. The page [from], and the next page.
/// 2. Until the profile froze, the sample: for each side, all its pages when
///    it has at most 32, and otherwise 32 pages spread evenly over the book,
///    the sides in turn. A sample page that is no body page, or that failed,
///    gives its place to the next page of its side, up to the next sample
///    page. When each place has a body page, or has no page left, the
///    profile freezes. A place that only failed pages leave empty keeps the
///    profile from freezing in this session.
/// 3. Every other page, from [from] to the end, then from the start.
///
/// It never gives a surveyed or a failed page, so a page runs once.
SurveyStep nextSurveyStep({
  required int pageCount,
  required int from,
  required Map<int, bool> surveyed,
  required Set<int> skipped,
  required bool frozen,
}) {
  bool open(int page) => !surveyed.containsKey(page) && !skipped.contains(page);
  for (final page in [from, from + 1]) {
    if (page >= 1 && page <= pageCount && open(page)) return SurveyPage(page);
  }
  if (!frozen) {
    var short = false;
    final sides = [
      for (final side in [0, 1])
        [for (var page = side == 0 ? 2 : 1; page <= pageCount; page += 2) page],
    ];
    final targets = [for (final pages in sides) _targets(pages.length)];
    for (var k = 0; k < _sampleSize; k++) {
      for (final side in [0, 1]) {
        final pages = sides[side], starts = targets[side];
        if (k >= starts.length) continue;
        final end = k + 1 < starts.length ? starts[k + 1] : pages.length;
        var failed = false, done = false;
        for (var index = starts[k]; index < end && !done; index++) {
          final page = pages[index];
          if (skipped.contains(page)) {
            failed = true;
          } else if (surveyed[page] case final body?) {
            done = body;
          } else {
            return SurveyPage(page);
          }
        }
        if (!done && failed) short = true;
      }
    }
    if (!short) return const FreezeProfile();
  }
  for (var step = 0; step < pageCount; step++) {
    final page = (from - 1 + step) % pageCount + 1;
    if (open(page)) return SurveyPage(page);
  }
  return const SurveyRested();
}

/// The indexes of the sample's pages among the [count] pages of one side:
/// all of them for at most 32 pages, and otherwise 32 spread evenly.
List<int> _targets(int count) => count <= _sampleSize
    ? List.generate(count, (index) => index)
    : List.generate(
        _sampleSize,
        (index) => ((index + 0.5) * count / _sampleSize).floor(),
      );

/// The background survey of one open PDF: it analyzes every page once, at
/// the lowest priority, freezes the book profile from a sample, and gives
/// each surveyed page its crop (see book_crop.dart). [PdfBook] owns it, and
/// a reader starts it with the book's kept survey.
///
/// It keeps its results in [SurveyFiles] in batches, so a later open goes on
/// where it stopped. It runs one page at a time, in the order of
/// [nextSurveyStep]. Each page goes through [PdfBook.reflowPage] as a
/// background request, which waits for the reader's own requests, and whose
/// layout pass on a scanned page waits behind all other recognition work.
/// The layout pass keeps its record, so the word view later opens that page
/// at once. A page that fails is tried again at the next open.
///
/// Invariants, which [checkInvariants] makes sure of: each surveyed page is
/// kept under its number, within the book; no page is both surveyed and
/// failed; once the profile froze, every page crop holds the page's content
/// box, and a page that its side's box holds, or a blank page, has that box
/// as its crop.
class BookSurvey {
  BookSurvey(this._book);
  final PdfBook _book;

  /// The pages surveyed after which the survey writes a batch.
  static const _batch = 8;

  SurveyFiles? _store;

  /// The page that the reader showed when the survey started.
  var _from = 1;

  /// The surveyed pages, by their source page numbers.
  final _pages = <int, SurveyedPage>{};

  /// The pages that failed in this session.
  final _failed = <int>{};
  BookProfile? _profile;
  var _paused = false;
  var _closed = false;

  /// Whether the survey learned something that its store does not keep.
  var _unsaved = 0;
  Future<void>? _restored;
  Future<void>? _loop;
  Future<void> _saving = Future.value();

  /// How many times crops became known. Its listeners are [crops]'s.
  final _crops = ValueNotifier(0);

  /// Notifies when crops become known: when the profile freezes, when a
  /// kept profile is read, and when a page surveyed after the freeze gets
  /// its crop. A crop never changes once it is known.
  Listenable get crops => _crops;

  /// The book profile, once it froze.
  BookProfile? get profile => _profile;

  /// Starts the survey with the kept survey [store], from the page [from]
  /// that the reader shows. A survey starts once.
  void start(SurveyFiles store, {required int from}) {
    if (_store != null || _closed) {
      throw StateError('A book survey starts once, before its book closes.');
    }
    _store = store;
    _from = from.clamp(1, _book.pageCount);
    _restored = _restore(store);
    _wake();
  }

  /// Stops the survey after the page that runs, as while the app is in the
  /// background, and writes what it learned.
  void pause() {
    _paused = true;
    unawaited(_save());
  }

  /// Goes on with the survey after [pause].
  void resume() {
    _paused = false;
    _wake();
  }

  /// Stops the survey for good, as when its book closes. It completes after
  /// the page that runs and the last write.
  Future<void> close() async {
    _closed = true;
    await _loop;
    await _save();
  }

  /// The crop of source page [page], or null until the survey surveyed it
  /// and froze the profile.
  PageBox? cropOf(int page) {
    final profile = _profile, surveyed = _pages[page];
    if (profile == null || surveyed == null) return null;
    return crops_.cropOf(surveyed, profile);
  }

  /// Tells the survey that the reader shows source page [page]. The survey
  /// goes on from it, so that page and the page after it get their analysis
  /// before any other page, after the page that runs. So the next page's
  /// crop is normally known before the person turns.
  void follow(int page) {
    final from = page.clamp(1, _book.pageCount);
    if (from == _from) return;
    _from = from;
    _wake();
  }

  /// The crop of source page [page] as soon as it is known, or null when it
  /// is not known within [limit].
  ///
  /// It is null at once when no crop can come soon: when the survey did not
  /// start, or closed, or when it read its kept survey and has no profile.
  /// A new book's profile freezes only after its whole sample, so a wait
  /// would only delay the page.
  Future<PageBox?> cropWithin(int page, Duration limit) async {
    final known = cropOf(page);
    final restored = _restored;
    if (known != null || restored == null || _closed) return known;
    final answer = Completer<PageBox?>();
    void give(PageBox? crop) {
      if (!answer.isCompleted) answer.complete(crop);
    }

    void whenKnown() {
      if (cropOf(page) case final crop?) give(crop);
    }

    final timer = Timer(limit, () => give(null));
    _crops.addListener(whenKnown);
    unawaited(
      restored.then((_) => _profile == null ? give(null) : whenKnown()),
    );
    try {
      return await answer.future;
    } finally {
      timer.cancel();
      _crops.removeListener(whenKnown);
    }
  }

  Future<void> _restore(SurveyFiles store) async {
    final kept = await store.read();
    if (kept == null || _closed) return;
    for (final page in kept.pages) {
      if (page.sourcePage >= 1 && page.sourcePage <= _book.pageCount) {
        _pages[page.sourcePage] = page;
      }
    }
    _profile = kept.profile;
    if (_profile != null) _crops.value++;
  }

  void _wake() {
    if (_store == null || _paused || _closed || _loop != null) return;
    _loop = _run();
  }

  Future<void> _run() async {
    try {
      await _restored;
      while (!_paused && !_closed) {
        final step = nextSurveyStep(
          pageCount: _book.pageCount,
          from: _from,
          surveyed: {
            for (final MapEntry(:key, :value) in _pages.entries)
              key: value.body,
          },
          skipped: _failed,
          frozen: _profile != null,
        );
        switch (step) {
          case SurveyPage(:final page):
            assert(!_pages.containsKey(page), 'No page is surveyed twice.');
            // A page that finishes after a pause or a close is kept, so
            // that it does not run again.
            final surveyed = await _survey(page);
            if (surveyed == null) {
              _failed.add(page);
              continue;
            }
            _pages[page] = surveyed;
            _unsaved++;
            if (_profile != null) _crops.value++;
            if (_unsaved >= _batch) unawaited(_save());
          case FreezeProfile():
            assert(_profile == null, 'The profile freezes once.');
            _profile = await _book.hop(bookProfile, [..._pages.values]);
            _unsaved++;
            _crops.value++;
            unawaited(_save());
          case SurveyRested():
            return;
        }
      }
    } finally {
      _loop = null;
      unawaited(_save());
    }
  }

  /// What the crop needs of source page [page], or null when it has no
  /// geometry or its analysis failed.
  Future<SurveyedPage?> _survey(int page) async {
    try {
      final reflow = await _book.reflowPage(page, background: true);
      if (reflow == null) return null;
      // Only a text layer gives text at once. A scanned page's text needs
      // recognition, which the survey never asks for.
      return surveyPage(await reflow.templateReading());
    } on Exception {
      return null;
    } on StateError {
      return null; // The book closed.
    }
  }

  /// Writes the survey when it learned something since the last write.
  /// Writes run one after another.
  Future<void> _save() {
    final store = _store;
    if (store == null || _unsaved == 0) return _saving;
    _unsaved = 0;
    final kept = (pages: [..._pages.values], profile: _profile);
    return _saving = _saving.then((_) => store.write(kept));
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs only on demand, from a test or a debug switch.
  void checkInvariants() {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Book survey: $rule.');
    }

    for (final MapEntry(key: number, value: page) in _pages.entries) {
      require(page.sourcePage == number, 'page $number is kept as itself');
      require(
        number >= 1 && number <= _book.pageCount,
        'page $number lies in the book',
      );
      require(!_failed.contains(number), 'page $number did not fail');
      final profile = _profile;
      if (profile == null) continue;
      final crop = crops_.cropOf(page, profile);
      final content = contentOf(page, profile.templates);
      final box = profile.boxes[number % 2];
      require(
        content == null || _holds(crop, content),
        'the crop of page $number holds its content',
      );
      require(
        box == null || content != null && !_holds(box, content) || crop == box,
        'page $number shows its side\'s box when that box holds it',
      );
    }
  }
}

bool _holds(PageBox outer, PageBox inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;
