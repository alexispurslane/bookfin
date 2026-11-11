// The alignment of an audio edition with an ebook edition by matched
// chapters: design A of docs/plans/cross-edition-places.md. It is a pure
// function of the two outlines, so it runs in a worker isolate.
//
// The steps, in order:
//
// 1. Titles. Each audio chapter title and contents entry title gives a
//    chapter number and its content words (readTitle).
// 2. Pairing. A dynamic program finds the monotone pairing with the most
//    title agreement. A tie goes to the pair whose time share and character
//    share differ least.
// 3. Rate check. While a span reads at less than half or more than twice
//    the median rate, the anchor whose removal helps most goes.
// 4. Ordinal fill. In a gap between anchors with as many audio chapters as
//    contents entries at the anchors' depth, the fill pairs them in order.
//    The rate check runs again over the filled anchors.
// 5. Placement. Inside a span, a place lands at the same share of the
//    other edition's side of the span.
// 6. Refusal: no chapters, fewer than two anchors, or anchors that cover
//    less than half of the recording.
//
// tool/research/cross_edition/measure.py is the prototype that the design
// measured. This port differs in two ways. The rate check also runs after
// the fill, so that every span of the result reads in the band. And among
// removals that bring every span into the band, it takes the one whose
// spans then read closest to the median rate: a single bad span is often
// fixed by removing either of its two anchors, and the prototype took the
// first, which can keep a misplaced chapter mark and drop a good one.
import 'dart:math' as math;
import 'dart:typed_data';

import '../playback/audio_outline.dart';
import '../reader/text_outline.dart';

/// What a chapter title says: the chapters that it names, as the first and
/// the last chapter number of a range, or null when it names no number,
/// and its content words.
typedef ChapterTitle = ({(int, int)? number, Set<String> words});

/// The chapter number and the content words of [title].
///
/// The number is the one after a chapter word ("chapter", "stave",
/// "letter", "adventure") when the title has one, so that "Chapter 1,
/// Part 2" is chapter 1. Otherwise it is the last number, so that "Volume
/// 2, Chapter 3" is 3 and "Book 1, Part 4" is 4. Digits, Roman numerals
/// after a label word or at the start, and number words after a label word
/// count. "1-3", "1 to 3", "1 & 2" and "1 and 2" are ranges. Content words
/// are the other words of two letters or more, in lowercase, without stop
/// words.
ChapterTitle readTitle(String title) {
  final text = title
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAllMapped(_dashRange, (match) => '${match[1]}~${match[2]}')
      .replaceAllMapped(_wordRange, (match) => '${match[1]}~${match[2]}');
  final tokens = [
    for (final match in _token.allMatches(text)) _trimQuotes(match[0]!),
  ];
  final numbers = <(int, int)>[];
  final words = <String>{};
  var afterLabel = false;
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (_labels.contains(token)) {
      afterLabel = true;
      continue;
    }
    if (_range.firstMatch(token) case final range?) {
      numbers.add((int.parse(range[1]!), int.parse(range[2]!)));
    } else if (_digits.hasMatch(token)) {
      final number = int.parse(token);
      numbers.add((number, number));
    } else if (_roman.hasMatch(token) &&
        (afterLabel || index == 0 && !(token == 'i' && tokens.length > 1))) {
      final number = _romanValue(token);
      numbers.add((number, number));
    } else if (afterLabel && _numberWord(token) != null) {
      var number = _numberWord(token)!;
      if (_tens.containsKey(token) &&
          index + 1 < tokens.length &&
          _units.contains(tokens[index + 1])) {
        number += _units.indexOf(tokens[++index]);
      }
      numbers.add((number, number));
    } else {
      afterLabel = false;
      if (!_stop.contains(token) && token.length > 1) words.add(token);
      continue;
    }
    afterLabel = false;
  }
  if (numbers.isEmpty) return (number: null, words: words);
  // The number after a chapter word wins over the last number.
  final labeled = _chapterNumber.firstMatch(text);
  final number = switch (labeled?[2]) {
    null => numbers.last,
    final token when _range.hasMatch(token) => () {
      final range = _range.firstMatch(token)!;
      return (int.parse(range[1]!), int.parse(range[2]!));
    }(),
    final token when _digits.hasMatch(token) => (
      int.parse(token),
      int.parse(token),
    ),
    final token when _roman.hasMatch(token) => (
      _romanValue(token),
      _romanValue(token),
    ),
    _ => numbers.last,
  };
  return (number: number, words: words);
}

final _dashRange = RegExp(r'(\d)\s*[-–—]\s*(\d)');
final _wordRange = RegExp(r'\b(\d+)\s*(?:&|and|to)\s*(\d+)\b');
final _token = RegExp(r"[\p{L}\p{N}~']+", unicode: true);
final _range = RegExp(r'^(\d+)~(\d+)');
final _digits = RegExp(r'^\d+$');
final _roman = RegExp(
  r'^(?=[mdclxvi]+$)m{0,4}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$',
);
final _chapterNumber = RegExp(
  r'\b(chapters?|chap|ch|staves?|letters?|adventure)\b\.?\s*([0-9~]+|[ivxlcdm]+\b)',
);

String _trimQuotes(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && token[start] == "'") {
    start++;
  }
  while (end > start && token[end - 1] == "'") {
    end--;
  }
  return token.substring(start, end);
}

int _romanValue(String numeral) {
  const values = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100, 'd': 500};
  var total = 0;
  for (var index = 0; index < numeral.length; index++) {
    final value = values[numeral[index]] ?? 1000;
    final next = index + 1 < numeral.length
        ? values[numeral[index + 1]] ?? 1000
        : 0;
    total += next > value ? -value : value;
  }
  return total;
}

int? _numberWord(String word) =>
    _ordinals[word] ??
    _tens[word] ??
    (_units.contains(word) ? _units.indexOf(word) : null);

const _labels = {
  'chapter', 'chapters', 'chap', 'ch', 'letter', 'letters', 'stave', //
  'staves', 'book', 'part', 'parts', 'volume', 'vol', 'section', //
  'sections', 'adventure', 'canto', 'no', 'number',
};
const _stop = {
  'the', 'a', 'an', 'of', 'and', 'in', 'to', 'on', 'at', 'for', 'with', //
  'from', 'by', 'or', 'is', 'it', 'his', 'her', 'their', 'its', 'as', //
  'into', 'that', 'which', 'what', 'who',
};
const _units = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', //
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = {
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, //
  'seventy': 70, 'eighty': 80, 'ninety': 90,
};
const _ordinals = {
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, //
  'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10, //
  'eleventh': 11, 'twelfth': 12,
};

/// An audio chapter start and a contents entry start that the matcher
/// pairs: a time in milliseconds from the audio edition's start, and a
/// place in visible characters from the ebook's start.
typedef Anchor = ({int milliseconds, int characters});

/// The audio time and the text between two neighboring anchors, or after
/// the last anchor to the end of its chapter on both sides.
typedef Span = ({Anchor from, Anchor to});

/// Why no landing exists for a place of the other edition.
enum Refusal {
  /// The audio edition has fewer than two chapters, or the ebook lists
  /// fewer than two contents entries.
  noChapters,

  /// Fewer than two audio chapters pair with contents entries, after the
  /// rate check: the chapters of the two editions do not match.
  fewMatches,

  /// The paired chapters cover less than half of the recording, as for an
  /// abridged recording or another edition.
  partCovered,

  /// The recording's length is unknown, so no place has a share of it.
  unmeasured,
}

/// The alignment of an audio edition with an ebook edition: matched
/// chapters, or the reason why none match.
sealed class EditionAlignment {
  const EditionAlignment();
}

/// Chapters of the two editions that pair, as anchors, and the spans
/// between them, which place a time in the text and the reverse.
///
/// Invariants, which [checkInvariants] checks:
/// - There are at least two anchors, and they increase strictly in time
///   and in characters.
/// - The spans join one anchor to the next, in order, and perhaps the last
///   anchor to the end of its chapter.
/// - Every span reads at 0.5 to 2 times the median rate of the spans
///   between anchors.
final class MatchedChapters extends EditionAlignment {
  MatchedChapters._(this.anchors, this.spans, this._rate);

  /// The anchors in order.
  final List<Anchor> anchors;

  /// The spans in order. Each one starts where the one before it ends.
  final List<Span> spans;

  /// The median rate of the spans between anchors, in visible characters
  /// per millisecond.
  final double _rate;

  /// The characters of one page: the median page of the measured corpus at
  /// 412 × 671 px with 20 px text. A place at most one page outside every
  /// span still lands.
  static const pageCharacters = 582;

  /// Where the time [milliseconds] of the audio edition lands in the text,
  /// in visible characters from the ebook's start, or null when it lies
  /// more than one page outside every span.
  double? charactersAt(int milliseconds) => _place(
    milliseconds.toDouble(),
    (anchor) => anchor.milliseconds.toDouble(),
    (anchor) => anchor.characters.toDouble(),
    pageCharacters / _rate,
  );

  /// Where the text place [characters], in visible characters from the
  /// ebook's start, lands in the audio edition, in milliseconds from its
  /// start, or null when it lies more than one page outside every span.
  int? millisecondsAt(double characters) => _place(
    characters,
    (anchor) => anchor.characters.toDouble(),
    (anchor) => anchor.milliseconds.toDouble(),
    pageCharacters.toDouble(),
  )?.round();

  /// [at], on the side of the spans that [from] reads, at the same share of
  /// the span on the side that [to] reads. A place within [margin] on the
  /// [from] side before the first span or after the last lands at the rate
  /// of that span.
  double? _place(
    double at,
    double Function(Anchor) from,
    double Function(Anchor) to,
    double margin,
  ) {
    for (final span in spans) {
      if (at >= from(span.from) && at <= from(span.to)) {
        return to(span.from) +
            (at - from(span.from)) /
                (from(span.to) - from(span.from)) *
                (to(span.to) - to(span.from));
      }
    }
    final (first, last) = (spans.first, spans.last);
    double rate(Span span) =>
        (to(span.to) - to(span.from)) / (from(span.to) - from(span.from));
    if (at < from(first.from) && from(first.from) - at <= margin) {
      return math.max(
        0,
        to(first.from) - (from(first.from) - at) * rate(first),
      );
    }
    if (at > from(last.to) && at - from(last.to) <= margin) {
      return to(last.to) + (at - from(last.to)) * rate(last);
    }
    return null;
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    if (anchors.length < 2) throw StateError('An alignment has two anchors.');
    for (final (before, after) in _neighbors(anchors)) {
      if (after.milliseconds <= before.milliseconds ||
          after.characters <= before.characters) {
        throw StateError('Anchors increase strictly in time and characters.');
      }
    }
    for (final (index, span) in spans.indexed) {
      final joined = index + 1 < anchors.length
          ? span.from == anchors[index] && span.to == anchors[index + 1]
          : index == anchors.length - 1 && span.from == anchors.last;
      if (!joined || !_inBand(_rateOf(span), _rate)) {
        throw StateError(
          'The spans join the anchors in order and read in the rate band.',
        );
      }
    }
  }
}

/// No chapters of the two editions match, for [reason].
final class UnmatchedChapters extends EditionAlignment {
  const UnmatchedChapters(this.reason);
  final Refusal reason;
}

/// Aligns the audio edition of [audio] with the ebook edition of [text] by
/// matched chapters. It runs a dynamic program over every pair of an audio
/// chapter and a contents entry, so run it in a worker isolate.
EditionAlignment alignEditions(AudioOutline audio, TextOutline text) {
  final length = audio.length;
  if (length == null) return const UnmatchedChapters(Refusal.unmeasured);
  final chapters = audio.chapters;
  final entries = text.entries;
  if (chapters.length < 2 ||
      entries.length < 2 ||
      length <= 0 ||
      text.length <= 0) {
    return const UnmatchedChapters(Refusal.noChapters);
  }
  final starts = [for (final chapter in chapters) chapter.editionMilliseconds!];
  Anchor anchorOf((int, int) pair) =>
      (milliseconds: starts[pair.$1], characters: entries[pair.$2].start);

  final titled = _checkRates(
    _pair(chapters, entries, starts, length, text.length),
    anchorOf,
  );
  final pairs = _checkRates(
    [
      ...{...titled, ..._fill(titled, chapters.length, entries)},
    ]..sort((a, b) => a.$1.compareTo(b.$1)),
    anchorOf,
  );
  if (pairs.length < 2) return const UnmatchedChapters(Refusal.fewMatches);

  final anchors = [for (final pair in pairs) anchorOf(pair)];
  final spans = <Span>[
    for (final (before, after) in _neighbors(anchors))
      (from: before, to: after),
  ];
  final rate = _median([for (final span in spans) _rateOf(span)]);
  // The last anchor's chapter, to the next audio chapter and to the next
  // contents entry at its depth or above.
  final (lastChapter, lastEntry) = pairs.last;
  final closing = (
    from: anchors.last,
    to: (
      milliseconds: lastChapter + 1 < starts.length
          ? starts[lastChapter + 1]
          : length,
      characters:
          entries
              .skip(lastEntry + 1)
              .where(
                (entry) =>
                    entry.depth <= entries[lastEntry].depth &&
                    entry.start > entries[lastEntry].start,
              )
              .firstOrNull
              ?.start ??
          text.length,
    ),
  );
  if (closing.to.milliseconds > closing.from.milliseconds &&
      closing.to.characters > closing.from.characters &&
      _inBand(_rateOf(closing), rate)) {
    spans.add(closing);
  }
  final covered = spans.fold(
    0,
    (sum, span) => sum + span.to.milliseconds - span.from.milliseconds,
  );
  if (covered * 2 < length) return const UnmatchedChapters(Refusal.partCovered);
  return MatchedChapters._(
    List.unmodifiable(anchors),
    List.unmodifiable(spans),
    rate,
  );
}

/// The monotone pairs of an audio chapter index and a contents entry index
/// with the most title agreement, in order. Only a pair whose titles score
/// 2 or more counts. A pair loses 1.5 times the difference between the
/// chapter's share of the recording and the entry's share of the book, so
/// a tie goes to the pair whose shares differ least.
List<(int, int)> _pair(
  List<PlaybackChapter> chapters,
  List<OutlineEntry> entries,
  List<int> starts,
  int length,
  int characters,
) {
  final audio = [for (final chapter in chapters) readTitle(chapter.name)];
  final text = [for (final entry in entries) readTitle(entry.title)];
  final (n, m) = (chapters.length, entries.length);
  // best[i][j]: the most agreement of the chapters from i on with the
  // entries from j on. step[i][j]: 0 skips chapter i, 1 skips entry j, 2
  // pairs them.
  final best = [for (var i = 0; i <= n; i++) Float64List(m + 1)];
  final step = [for (var i = 0; i <= n; i++) Uint8List(m + 1)];
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      var value = best[i + 1][j];
      var choice = 0;
      if (best[i][j + 1] > value) {
        value = best[i][j + 1];
        choice = 1;
      }
      final score = _score(audio[i], text[j]);
      if (score >= 2) {
        final drift = (starts[i] / length - entries[j].start / characters)
            .abs();
        final paired = best[i + 1][j + 1] + score - 1.5 * drift;
        if (paired > value) {
          value = paired;
          choice = 2;
        }
      }
      best[i][j] = value;
      step[i][j] = choice;
    }
  }
  final pairs = <(int, int)>[];
  var (i, j) = (0, 0);
  while (i < n && j < m) {
    switch (step[i][j]) {
      case 2:
        pairs.add((i++, j++));
      case 0:
        i++;
      default:
        j++;
    }
  }
  return pairs;
}

/// How well the audio chapter title [audio] agrees with the contents entry
/// title [text]: 2 for the same number, 1 for a number inside the audio
/// title's range, -1 for another number, and 2 or 1 more for many or some
/// shared content words.
double _score(ChapterTitle audio, ChapterTitle text) {
  var score = 0.0;
  if ((audio.number, text.number) case (
    (final low, final high),
    (final number, _),
  )) {
    score += number == low
        ? 2
        : number >= low && number <= high
        ? 1
        : -1;
  }
  if (audio.words.isNotEmpty && text.words.isNotEmpty) {
    final shared = audio.words.intersection(text.words).length;
    final share = shared / audio.words.union(text.words).length;
    score += share >= .5
        ? 2
        : share >= .34
        ? 1
        : 0;
  }
  return score;
}

/// [pairs] without the anchors whose spans read at an implausible rate.
/// While three or more anchors remain and a span reads at less than half
/// or more than twice the median rate, or does not move forward on both
/// sides, the anchor whose removal leaves the least such misreading goes.
/// Among equal removals, the one whose spans read closest to their median
/// goes, then the first.
List<(int, int)> _checkRates(
  List<(int, int)> pairs,
  Anchor Function((int, int)) anchorOf,
) {
  (double, double) misreading(List<(int, int)> pairs) {
    final rates = [
      for (final (before, after) in _neighbors(pairs.map(anchorOf).toList()))
        _rateOf((from: before, to: after)),
    ];
    final positive = [
      for (final rate in rates)
        if (rate > 0) rate,
    ];
    if (positive.isEmpty) return (0, 0);
    final median = _median(positive);
    var outside = 0.0;
    var spread = 0.0;
    for (final rate in rates) {
      final away = rate > 0 ? math.log(rate / median).abs() : 9.0;
      spread += away;
      if (!_inBand(rate, median)) outside += away;
    }
    return (outside, spread);
  }

  var kept = pairs;
  while (kept.length >= 3 && misreading(kept).$1 > 0) {
    List<(int, int)>? best;
    (double, double)? bestMisreading;
    for (var index = 0; index < kept.length; index++) {
      final without = [...kept]..removeAt(index);
      final value = misreading(without);
      if (bestMisreading == null ||
          value.$1 < bestMisreading.$1 ||
          value.$1 == bestMisreading.$1 && value.$2 < bestMisreading.$2) {
        best = without;
        bestMisreading = value;
      }
    }
    kept = best!;
  }
  // Two anchors that do not move forward on both sides make no span.
  if (kept.length == 2 &&
      !(_rateOf((from: anchorOf(kept[0]), to: anchorOf(kept[1]))) > 0)) {
    return const [];
  }
  return kept;
}

/// The pairs that the ordinal fill adds to [titled]: in each gap between
/// two anchors, or before the first or after the last, that holds as many
/// audio chapters as contents entries at the depth of the anchor next to
/// it, the chapters and entries pair in order. Before the first anchor and
/// after the last, the entries count up to the first entry of another
/// depth.
List<(int, int)> _fill(
  List<(int, int)> titled,
  int chapters,
  List<OutlineEntry> entries,
) {
  final filled = <(int, int)>[];
  final bounds = [(-1, -1), ...titled, (chapters, entries.length)];
  for (final ((i0, j0), (i1, j1)) in _neighbors(bounds)) {
    final gap = [for (var i = i0 + 1; i < i1; i++) i];
    if (gap.isEmpty) continue;
    final List<int> matching;
    if (i0 >= 0 && i1 < chapters) {
      final depth = entries[j0].depth;
      matching = [
        for (var j = j0 + 1; j < j1; j++)
          if (entries[j].depth == depth) j,
      ];
    } else if (i0 >= 0) {
      final depth = entries[j0].depth;
      matching = [];
      for (var j = j0 + 1; j < entries.length; j++) {
        if (entries[j].depth != depth) break;
        matching.add(j);
      }
    } else if (i1 < chapters) {
      final depth = entries[j1].depth;
      matching = [];
      for (var j = j1 - 1; j >= 0; j--) {
        if (entries[j].depth != depth) break;
        matching.insert(0, j);
      }
    } else {
      matching = const [];
    }
    if (gap.length == matching.length) {
      for (final (index, chapter) in gap.indexed) {
        filled.add((chapter, matching[index]));
      }
    }
  }
  return filled;
}

/// The rate of [span]: visible characters per millisecond. A span that
/// does not move forward in time reads at 0.
double _rateOf(Span span) {
  final time = span.to.milliseconds - span.from.milliseconds;
  return time > 0 ? (span.to.characters - span.from.characters) / time : 0;
}

/// Whether [rate] lies from half to twice [median].
bool _inBand(double rate, double median) =>
    rate > 0 && rate >= median / 2 && rate <= median * 2;

/// The median of [values], the upper one of an even count.
double _median(List<double> values) =>
    ([...values]..sort())[values.length ~/ 2];

/// Each pair of neighbors of [items], in order.
Iterable<(T, T)> _neighbors<T>(List<T> items) sync* {
  for (var index = 0; index + 1 < items.length; index++) {
    yield (items[index], items[index + 1]);
  }
}
