import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

import '../reader/epub/publication.dart';
import '../reader/text_outline.dart';
import '../reader/section_text.dart';
import 'words.dart';

/// The normalized words of an ebook edition (see [normalizeWords]), each
/// with the visible characters before it from the book's start, as the
/// book map and the text outline count them. Speech search finds heard
/// words among them, and turns a found word into a place by its characters.
class BookWords {
  BookWords(this.words, this.offsets, {required this.bodyEnd})
    : assert(words.length == offsets.length),
      assert(bodyEnd >= 0 && bodyEnd <= words.length);

  /// The words in reading order.
  final List<String> words;

  /// The visible characters before each word, from the book's start, in
  /// increasing order. The words of one written number share an offset.
  final Int32List offsets;

  /// The first word of the back matter, or the word count when the book
  /// has none. A search reads only the words before it: a narrator does
  /// not read endnotes, a colophon or a license, and endnotes can quote the
  /// body word for word.
  final int bodyEnd;

  /// Where each word occurs, in increasing order.
  late final Map<String, Int32List> positions = () {
    final lists = <String, List<int>>{};
    for (var index = 0; index < words.length; index++) {
      (lists[words[index]] ??= []).add(index);
    }
    return {
      for (final MapEntry(:key, :value) in lists.entries)
        key: Int32List.fromList(value),
    };
  }();

  /// The weight of [word] in a search's vote: a rare word counts more.
  double weight(String word) =>
      math.log(words.length / (positions[word]?.length ?? 1));

  /// The first word that starts at [characters] from the book's start or
  /// after it, or the last word when none does.
  int wordAt(double characters) {
    var low = 0, high = offsets.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (offsets[middle] < characters) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.min(low, words.length - 1);
  }
}

/// The elements whose start or end does not part two words: those that
/// change the look of text inside a line.
const _inline = {
  'a', 'abbr', 'b', 'bdi', 'bdo', 'cite', 'code', 'data', 'dfn', 'em', //
  'font', 'i', 'kbd', 'mark', 'q', 's', 'samp', 'small', 'span', 'strike',
  'strong', 'sub', 'sup', 'time', 'tt', 'u', 'var', 'wbr',
};

/// A dash or an ellipsis: it parts two words, as [normalizeWords] reads it,
/// and is a visible character.
bool _parts(int code) => code == 0x2014 || code == 0x2013 || code == 0x2026;

/// Contents titles that start the back matter, in the book's second half.
final _backMatter = RegExp(
  r'^(end ?notes|notes|colophon|uncopyright|.*license)$',
  caseSensitive: false,
);

/// The words of [publication]: the body text of every section of its
/// spine, in order, using the [outline] that Crossings owns for this file
/// revision to locate back matter. It parses every section once, so run it
/// in a worker isolate.
BookWords bookWordsOf(Publication publication, TextOutline outline) {
  final words = <String>[];
  final offsets = <int>[];
  var visible = 0;
  for (final path in publication.spine) {
    final bytes = publication.textFiles[path];
    if (bytes == null) continue;
    visible = _addSection(bytes, visible, words, offsets);
  }
  var bodyEnd = words.length;
  for (final entry in outline.entries) {
    if (entry.start > outline.length / 2 &&
        _backMatter.hasMatch(entry.title.trim())) {
      bodyEnd = _firstAtOrAfter(offsets, entry.start);
      break;
    }
  }
  return BookWords(
    List.unmodifiable(words),
    Int32List.fromList(offsets),
    bodyEnd: bodyEnd,
  );
}

int _firstAtOrAfter(List<int> offsets, int characters) {
  var low = 0, high = offsets.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (offsets[middle] < characters) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// Adds the words of the section [bytes] to [words] and [offsets], from
/// [visible] characters on, and gives the visible characters after it. It
/// counts the characters that `countSection` of the book map counts: the
/// text of the body without white space. A section that does not parse
/// adds nothing, as it counts nothing there.
int _addSection(
  Uint8List bytes,
  int visible,
  List<String> words,
  List<int> offsets,
) {
  final added = words.length;
  final start = visible;
  final pending = StringBuffer();
  var pendingAt = visible;
  void flush() {
    if (pending.isEmpty) return;
    for (final word in normalizeWords(pending.toString())) {
      words.add(word);
      offsets.add(pendingAt);
    }
    pending.clear();
  }

  void read(String text, int before, bool whitespace) {
    if (whitespace) {
      flush();
      return;
    }
    for (var index = 0; index < text.length; index++) {
      final code = text.codeUnitAt(index);
      if (_parts(code)) {
        flush();
      } else {
        if (pending.isEmpty) pendingAt = start + before + index;
        pending.writeCharCode(code);
      }
    }
  }

  try {
    visible += walkSection(
      bytes,
      onText: read,
      onElement: (event, _) {
        switch (event) {
          case XmlStartElementEvent(:final localName) ||
              XmlEndElementEvent(:final localName):
            if (!_inline.contains(localName)) flush();
          default:
        }
      },
    );
    flush();
  } on Exception {
    words.length = added;
    offsets.length = added;
    return start;
  }
  return visible;
}
