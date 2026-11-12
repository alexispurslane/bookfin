/// The words of a narrator and of a book, in one normalized form, so that a
/// search can match them (docs/plans/cross-edition-places.md, "Speech
/// search prototype", "Heard words").
library;

const _units = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = [
  'zero', 'ten', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', //
  'eighty', 'ninety',
];

/// The cardinal words of [n], from 0 to below a million, without "and".
List<String> _numberWords(int n) {
  if (n < 20) return [_units[n]];
  if (n < 100) return [_tens[n ~/ 10], if (n % 10 > 0) _units[n % 10]];
  if (n < 1000) {
    return [
      _units[n ~/ 100],
      'hundred',
      if (n % 100 > 0) ..._numberWords(n % 100),
    ];
  }
  return [
    ..._numberWords(n ~/ 1000),
    'thousand',
    if (n % 1000 > 0) ..._numberWords(n % 1000),
  ];
}

final _dashes = RegExp('[—–…]');
final _space = RegExp(r'\s+');
final _notWord = RegExp('[^a-z0-9]');
final _number = RegExp(r'^\d{1,6}$');

/// The search words of [raw], a piece of book text or of a transcript: in
/// lower case, with dashes and ellipses as spaces, every other character
/// but a to z and 0 to 9 left out, and a number below a million as the
/// words that a narrator speaks.
List<String> normalizeWords(String raw) {
  final words = <String>[];
  for (final part in raw.toLowerCase().replaceAll(_dashes, ' ').split(_space)) {
    final word = part.replaceAll(_notWord, '');
    if (word.isEmpty) continue;
    if (_number.hasMatch(word)) {
      words.addAll(_numberWords(int.parse(word)));
    } else {
      words.add(word);
    }
  }
  return words;
}

/// The heard words of one window: each normalized word with the start of
/// its first token, in milliseconds from the window's start.
class Heard {
  const Heard(this.words, this.ms) : assert(words.length == ms.length);

  /// The words of whisper's token lines, `<start ms>\t<text>`, which the
  /// speech library writes. A token that starts with a space starts a word.
  /// Special tokens, such as `[_TT_150]` and `<|endoftext|>`, are left out.
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
      final at = int.tryParse(line.substring(0, tab));
      if (at == null) continue;
      if (text.startsWith(' ') || pending.isEmpty) {
        flush();
        pending = text;
        start = at;
      } else {
        pending += text;
      }
    }
    flush();
    return Heard(List.unmodifiable(words), List.unmodifiable(ms));
  }

  final List<String> words;
  final List<int> ms;
}
