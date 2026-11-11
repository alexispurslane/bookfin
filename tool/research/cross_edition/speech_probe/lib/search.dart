// Tool code for the boo-snng speech prototype, not part of Bookfin.
// Finds the heard words of a window in a range of the book's words.
import 'dart:math' as math;
import 'dart:typed_data';

import 'text.dart';

/// Where the heard words matched in the book.
class Found {
  Found(this.pairs, this.runnerUp, this.heard);

  /// The matched words in order: (heard index, book word).
  final List<(int, int)> pairs;

  /// The matched words of the best place that starts more than
  /// [separation] book words away from this one.
  final int runnerUp;

  /// The number of heard words.
  final int heard;

  int get matched => pairs.length;

  /// Whether the match is unique and strong enough to land on: at least
  /// [minMatched] words and at least half of the heard words match in
  /// order, and the best other place matches at most [maxRunnerShare] as
  /// many.
  bool confident({int minMatched = 6, double maxRunnerShare = 0.5}) =>
      matched >= minMatched &&
      matched * 2 >= heard &&
      runnerUp <= matched * maxRunnerShare;

  /// The book word of heard word [j]: the matched pair nearest to it,
  /// moved by the heard words between them.
  int bookWordOf(int j) {
    var best = pairs.first;
    for (final pair in pairs) {
      if ((pair.$1 - j).abs() < (best.$1 - j).abs()) best = pair;
    }
    return best.$2 + (j - best.$1);
  }
}

/// Two candidate places closer than this many book words are one place.
const separation = 30;

/// Heard words are voted for in diagonals of this many book words.
const _bucket = 4;

/// The best place of [heard] in the book words [lo] to [hi], or null when
/// no heard word occurs there. Each heard word votes for the diagonals
/// (book word minus heard index) where it occurs, weighted by its rarity.
/// The best diagonals are then aligned word by word, and the one with the
/// most words in order wins.
Found? search(BookText book, List<String> heard, int lo, int hi) {
  if (heard.isEmpty) return null;
  final range = hi - lo;
  final votes = <int, double>{};
  for (var i = 0; i < heard.length; i++) {
    final list = book.positions[heard[i]];
    if (list == null) continue;
    // A word that fills more than 1 in 250 words of the book votes for
    // too many places to help, and costs the most time.
    if (range > 2000 && list.length * 250 > book.words.length) continue;
    final weight = book.weight(heard[i]);
    for (var k = _lowerBound(list, lo); k < list.length && list[k] < hi; k++) {
      final diagonal = (list[k] - i) ~/ _bucket;
      votes[diagonal] = (votes[diagonal] ?? 0) + weight;
    }
  }
  if (votes.isEmpty) return null;
  double score(int d) => votes[d]! + (votes[d + 1] ?? 0);
  final ranked = votes.keys.toList()
    ..sort((a, b) => score(b).compareTo(score(a)));
  final candidates = <int>[];
  for (final d in ranked) {
    if (candidates.length == 8) break;
    if (candidates.every((c) => (c - d).abs() * _bucket > separation)) {
      candidates.add(d);
    }
  }
  List<(int, int)>? best;
  final aligned = <List<(int, int)>>[];
  for (final d in candidates) {
    final from = math.max(lo, d * _bucket - 8);
    final to = math.min(hi, d * _bucket + heard.length + 12);
    if (from >= to) continue;
    final pairs = align(heard, book.words, from, to);
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
  return Found(best, runnerUp, heard.length);
}

int _lowerBound(Int32List list, int value) {
  var lo = 0, hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Two words that a narrator and a book spell differently still match
/// when both are long, differ in length by at most one letter and share
/// their first four letters: "colour" and "color".
bool same(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  return a.startsWith(b.substring(0, 4));
}

/// The longest sequence of [heard] that occurs in order in book words
/// [from] to [to], as (heard index, book word) pairs.
List<(int, int)> align(List<String> heard, List<String> words, int from, int to) {
  final n = heard.length, m = to - from;
  final table = Uint16List((n + 1) * (m + 1));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final at = i * (m + 1) + j;
      table[at] = same(heard[i - 1], words[from + j - 1])
          ? table[at - m - 2] + 1
          : math.max(table[at - m - 1], table[at - 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = n, j = m;
  while (i > 0 && j > 0) {
    final at = i * (m + 1) + j;
    if (same(heard[i - 1], words[from + j - 1]) &&
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
