import 'dart:math' as math;
import 'dart:typed_data';

import 'book_words.dart';

/// The search of heard words in a book's words, as the speech prototype
/// measured it (docs/plans/cross-edition-places.md, "The search"): each
/// heard word votes for the diagonals where it occurs, weighted by its
/// rarity, the best diagonals are aligned word by word, and the best
/// alignment wins when it is a confident match. A search near an estimate
/// grows its radius until a place is clear.

/// The visible characters of one page in the design doc: the median page
/// of the corpus books.
const pageCharacters = 582;

/// The radii of a search from the whole-book share, in pages: about its
/// median error, its 90th percentile, three times that, then the book.
const wholeBookRadii = [8.0, 24.0, 72.0, double.infinity];

/// The radii of a search from matched chapters or from a found window:
/// about twice the 90th percentile of matched chapters, then wider.
const nearRadii = [3.0, 24.0, double.infinity];

/// Where heard words matched in a book.
class WordMatch {
  WordMatch(this.pairs, this.runnerUp, this.heard) : assert(pairs.isNotEmpty);

  /// The matched words in order: (heard index, book word).
  final List<(int, int)> pairs;

  /// The matched words of the best place that starts more than
  /// [separation] book words away from this one.
  final int runnerUp;

  /// The number of heard words.
  final int heard;

  int get matched => pairs.length;

  /// Whether the match is unique and strong enough to land on: at least
  /// six words, and at least half of the heard words, match in order, and
  /// the best other place matches at most half as many.
  bool get confident =>
      matched >= 6 && matched * 2 >= heard && runnerUp * 2 <= matched;

  /// The book word of heard word [index]: the matched pair nearest to it,
  /// moved by the heard words between them.
  int bookWordOf(int index) {
    var best = pairs.first;
    for (final pair in pairs) {
      if ((pair.$1 - index).abs() < (best.$1 - index).abs()) best = pair;
    }
    return best.$2 + (index - best.$1);
  }
}

/// Two places that start closer than this many book words are one place.
const separation = 30;

/// Heard words vote for diagonals of this many book words.
const _bucket = 4;

/// Searches [heard] around book word [around], in growing [radii] of
/// pages, and stops at the first confident match. Gives the last match,
/// confident or not, or null when no heard word occurs in the body.
WordMatch? searchAround(
  BookWords book,
  List<String> heard,
  int around,
  List<double> radii,
) {
  final end = book.bodyEnd;
  if (end == 0 || heard.isEmpty) return null;
  final at = book.offsets[around.clamp(0, book.words.length - 1)].toDouble();
  WordMatch? found;
  for (final radius in radii) {
    final low = radius.isInfinite
        ? 0
        : math.min(book.wordAt(at - radius * pageCharacters), end - 1);
    final high = radius.isInfinite
        ? end
        : math.max(
            low + 1,
            math.min(end, book.wordAt(at + radius * pageCharacters)),
          );
    found = search(book, heard, low, high) ?? found;
    if (found != null && found.confident) return found;
  }
  return found;
}

/// The best place of [heard] in the book words [low] to [high], or null
/// when no heard word occurs there.
WordMatch? search(BookWords book, List<String> heard, int low, int high) {
  if (heard.isEmpty || low >= high) return null;
  final range = high - low;
  final votes = <int, double>{};
  for (var index = 0; index < heard.length; index++) {
    final list = book.positions[heard[index]];
    if (list == null) continue;
    // A word that fills more than 1 in 250 words of the book votes for too
    // many places to help, and costs the most time.
    if (range > 2000 && list.length * 250 > book.words.length) continue;
    final weight = book.weight(heard[index]);
    for (
      var at = _lowerBound(list, low);
      at < list.length && list[at] < high;
      at++
    ) {
      final diagonal = (list[at] - index) ~/ _bucket;
      votes[diagonal] = (votes[diagonal] ?? 0) + weight;
    }
  }
  if (votes.isEmpty) return null;
  double score(int diagonal) => votes[diagonal]! + (votes[diagonal + 1] ?? 0);
  final ranked = votes.keys.toList()
    ..sort((a, b) => score(b).compareTo(score(a)));
  final candidates = <int>[];
  for (final diagonal in ranked) {
    if (candidates.length == 8) break;
    if (candidates.every(
      (other) => (other - diagonal).abs() * _bucket > separation,
    )) {
      candidates.add(diagonal);
    }
  }
  List<(int, int)>? best;
  final aligned = <List<(int, int)>>[];
  for (final diagonal in candidates) {
    final from = math.max(low, diagonal * _bucket - 8);
    final to = math.min(high, diagonal * _bucket + heard.length + 12);
    if (from >= to) continue;
    final pairs = _align(heard, book.words, from, to);
    if (pairs.isEmpty) continue;
    aligned.add(pairs);
    if (best == null || pairs.length > best.length) best = pairs;
  }
  if (best == null) return null;
  var runnerUp = 0;
  for (final pairs in aligned) {
    if ((pairs.first.$2 - best.first.$2).abs() > separation) {
      runnerUp = math.max(runnerUp, pairs.length);
    }
  }
  return WordMatch(best, runnerUp, heard.length);
}

int _lowerBound(Int32List list, int value) {
  var low = 0, high = list.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (list[middle] < value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Whether a narrator's word [a] and a book's word [b] match. Two long
/// words that differ in length by at most one letter and share their first
/// four letters still match, as "colour" and "color" do.
bool _same(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  return a.startsWith(b.substring(0, 4));
}

/// The longest sequence of [heard] that occurs in order in the book words
/// [from] to [to], as (heard index, book word) pairs.
List<(int, int)> _align(
  List<String> heard,
  List<String> words,
  int from,
  int to,
) {
  final n = heard.length, m = to - from;
  final table = Uint16List((n + 1) * (m + 1));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final at = i * (m + 1) + j;
      table[at] = _same(heard[i - 1], words[from + j - 1])
          ? table[at - m - 2] + 1
          : math.max(table[at - m - 1], table[at - 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = n, j = m;
  while (i > 0 && j > 0) {
    final at = i * (m + 1) + j;
    if (_same(heard[i - 1], words[from + j - 1]) &&
        table[at] == table[at - m - 2] + 1) {
      pairs.add((i - 1, from + j - 1));
      i--;
      j--;
    } else if (table[at - m - 1] >= table[at - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return pairs.reversed.toList();
}
