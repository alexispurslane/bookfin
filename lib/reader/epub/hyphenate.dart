// Automatic hyphenation: where a word may break at the end of a line.
//
// It follows Frank Liang's algorithm ("Word Hy-phen-a-tion by
// Com-put-er", 1983) with the TeX patterns of the hyph-utf8 project
// (hyphenation_en.dart), and the rules of Chromium's hyphenation for the
// words that it breaks. Prepare runs it in a worker isolate, so it uses no
// dart:ui.
import 'dart:typed_data';

import 'hyphenation_en.dart';

/// Liang hyphenation with the TeX patterns and exceptions of one language.
final class Hyphenator {
  Hyphenator._(String patterns, String exceptions) {
    for (final pattern in patterns.split(' ')) {
      _addPattern(pattern);
    }
    for (final word in exceptions.split(' ')) {
      final breaks = <int>[];
      for (var index = 0; index < word.length; index++) {
        if (word.codeUnitAt(index) == 0x2d) breaks.add(index - breaks.length);
      }
      _exceptions[word.replaceAll('-', '')] = breaks;
    }
  }

  static final _american = Hyphenator._(enUsPatterns, enUsExceptions);
  static final _british = Hyphenator._(enGbPatterns, enGbExceptions);

  /// The hyphenator for [language], a BCP 47 language tag such as `en-GB`,
  /// or null when no patterns cover it. British English has its own
  /// patterns, and all other English uses the American ones.
  static Hyphenator? forLanguage(String? language) {
    final tag = language?.toLowerCase();
    if (tag == null) return null;
    if (tag == 'en-gb' || tag.startsWith('en-gb-')) return _british;
    if (tag == 'en' || tag.startsWith('en-')) return _american;
    return null;
  }

  /// The levels of each pattern, by the key of its letters (see [_key]).
  /// The key of each shorter start of a pattern maps to an empty list, so
  /// that a lookup can stop at the first key that no pattern starts with.
  final _patterns = <int, Uint8List>{};
  final _exceptions = <String, List<int>>{};
  static final _start = Uint8List(0);

  /// The most letters of a pattern, the dots at a word's edges included.
  /// 28 to the power of 11 is below 2 to the power of 53, so a key stays
  /// exact in every Dart number.
  static const _longest = 11;

  void _addPattern(String pattern) {
    final levels = <int>[0];
    var key = 0;
    var letters = 0;
    for (final code in pattern.codeUnits) {
      if (code >= 0x30 && code <= 0x39) {
        levels.last = code - 0x30;
      } else {
        if (letters > 0) _patterns.putIfAbsent(key, () => _start);
        key = key * 28 + _code(code);
        letters++;
        levels.add(0);
      }
    }
    if (letters > _longest) {
      throw StateError('The hyphenation pattern $pattern is too long.');
    }
    _patterns[key] = Uint8List.fromList(levels);
  }

  /// The number that stands for [code] in a key: 1 to 26 for the letters a
  /// to z, 27 for the dot at a word's edge.
  static int _code(int code) => code == 0x2e ? 27 : code - 0x60;

  /// The breaks that hyphenation allows in [word]: for each, the number of
  /// code units before it, in increasing order.
  ///
  /// A word breaks only when it holds the ASCII letters a to z alone, as the
  /// TeX patterns know no other characters, and when it has at least five
  /// of them. A break keeps at least two letters before it and three after
  /// it, the TeX limits for English. A word that starts with a capital does
  /// not break, as Chromium does not break one in English.
  List<int> breaks(String word) {
    if (word.length < 5) return const [];
    final first = word.codeUnitAt(0);
    if (first >= 0x41 && first <= 0x5a) return const [];
    final codes = Uint8List(word.length + 2)
      ..first = 27
      ..last = 27;
    for (var index = 0; index < word.length; index++) {
      final code = word.codeUnitAt(index) | 0x20;
      if (code < 0x61 || code > 0x7a) return const [];
      codes[index + 1] = code - 0x60;
    }
    final points = _exceptions[word.toLowerCase()] ?? _liang(codes);
    return [
      for (final at in points)
        if (at >= 2 && at <= word.length - 3) at,
    ];
  }

  /// Liang's algorithm on [codes], a word between its two dots: each
  /// pattern that occurs in the word raises the level between its letters,
  /// and an odd level allows a break.
  List<int> _liang(Uint8List codes) {
    final levels = Uint8List(codes.length + 1);
    for (var start = 0; start < codes.length; start++) {
      var key = 0;
      for (
        var end = start;
        end < codes.length && end - start < _longest;
        end++
      ) {
        key = key * 28 + codes[end];
        final found = _patterns[key];
        if (found == null) break;
        for (var at = 0; at < found.length; at++) {
          if (found[at] > levels[start + at]) levels[start + at] = found[at];
        }
      }
    }
    // The level before code start + 1 is the level between letters start
    // and start + 1 of the word, as codes start with a dot.
    return [
      for (var at = 1; at < codes.length - 2; at++)
        if (levels[at + 1].isOdd) at,
    ];
  }
}

/// The words of [text] that hyphenation can break, as the start and end of
/// each. A word runs between two places where a line can break without
/// hyphenation: spaces, and after a hyphen or a dash. Opening punctuation
/// and quotes before it, and punctuation after it, are not part of it, as
/// in Chromium.
Iterable<(int, int)> hyphenationWords(String text) sync* {
  var index = 0;
  while (index < text.length) {
    while (index < text.length && _isSpace(text.codeUnitAt(index))) {
      index++;
    }
    var end = index;
    while (end < text.length && !_isSpace(text.codeUnitAt(end))) {
      if (_breaksAfter(text.codeUnitAt(end++))) break;
    }
    var start = index;
    var stop = end;
    while (start < stop && _opens(text.codeUnitAt(start))) {
      start++;
    }
    while (stop > start && _isPunctuation(text.codeUnitAt(stop - 1))) {
      stop--;
    }
    if (stop > start) yield (start, stop);
    index = end;
  }
}

/// Whether a line can break at [code], a space.
bool _isSpace(int code) =>
    code == 0x20 ||
    code == 0x09 ||
    code == 0x0a ||
    code == 0x0d ||
    (code >= 0x2000 && code <= 0x200b && code != 0x2007) ||
    code == 0x3000;

/// Whether a line can break after [code]: a hyphen or a dash.
bool _breaksAfter(int code) =>
    code == 0x2d || (code >= 0x2010 && code <= 0x2015 && code != 0x2011);

/// Whether [code] opens a quote or a parenthesis: the line break classes OP
/// and QU of Unicode's line breaking algorithm, in the forms that books
/// use.
bool _opens(int code) => const {
  0x22, 0x27, 0x28, 0x5b, 0x7b, 0xa1, 0xab, 0xbb, 0xbf, //
  0x2018, 0x2019, 0x201a, 0x201b, 0x201c, 0x201d, 0x201e, 0x201f,
  0x2039, 0x203a,
}.contains(code);

/// Whether [code] is punctuation: Unicode general category P, in the
/// ranges that books use.
bool _isPunctuation(int code) =>
    (code >= 0x21 && code <= 0x2f && code != 0x24 && code != 0x2b) ||
    code == 0x3a ||
    code == 0x3b ||
    code == 0x3f ||
    code == 0x40 ||
    (code >= 0x5b && code <= 0x5d) ||
    code == 0x5f ||
    code == 0x7b ||
    code == 0x7d ||
    const {0xa1, 0xa7, 0xab, 0xb6, 0xb7, 0xbb, 0xbf}.contains(code) ||
    (code >= 0x2010 && code <= 0x2027) ||
    (code >= 0x2030 && code <= 0x205e && code != 0x2044 && code != 0x2052);
