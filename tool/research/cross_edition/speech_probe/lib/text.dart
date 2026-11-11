// Tool code for the boo-snng speech prototype, not part of Bookfin.
// The book's words and the heard words, in one normalized form.
import 'dart:math' as math;
import 'dart:typed_data';

const _units = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = [
  'zero', 'ten', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', //
  'eighty', 'ninety',
];

/// The cardinal words of [n] below a million, without "and".
List<String> numberWords(int n) {
  if (n < 20) return [_units[n]];
  if (n < 100) return [_tens[n ~/ 10], if (n % 10 > 0) _units[n % 10]];
  if (n < 1000) {
    return [_units[n ~/ 100], 'hundred', if (n % 100 > 0) ...numberWords(n % 100)];
  }
  return [
    ...numberWords(n ~/ 1000),
    'thousand',
    if (n % 1000 > 0) ...numberWords(n % 1000),
  ];
}

final _dashes = RegExp('[—–…]');
final _space = RegExp(r'\s+');
final _notWord = RegExp('[^a-z0-9]');
final _number = RegExp(r'^\d{1,6}$');

/// The search words of [raw], a piece of book text or of a transcript:
/// lower case, dashes and ellipses as spaces, every other character but a
/// to z and 0 to 9 left out, and numbers below a million as words.
/// speech_book.py applies the same rules to the book.
List<String> normalizeWords(String raw) {
  final out = <String>[];
  for (final part in raw.toLowerCase().replaceAll(_dashes, ' ').split(_space)) {
    final word = part.replaceAll(_notWord, '');
    if (word.isEmpty) continue;
    if (_number.hasMatch(word)) {
      out.addAll(numberWords(int.parse(word)));
    } else {
      out.add(word);
    }
  }
  return out;
}

/// The words of an ebook as speech_book.py wrote them: each normalized
/// word, the visible characters before it, and the number of its sentence.
class BookText {
  BookText.fromJson(Map<String, dynamic> json)
    : words = List<String>.from(json['words'] as List),
      offsets = Int32List.fromList(List<int>.from(json['offsets'] as List)),
      sentences = Int32List.fromList(List<int>.from(json['sentences'] as List)),
      characters = json['characters'] as int,
      backMatter = _backMatter(json);

  /// Where the back matter starts in visible characters: the first contents
  /// entry in the second half of the book that names endnotes, a colophon
  /// or a license. A narrator does not read it, and endnotes can quote the
  /// body word for word.
  static int _backMatter(Map<String, dynamic> json) {
    final characters = json['characters'] as int;
    for (final entry in (json['entries'] as List? ?? const [])) {
      final start = entry['start'] as int;
      if (start > characters / 2 &&
          RegExp(r'^(end ?notes|notes|colophon|uncopyright|.*license)$', caseSensitive: false)
              .hasMatch((entry['title'] as String).trim())) {
        return start;
      }
    }
    return characters;
  }

  /// Where the back matter starts, in visible characters.
  final int backMatter;

  /// The first word of the back matter, or the word count: the end of the
  /// words that a search reads.
  late final int bodyEnd = backMatter >= characters ? words.length : wordAt(backMatter.toDouble());

  final List<String> words;
  final Int32List offsets;
  final Int32List sentences;

  /// The visible characters of the whole book.
  final int characters;

  /// Where each word occurs, in increasing order.
  late final Map<String, Int32List> positions = () {
    final lists = <String, List<int>>{};
    for (var i = 0; i < words.length; i++) {
      (lists[words[i]] ??= []).add(i);
    }
    return {
      for (final MapEntry(:key, :value) in lists.entries)
        key: Int32List.fromList(value),
    };
  }();

  /// The weight of a word in a vote: rare words count more.
  double weight(String word) =>
      math.log(words.length / (positions[word]?.length ?? 1));

  /// The first word at or after [characters] from the book's start.
  int wordAt(double characters) {
    var lo = 0, hi = offsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] < characters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return math.min(lo, words.length - 1);
  }
}

/// The words of a transcribed window: each normalized word with the start
/// of its first token, in milliseconds from the window's start.
class Heard {
  Heard(this.words, this.ms);

  /// The words of whisper's token lines, `<start ms>\t<text>`. A token that
  /// starts with a space starts a word.
  factory Heard.fromTokens(String lines) {
    final words = <String>[], ms = <int>[];
    var pending = '';
    var start = 0;
    void flush() {
      for (final word in normalizeWords(pending)) {
        words.add(word);
        ms.add(start);
      }
    }

    for (final line in lines.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final text = line.substring(tab + 1);
      if (text.startsWith('[_') || text.startsWith('<|')) continue;
      if (text.startsWith(' ') || pending.isEmpty) {
        flush();
        pending = text;
        start = int.parse(line.substring(0, tab));
      } else {
        pending += text;
      }
    }
    flush();
    return Heard(words, ms);
  }

  final List<String> words;
  final List<int> ms;
}
