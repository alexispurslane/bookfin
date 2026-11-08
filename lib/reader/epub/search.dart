// Searches an EPUB's spine sections for a phrase, with the rules of the
// WebView reader (reader.js `searchBook` and passive-search.js
// `searchPublicationText`), so that a search finds the same hits, in the
// same order, with the same excerpts and saved locations.
//
// A section's searched text is the text of its body without hidden text,
// lowercased one character at a time, with each run of white space folded
// to one space and a space between two block elements. A hit is each
// occurrence of the folded query in that text, overlapping ones included.
//
// [searchSections] needs no dart:ui, so it runs in a worker isolate.
// [searchBook] sends it batches of sections and joins their hits.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/navigation.dart';

import '../../foundation/hop.dart';
import '../document.dart';
import 'dom.dart';
import 'places.dart';

/// One spine section to search.
class SearchSection {
  const SearchSection({
    required this.index,
    required this.path,
    required this.xhtml,
    required this.spine,
  });

  /// The section's spine index.
  final int index;

  /// The section's path in the publication, as the spine lists it.
  final String path;

  /// The section's admitted XHTML, as UTF-8. The worker decodes it.
  final Uint8List xhtml;

  /// The section's spine step in a CFI, such as `/6/4` (see [spineSteps]).
  final String spine;
}

/// The hits of one section, in document order.
class SectionHits {
  const SectionHits(
    this.index,
    this.hits, {
    this.incomplete = false,
    this.failed = false,
  });

  /// The section's spine index.
  final int index;

  /// Each hit's saved location and its excerpt: the matched book text, at
  /// most 160 characters of it.
  final List<(ReadingLocation, String)> hits;

  /// Whether the section has more than [hitLimit] hits, of which [hits]
  /// holds the first [hitLimit].
  final bool incomplete;

  /// Whether the section could not be searched to its end. [hits] holds
  /// what was found before the failure.
  final bool failed;
}

/// The most hits that a section gives, and that a book gives.
const hitLimit = 500;

/// The number of sections that one worker isolate searches. A cancel takes
/// effect between batches.
const searchBatch = 8;

/// Searches the whole book, [sections] in spine order, for [query], with
/// [searchSections] in worker isolates through [hop], one batch of
/// [searchBatch] sections at a time.
///
/// The report is reader.js `searchBook`'s: at most [hitLimit] hits, and an
/// error when the query is empty or longer than 256 characters, when a
/// section or the book has more than [hitLimit] hits, or when a section
/// fails. [isCurrent] says whether the search is still wanted. It is asked
/// before and after each batch, and when it says no, the report is empty.
///
/// [contents] and [packagePath] give each hit's chapter, as
/// [chapterTitle] takes them.
Future<ReaderSearchReport> searchBook(
  List<SearchSection> sections,
  String query,
  List<ContentsEntry> contents,
  String packagePath, {
  required bool Function() isCurrent,
  IsolateHop hop = compute,
}) async {
  if (_blank(query) || query.length > 256) {
    return const ReaderSearchReport(
      [],
      error: 'Enter between 1 and 256 characters.',
    );
  }
  const cancelled = ReaderSearchReport([]);
  final hits = <ReaderHit>[];
  String? error;
  // Batches run one after another, not at once: a book that reaches the
  // limit needs no more batches, a cancel stops at the next batch, and the
  // workers that prepare sections for layout keep the other cores.
  for (var start = 0; start < sections.length; start += searchBatch) {
    if (!isCurrent()) return cancelled;
    final batch = sections.sublist(
      start,
      math.min(start + searchBatch, sections.length),
    );
    final found = await hop(_searchBatch, (
      batch,
      query,
      contents,
      packagePath,
    ));
    if (!isCurrent()) return cancelled;
    for (final section in found) {
      if (section.incomplete) {
        error =
            'Search is incomplete. Only the first $hitLimit matches per '
            'chapter are shown.';
      }
      for (final (location, excerpt) in section.hits) {
        if (hits.length >= hitLimit) {
          return ReaderSearchReport(
            hits,
            error:
                'Search is incomplete. Only the first $hitLimit matches are '
                'shown. Use a longer phrase.',
          );
        }
        hits.add(ReaderHit(EpubAddress(location), excerpt));
      }
      if (section.failed) {
        error =
            'Search is incomplete. A chapter could not be searched. Retry '
            'or use Contents.';
      }
    }
  }
  return ReaderSearchReport(hits, error: error);
}

List<SectionHits> _searchBatch(
  (List<SearchSection>, String, List<ContentsEntry>, String) input,
) => searchSections(input.$1, input.$2, input.$3, input.$4);

/// The hits of [query] in each of [sections], at most [hitLimit] per
/// section. A section that cannot be parsed has failed. It runs inside
/// `Isolate.run`.
List<SectionHits> searchSections(
  List<SearchSection> sections,
  String query,
  List<ContentsEntry> contents,
  String packagePath,
) {
  final needle = _foldQuery(query);
  return [
    for (final section in sections)
      _searchSection(section, needle, contents, packagePath),
  ];
}

SectionHits _searchSection(
  SearchSection section,
  String needle,
  List<ContentsEntry> contents,
  String packagePath,
) {
  final hits = <(ReadingLocation, String)>[];
  var incomplete = false;
  try {
    final dom = DomSection.parse(utf8.decode(section.xhtml));
    if (needle.isEmpty || dom.body.name != 'body') {
      return SectionHits(section.index, hits);
    }
    final text = _SearchText(dom);
    final chapters = _entriesInto(contents, packagePath, section.path);
    final starts = <int>[];
    for (
      var at = text.folded.indexOf(needle);
      at >= 0;
      at = text.folded.indexOf(needle, at + 1)
    ) {
      if (starts.length == hitLimit) {
        incomplete = true;
        break;
      }
      starts.add(at);
    }
    for (final at in starts) {
      final last = at + needle.length - 1;
      final start = EpubPlace(
        section.index,
        dom.texts[text.nodes[at]].order,
        text.starts[at],
      );
      final chapter = chapterTitle(
        dom,
        start,
        chapters,
        packagePath,
        section.path,
      );
      hits.add((
        hitLocation(section.spine, section.path, dom, start, chapter),
        _excerpt(
          dom,
          text.nodes[at],
          text.starts[at],
          text.nodes[last],
          text.ends[last],
        ),
      ));
    }
  } on Exception {
    return SectionHits(
      section.index,
      hits,
      incomplete: incomplete,
      failed: true,
    );
  }
  return SectionHits(section.index, hits, incomplete: incomplete);
}

/// The entries of [contents] that can name a chapter of the section at
/// [path]: all but those that point into another section. [chapterTitle]
/// skips those for each hit, so leaving them out gives the same chapters
/// with less work. A long book has hundreds of entries.
List<ContentsEntry> _entriesInto(
  List<ContentsEntry> contents,
  String packagePath,
  String path,
) {
  final package = Uri(scheme: 'https', host: 'book', path: '/$packagePath');
  bool elsewhere(String href) {
    try {
      return package.resolve(href).pathSegments.join('/') != path;
    } on FormatException {
      return false;
    }
  }

  return [
    for (final entry in contents)
      if (!elsewhere(entry.href)) entry,
  ];
}

/// The text of the body of [dom] from offset [start] of text node
/// [first] to offset [end] of text node [last], as a DOM range's
/// `toString` gives it, at most 160 characters. Like the range, it keeps
/// hidden text and CDATA text. [first] and [last] index [DomSection.texts].
String _excerpt(DomSection dom, int first, int start, int last, int end) {
  final texts = dom.texts;
  if (first == last) {
    return texts[first].text.substring(start, math.min(end, start + 160));
  }
  final buffer = StringBuffer(texts[first].text.substring(start));
  for (var index = first + 1; index < last && buffer.length < 160; index++) {
    buffer.write(texts[index].text);
  }
  if (buffer.length < 160) buffer.write(texts[last].text.substring(0, end));
  final excerpt = buffer.toString();
  return excerpt.length > 160 ? excerpt.substring(0, 160) : excerpt;
}

/// The searched text of a section and, for each of its code units, the
/// book text that it came from.
class _SearchText {
  _SearchText(DomSection dom) {
    final units = <int>[];
    DomElement? previousBlock;
    for (var index = 0; index < dom.texts.length; index++) {
      final node = dom.texts[index];
      // The tree walker shows text nodes, not CDATA sections.
      if (node.textIndex < 0) continue;
      var hidden = false;
      DomElement? block;
      for (
        var parent = node.parent;
        parent != null && parent != dom.body;
        parent = parent.parent
      ) {
        if (_hides(parent)) hidden = true;
        if (block == null && _blocks.contains(parent.name.toUpperCase())) {
          block = parent;
        }
      }
      if (hidden) continue;
      // reader.js keeps the block of the text node before, which is none
      // for text outside every block. Text after such text then runs into
      // the next block without a space.
      if (previousBlock != null &&
          block != previousBlock &&
          units.isNotEmpty &&
          units.last != _space) {
        units.add(_space);
        nodes.add(index);
        starts.add(0);
        ends.add(0);
      }
      previousBlock = block;
      final data = node.text;
      for (var offset = 0; offset < data.length;) {
        var point = data.codeUnitAt(offset);
        var end = offset + 1;
        if (_isLead(point) &&
            end < data.length &&
            _isTrail(data.codeUnitAt(end))) {
          point =
              0x10000 +
              ((point - 0xd800) << 10) +
              data.codeUnitAt(end) -
              0xdc00;
          end++;
        }
        if (isSpace(point)) {
          // A space that follows a space only widens the one before. A
          // match never starts or ends on a space, so the widened end is
          // not kept.
          if (units.isEmpty || units.last != _space) {
            units.add(_space);
            nodes.add(index);
            starts.add(offset);
            ends.add(end);
          }
        } else if (point < 0x80) {
          units.add(point >= 0x41 && point <= 0x5a ? point + 0x20 : point);
          nodes.add(index);
          starts.add(offset);
          ends.add(end);
        } else {
          for (final unit in _lower(point)) {
            units.add(unit);
            nodes.add(index);
            starts.add(offset);
            ends.add(end);
          }
        }
        offset = end;
      }
    }
    folded = String.fromCharCodes(units);
  }

  /// The searched text.
  late final String folded;

  /// For each code unit of [folded]: the index in [DomSection.texts] of the
  /// text node that it came from, and the code unit offsets in that node
  /// where its character starts and ends. A space between two blocks
  /// starts and ends at 0 in the text node after it.
  final nodes = <int>[];
  final starts = <int>[];
  final ends = <int>[];
}

const _space = 0x20;

/// The elements that reader.js counts as blocks, by upper case name.
const _blocks = {
  'P',
  'DIV',
  'LI',
  'H1',
  'H2',
  'H3',
  'H4',
  'H5',
  'H6',
  'BLOCKQUOTE',
  'TD',
  'TH',
  'PRE',
  'SECTION',
  'ARTICLE',
};

final _hiddenStyle = RegExp(
  r'(?:display\s*:\s*none|visibility\s*:\s*hidden)',
  caseSensitive: false,
);

/// Whether [element] hides the text in it from a search.
bool _hides(DomElement element) =>
    element.attributes.containsKey('hidden') ||
    element.attributes['aria-hidden'] == 'true' ||
    _hiddenStyle.hasMatch(element.attributes['style'] ?? '') ||
    const {'SCRIPT', 'STYLE', 'TEMPLATE'}.contains(element.name.toUpperCase());

bool _isLead(int unit) => unit >= 0xd800 && unit <= 0xdbff;
bool _isTrail(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

/// Whether [text] is empty after JavaScript's `trim`. Dart's `trim` also
/// removes U+0085, which JavaScript keeps.
bool _blank(String text) => text.codeUnits.every(isSpace);

/// [query] as reader.js folds it: lowercased as a whole by JavaScript's
/// `toLowerCase`, each run of white space one space, and no white space at
/// either end.
String _foldQuery(String query) {
  final points = query.runes.toList();
  final units = <int>[];
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    if (isSpace(point)) {
      if (units.isNotEmpty && units.last != _space) units.add(_space);
    } else if (point == 0x3a3 && _endsWord(points, index)) {
      units.add(0x3c2);
    } else {
      units.addAll(_lower(point));
    }
  }
  if (units.isNotEmpty && units.last == _space) units.removeLast();
  return String.fromCharCodes(units);
}

/// Whether the capital sigma at [index] of [points] lowercases to a final
/// sigma, by the Final_Sigma rule of Unicode's SpecialCasing that
/// JavaScript applies to a whole string: a cased letter comes before it and
/// none comes after it, each across case-ignorable characters.
bool _endsWord(List<int> points, int index) {
  int? near(int step) {
    for (var at = index + step; at >= 0 && at < points.length; at += step) {
      if (!_caseIgnorable(points[at])) return points[at];
    }
    return null;
  }

  final before = near(-1);
  final after = near(1);
  return before != null && _cased(before) && (after == null || !_cased(after));
}

/// Whether [point] has a case. A letter whose lower and upper case are the
/// same counts as uncased. This misses a few cased letters without a pair.
bool _cased(int point) {
  final character = String.fromCharCode(point);
  return character.toLowerCase() != character.toUpperCase();
}

/// Whether [point] is case-ignorable in the Final_Sigma rule. This covers
/// the apostrophes, word-inner punctuation, modifier letters, combining
/// marks and format characters that Greek text uses, not the whole Unicode
/// property.
bool _caseIgnorable(int point) =>
    const {
      0x27, 0x2e, 0x3a, 0x5e, 0x60, 0xa8, 0xad, 0xaf, 0xb4, 0xb7, 0xb8, //
      0x374, 0x375, 0x37a, 0x384, 0x385, 0x387, 0x2018, 0x2019, 0x2024,
      0x2027,
    }.contains(point) ||
    (point >= 0x2b0 && point <= 0x36f) ||
    (point >= 0x200b && point <= 0x200f) ||
    (point >= 0xfe00 && point <= 0xfe0f);

/// The code units of [point] lowercased by itself, as JavaScript's
/// `toLowerCase` gives them for a string of that one character.
List<int> _lower(int point) {
  if (point < 0x80) {
    return point >= 0x41 && point <= 0x5a ? [point + 0x20] : [point];
  }
  return _lowered[point] ??= point == 0x130
      // JavaScript lowercases a dotted capital I to i and a combining dot,
      // where Dart drops the dot.
      ? const [0x69, 0x307]
      : String.fromCharCode(point).toLowerCase().codeUnits;
}

/// The lower case of each character outside ASCII met so far, in this
/// isolate.
final _lowered = <int, List<int>>{};
