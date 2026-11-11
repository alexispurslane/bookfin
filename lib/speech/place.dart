import 'dart:math' as math;

import 'book_words.dart';
import 'heard_windows.dart';
import 'search.dart';
import 'words.dart';

/// The two directions of a place by speech, as the speech prototype
/// measured them (docs/plans/cross-edition-places.md, "The two
/// directions"): a listening place into the ebook, from a heard window
/// around it, and a reading place into the audiobook, from heard windows
/// that move toward the time when its word is spoken. Each function here
/// is pure, so Crossings runs the searches in the worker of the book's
/// words.

/// The book word of the heard word at [atMs] from the start of [heard]'s
/// window: the words are searched around book word [around] in growing
/// [radii] of pages, and the heard word nearest [atMs] lands on its book
/// word. Null when no confident match exists, because a guess is worse
/// than no landing.
int? landHeard(
  BookWords book,
  Heard heard, {
  required int atMs,
  required int around,
  required List<double> radii,
}) {
  final match = searchAround(book, heard.words, around, radii);
  if (match == null || !match.confident) return null;
  var nearest = 0;
  for (var index = 1; index < heard.ms.length; index++) {
    if ((heard.ms[index] - atMs).abs() < (heard.ms[nearest] - atMs).abs()) {
      nearest = index;
    }
  }
  return match.bookWordOf(nearest);
}

/// The range of narration rates, in milliseconds per word: 1.85 to 3.7
/// words a second. A recording's own rate, its length over the book's
/// words, is clamped to it, because a book can hold more than the
/// recording reads, as a collection of stories does.
const narrationMsPerWord = (min: 270.0, max: 540.0);

/// The longest run of [pairs] whose book words follow their heard words
/// closely, so that a stray match of a common word at either end is left
/// out.
List<(int, int)> densePairs(List<(int, int)> pairs) {
  var best = <(int, int)>[], run = <(int, int)>[];
  for (final pair in pairs) {
    if (run.isNotEmpty && pair.$2 - run.last.$2 > (pair.$1 - run.last.$1) + 4) {
      if (run.length > best.length) best = run;
      run = [];
    }
    run.add(pair);
  }
  return run.length > best.length ? run : best;
}

/// The reading-place loop of the speech prototype, version 4: the time in
/// an audio edition when book word [target] is spoken. It starts at an
/// estimate, hears a window there, finds the window's words in the book,
/// and moves by the words between them and the target at the local
/// narration rate, until a window holds the target. It gives up after
/// [maxRounds] windows.
///
/// The caller runs each round: it hears the window centered on [nextMs],
/// searches its words around [expectedWord] in [radii], and gives the
/// result to [fold].
class ReadingSearch {
  /// [estimateMs] is the first guess of the time, and [msPerWord] the
  /// recording's length over the book's words. [radii] are the radii of the
  /// first search, in pages, which suit the estimate's error.
  ReadingSearch({
    required this.target,
    required int estimateMs,
    required double msPerWord,
    required List<double> radii,
    this.maxRounds = 6,
  }) : _at = estimateMs,
       _prior = msPerWord.clamp(narrationMsPerWord.min, narrationMsPerWord.max),
       _firstRadii = radii {
    _rate = _prior;
  }

  final int target;
  final int maxRounds;
  final double _prior;
  final List<double> _firstRadii;

  /// The time of the next window's middle.
  int _at;

  /// The local narration rate, in milliseconds per word.
  late double _rate;

  /// Each found window: the time and the book word of its middle pair.
  final _found = <(int, int)>[];

  /// Whether the last found window ended within a dozen words of the target.
  var _wasNear = false;
  var _rounds = 0;
  int? _landed;

  /// Whether the loop ended: it landed, or it gave up.
  bool get exhausted => _landed != null || _rounds >= maxRounds;

  /// The time where the next window centers. After the loop gives up, it is
  /// the last estimate.
  int get nextMs => _at;

  /// The radii of the next search: the estimate's, or after a found window,
  /// the near ones.
  List<double> get radii => _found.isEmpty ? _firstRadii : nearRadii;

  /// The book word that a window from [windowStartMs] is expected to start
  /// near: the target in the first round, then the last found window's
  /// word, moved at the local rate.
  int expectedWord(int windowStartMs) {
    if (_found.isEmpty) return target;
    final (ms, word) = _found.last;
    return math.max(0, word + ((windowStartMs - ms) / _rate).round());
  }

  /// Takes the window heard from [windowStartMs], with its [match] in the
  /// book, and gives the landing time when the window holds the target.
  /// Null while the loop goes on, and when it gives up.
  int? fold(int windowStartMs, Heard heard, WordMatch? match) {
    assert(!exhausted, 'The loop ended.');
    _rounds++;
    if (match == null || !match.confident) {
      // Music, credits or a passage that the ebook lacks: step past it.
      _at += HeardWindows.windowMs;
      return null;
    }
    final pairs = densePairs(match.pairs);
    final ms = heard.ms;
    // The target is in the window. Or it is within a dozen words of the
    // matched words for the second time in a row: a heading that the
    // narrator words differently, or the edge of a file.
    final inside = target >= pairs.first.$2 && target <= pairs.last.$2;
    final near = target >= pairs.first.$2 - 12 && target <= pairs.last.$2 + 12;
    if (inside || (near && _wasNear)) {
      var best = pairs.first;
      for (final pair in pairs) {
        if ((pair.$2 - target).abs() < (best.$2 - target).abs()) best = pair;
      }
      return _landed =
          windowStartMs + ms[best.$1] + ((target - best.$2) * _rate).round();
    }
    final (middle, word) = _middlePair(heard, pairs);
    final found = (windowStartMs + ms[middle], word);
    // Two found windows far enough apart give the local rate.
    for (final earlier in _found.reversed) {
      final elapsed = found.$1 - earlier.$1, words = found.$2 - earlier.$2;
      if (elapsed.abs() > 20000 && words != 0) {
        final local = elapsed / words;
        if (local > _prior / 2 && local < _prior * 2) _rate = local;
        break;
      }
    }
    _found.add(found);
    _wasNear = near;
    _at = found.$1 + ((target - found.$2) * _rate).round();
    return null;
  }
}

/// The pair of [pairs] nearest the middle of [heard]'s window, which stands
/// for the window.
(int, int) _middlePair(Heard heard, List<(int, int)> pairs) {
  final ms = heard.ms;
  final middle = ms.isEmpty ? 0 : ms.last ~/ 2;
  var nearest = pairs.first;
  for (final pair in pairs) {
    if ((ms[pair.$1] - middle).abs() < (ms[nearest.$1] - middle).abs()) {
      nearest = pair;
    }
  }
  return nearest;
}

/// The anchors of heard windows: for each window that the book holds, the
/// time of its middle pair, that pair's book word, and the characters
/// before the word. Each window is searched around its [coarse] estimate,
/// in the characters before its place in the book, with the radii of a
/// whole-book estimate. A window without a confident match is left out.
List<Anchor> findAnchors(
  BookWords book,
  List<({int startMs, Heard heard, double coarse})> windows,
) => [
  for (final window in windows)
    if (searchAround(
          book,
          window.heard.words,
          book.wordAt(window.coarse),
          wholeBookRadii,
        )
        case final match? when match.confident)
      if (_middlePair(window.heard, densePairs(match.pairs)) case (
        final heard,
        final word,
      ))
        (
          ms: window.startMs + window.heard.ms[heard],
          word: word,
          characters: book.offsets[word],
        ),
];

/// A found heard window: the time of a heard word in the recording, and
/// the book word that it matched, with the characters before that word.
typedef Anchor = ({int ms, int word, int characters});

/// The longest time between two anchors that place what lies between them:
/// at 10 minutes, the 99th percentile error of the anchor map is under a
/// page (docs/plans/cross-edition-places.md, "The anchor map").
const anchorSpanMs = 600000;

/// The characters before the word spoken at [ms] of the recording, between
/// the two [anchors] around it, or null when no two anchors place it.
double? charactersBetween(List<Anchor> anchors, int ms) {
  if (_around(anchors, ms, (anchor) => anchor.ms) case (final a, final b)) {
    if (a.ms == b.ms) return a.characters.toDouble();
    return a.characters +
        (ms - a.ms) / (b.ms - a.ms) * (b.characters - a.characters);
  }
  return null;
}

/// The time of the recording when the word after [characters] is spoken,
/// between the two [anchors] around it, or null when no two anchors place
/// it.
int? millisecondsBetween(List<Anchor> anchors, double characters) {
  if (_around(anchors, characters, (anchor) => anchor.characters) case (
    final a,
    final b,
  )) {
    if (a.characters == b.characters) return a.ms;
    return (a.ms +
            (characters - a.characters) /
                (b.characters - a.characters) *
                (b.ms - a.ms))
        .round();
  }
  return null;
}

/// The nearest anchor at or before [at] and the nearest at or after it, by
/// [key], when they place what lies between them: one anchor at [at], or
/// two at most [anchorSpanMs] apart that read at a narration rate. Null
/// otherwise.
(Anchor, Anchor)? _around(
  List<Anchor> anchors,
  num at,
  num Function(Anchor anchor) key,
) {
  Anchor? before, after;
  for (final anchor in anchors) {
    final value = key(anchor);
    if (value <= at && (before == null || value > key(before))) {
      before = anchor;
    }
    if (value >= at && (after == null || value < key(after))) after = anchor;
  }
  if (before == null || after == null) return null;
  if (before == after) return (before, after);
  final ms = after.ms - before.ms, words = after.word - before.word;
  if (ms <= 0 || ms > anchorSpanMs || words <= 0) return null;
  final rate = ms / words;
  if (rate < narrationMsPerWord.min || rate > narrationMsPerWord.max) {
    return null;
  }
  return (before, after);
}
