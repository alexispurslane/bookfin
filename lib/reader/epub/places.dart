// Converts between places in the native DOM and the EPUB CFIs, quotes and
// text progress that Bookfin saves today.
//
// Bookfin's former WebView reader saved a place as epub.js writes it
// (reader.js `visibleLocation`): a collapsed CFI, the first 120 characters
// of the body's text from the place on, and the share of the section's
// visible characters before the place. These functions read and write the
// same three values, so a place that the WebView reader saved still opens,
// and an older Bookfin opens a place that this one saves. A page saves its
// first visible character ([firstVisible]), not epub.js's word start.
import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../document.dart';
import 'dom.dart';

/// The spine step of a CFI for spine item [index] of the package document
/// [opf], as epub.js writes it: `/6/4`, with the itemref's id as an
/// assertion when it has one.
String spineStep(String opf, int index) => spineSteps(opf)[index];

/// The spine step of each spine item of the package document [opf], in
/// spine order, as [spineStep] gives it. It reads [opf] once.
List<String> spineSteps(String opf) =>
    spineStepsOf(XmlDocument.parse(opf).rootElement);

/// The spine steps of [spineSteps], from the parsed root element of the
/// package document, [package].
List<String> spineStepsOf(XmlElement package) {
  final elements = package.childElements.toList();
  final spine = elements.indexWhere((element) => element.localName == 'spine');
  final itemrefs = elements[spine].childElements.where(
    (element) => element.localName == 'itemref',
  );
  String step(int index, String? id) =>
      '/${(spine + 1) * 2}/${(index + 1) * 2}'
      '${id == null || id.isEmpty ? '' : '[$id]'}';
  return [
    for (final (index, itemref) in itemrefs.indexed)
      step(index, itemref.getAttribute('id')),
  ];
}

/// The CFI of [place] in [dom], a section whose spine step is [spine].
String cfiOf(String spine, DomSection dom, EpubPlace place) {
  final steps = <String>[];
  final node = dom.nodeAt(place.node);
  if (node is DomText) steps.add('${1 + 2 * node.textIndex}');
  var element = node is DomText ? node.parent! : node as DomElement;
  while (element.parent != null) {
    final id = element.id;
    steps.add(
      '${(element.elementIndex + 1) * 2}'
      '${id == null || id.isEmpty ? '' : '[$id]'}',
    );
    element = element.parent!;
  }
  final terminal = node is DomText ? ':${place.offset}' : '';
  return 'epubcfi($spine!/${steps.reversed.join('/')}$terminal)';
}

/// The spine index of [cfi], or null when it is not a CFI.
int? spineIndexOf(String cfi) {
  final match = RegExp(r'^epubcfi\(/\d+/(\d+)').firstMatch(cfi);
  if (match == null) return null;
  return int.parse(match.group(1)!) ~/ 2 - 1;
}

/// The place that [cfi] names in [dom], the section with spine index
/// [section], or null when its path does not exist. A range resolves to its
/// start. Like epub.js, an offset past the end of its text node stops at
/// that end.
EpubPlace? placeOf(DomSection dom, int section, String cfi) {
  final bang = cfi.indexOf('!');
  if (!cfi.startsWith('epubcfi(') || bang < 0 || !cfi.endsWith(')')) {
    return null;
  }
  var path = cfi.substring(bang + 1, cfi.length - 1);
  final comma = path.indexOf(',');
  if (comma >= 0) {
    // A range: the common path, then the start's own steps.
    final parts = path.split(',');
    path = parts[0] + parts[1];
  }
  var offset = -1;
  final colon = path.lastIndexOf(':');
  if (colon >= 0) {
    offset = int.tryParse(path.substring(colon + 1).split('[').first) ?? 0;
    path = path.substring(0, colon);
  }
  DomNode node = dom.root;
  for (final step in path.split('/').where((step) => step.isNotEmpty)) {
    final number = int.tryParse(step.split('[').first);
    if (number == null || node is! DomElement) return null;
    if (number.isEven) {
      final index = number ~/ 2 - 1;
      if (index < 0 || index >= node.elements.length) return null;
      node = node.elements[index];
    } else {
      final index = (number - 1) ~/ 2;
      final found = node.children.whereType<DomText>().where(
        (text) => text.textIndex == index,
      );
      if (found.isEmpty) return null;
      node = found.first;
    }
  }
  return EpubPlace(
    section,
    node.order,
    node is DomText ? offset.clamp(0, node.text.length) : 0,
  );
}

/// The place that a page of [dom] saves when it starts at [start] and its
/// last visible character is at [end]: the page's first visible character,
/// the first one at or after [start]. It can be in a later text node than
/// [start], when [start] is in white space at the end of its node. When the
/// page shows no visible character from [start] to [end], [start] stays.
///
/// epub.js saved the start of the first space-delimited word at or after
/// the page start instead. In text with few spaces, such as Chinese, that
/// word can start on a later page (t1-7l9c).
EpubPlace firstVisible(DomSection dom, EpubPlace start, EpubPlace end) {
  if (dom.textAt(start) == null) return start;
  final wanted = dom.visibleBefore(start);
  if (wanted >= dom.visibleLength) return start;
  final first = _visibleAt(dom, start.section, wanted);
  return first.compareTo(end) <= 0 ? first : start;
}

/// The first 120 characters of the body's text of [dom] from [place] on,
/// as reader.js `quoteAt` gives them.
String quoteAt(DomSection dom, EpubPlace place) {
  final text = dom.textAt(place);
  final first = text ?? dom.textFrom(dom.nodeAt(place.node));
  if (first == null) return '';
  final buffer = StringBuffer(
    text == null ? first.text : first.text.substring(place.offset),
  );
  // Text nodes are in document order. Locate the suffix without scanning
  // the part of the section before this page. A text outside the body
  // keeps the old behavior: its quote continues at the body's first text.
  var low = 0;
  var high = dom.texts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (dom.texts[middle].order < first.order) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  final next = low < dom.texts.length && identical(dom.texts[low], first)
      ? low + 1
      : 0;
  for (
    var index = next;
    index < dom.texts.length && buffer.length < 120;
    index++
  ) {
    buffer.write(dom.texts[index].text);
  }
  final quote = buffer.toString();
  return quote.length > 120 ? quote.substring(0, 120) : quote;
}

/// The text progress of [place] through [dom], as reader.js `progressAt`
/// gives it: the share of visible characters before it, rounded to six
/// decimals.
double progressAt(DomSection dom, EpubPlace place) {
  if (dom.visibleLength == 0) return 0;
  final before = dom.visibleBefore(place);
  return (before / dom.visibleLength * 1e6).round() / 1e6;
}

/// The place at text progress [progress] through [dom], the section with
/// spine index [section], as reader.js `placeAt` finds it: the visible
/// character at `floor(progress × total)`, at most the last one. A section
/// without visible text has its body.
///
/// [progress] runs from 0 to 1, in the measure of [progressAt].
EpubPlace placeAt(DomSection dom, int section, double progress) {
  if (!(progress >= 0 && progress <= 1)) {
    throw ArgumentError.value(progress, 'progress', 'must be from 0 to 1');
  }
  final total = dom.visibleLength;
  if (total == 0) return EpubPlace(section, dom.body.order, 0);
  return _visibleAt(
    dom,
    section,
    math.min(total - 1, (progress * total).floor()),
  );
}

/// The place of the visible character of [dom], the section with spine
/// index [section], that [wanted] visible characters come before.
///
/// [wanted] runs from 0 to [DomSection.visibleLength] − 1.
EpubPlace _visibleAt(DomSection dom, int section, int wanted) {
  final text = dom.textHolding(wanted);
  var left = wanted - text.visibleBefore;
  var offset = 0;
  for (; offset < text.text.length; offset++) {
    if (!isSpace(text.text.codeUnitAt(offset)) && left-- == 0) break;
  }
  return EpubPlace(section, text.order, offset);
}

/// The place that a link or a contents entry to [fragment] in [dom], the
/// section with spine index [section], opens, as reader.js
/// `resolveDestination` finds it: the first text node in the element whose
/// id is [fragment], at offset 0, even when it is white space. Without a
/// fragment the element is the body. An element without text is its own
/// place. A fragment that names no element has no destination.
///
/// [fragment] is the decoded id, or null or empty for none.
EpubPlace? destination(DomSection dom, int section, String? fragment) {
  final target = fragment == null || fragment.isEmpty
      ? dom.body
      : dom.elementById(fragment);
  if (target == null) return null;
  // A tree walker that shows text nodes skips CDATA sections.
  final text = target.texts.where((text) => text.textIndex >= 0).firstOrNull;
  return EpubPlace(section, (text ?? target).order, 0);
}

/// Whether the text of [dom] at [place] starts with [quote], the quote of a
/// saved place, as reader.js `verifyLocation` checks it. An empty quote
/// matches every place.
bool quoteMatches(DomSection dom, EpubPlace place, String quote) =>
    quote.isEmpty || quoteAt(dom, place).startsWith(quote);

/// The chapter labels derived from one section's DOM and contents. Prepare
/// once beside that DOM, in its worker, and keep for the same lifetime.
/// Nothing changes the resolved locations or fallback after construction.
class ChapterTitles {
  /// Resolves the entries of [contents] into [dom], the section at
  /// [sectionPath]. Each href is relative to the package at [packagePath].
  /// Missing or malformed targets and other sections are ignored. An
  /// entry without a fragment points at the body; fragments are decoded.
  ChapterTitles(
    DomSection dom,
    List<ContentsEntry> contents,
    String packagePath,
    String sectionPath,
  ) : _dom = dom,
      _fallback = _heading(dom) {
    final package = Uri(scheme: 'https', host: 'book', path: '/$packagePath');
    for (final (order, entry) in contents.indexed) {
      final DomElement? target;
      try {
        final href = package.resolve(entry.href);
        if (href.pathSegments.join('/') != sectionPath) continue;
        target = href.fragment.isEmpty
            ? dom.body
            : dom.elementById(Uri.decodeComponent(href.fragment));
      } on FormatException {
        continue;
      }
      if (target == null) continue;
      _entries.add((
        steps: _steps(dom, EpubPlace(0, target.order, 0)),
        title: entry.title,
        order: order,
      ));
    }
    _entries.sort((a, b) {
      final compared = _compareSteps(a.steps, b.steps);
      // List.sort is not stable: contents order must break equal-place ties.
      return compared != 0 ? compared : a.order.compareTo(b.order);
    });
  }

  final DomSection _dom;
  final String? _fallback;
  final _entries = <({(List<int>, int) steps, String title, int order})>[];

  /// The title of the last contents entry at or before [place], comparing
  /// CFIs as epub.js does, step by step ([_compareSteps]). The last entry
  /// in contents order wins at equal positions. Before all entries, uses
  /// the first `h1` or `title` in document order, trimmed, or "Chapter N"
  /// for the section's spine position N. Returns at most 512 characters.
  /// [place] belongs to the DOM that this object was prepared from.
  String at(EpubPlace place) {
    final steps = _steps(_dom, place);
    var low = 0;
    var high = _entries.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_compareSteps(_entries[middle].steps, steps) <= 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final chapter = low == 0
        ? _fallback ?? 'Chapter ${place.section + 1}'
        : _entries[low - 1].title;
    return chapter.length > 512 ? chapter.substring(0, 512) : chapter;
  }
}

/// The trimmed text of the first `h1` or `title` element of [dom] in
/// document order, as `querySelector('h1, title')` finds it, or null when
/// there is none or its text is empty.
String? _heading(DomSection dom) {
  DomElement? find(DomElement element) {
    if (element.name == 'h1' || element.name == 'title') return element;
    for (final child in element.elements) {
      if (find(child) case final found?) return found;
    }
    return null;
  }

  final heading = find(dom.root);
  if (heading == null) return null;
  final text = heading.texts.map((text) => text.text).join();
  var start = 0;
  var end = text.length;
  while (start < end && isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return start == end ? null : text.substring(start, end);
}

/// The steps of the CFI of [place] below the root element, as epub.js
/// parses them: each element's index among its parent's elements, then a
/// text node's index among its parent's text nodes. The second value is the
/// character offset, 0 for an element.
(List<int>, int) _steps(DomSection dom, EpubPlace place) {
  final node = dom.nodeAt(place.node);
  final steps = <int>[if (node is DomText) node.textIndex];
  var element = node is DomText ? node.parent! : node as DomElement;
  while (element.parent != null) {
    steps.add(element.elementIndex);
    element = element.parent!;
  }
  return (steps.reversed.toList(), place.offset);
}

/// Compares two CFIs of one section as epub.js `EpubCFI.compare` does: step
/// by step by index, where an element and a text node with the same index
/// count as equal; then the shorter path first; then the offset. So an
/// element can count as before a text node that precedes it.
int _compareSteps((List<int>, int) a, (List<int>, int) b) {
  final (stepsA, offsetA) = a;
  final (stepsB, offsetB) = b;
  for (var index = 0; index < stepsA.length; index++) {
    if (index >= stepsB.length) return 1;
    if (stepsA[index] != stepsB[index]) {
      return stepsA[index].compareTo(stepsB[index]);
    }
  }
  if (stepsA.length < stepsB.length) return -1;
  return offsetA.compareTo(offsetB);
}

/// The saved location of a page of [dom] that starts at [start] and whose
/// last visible character is at [end], in the form that reader.js
/// `visibleLocation` writes for a shown page: the CFI, quote and progress
/// of the page's [firstVisible] character, in the section at [sectionPath]
/// whose spine step is [spine]. [chapter] is the [ChapterTitles.at] of that
/// character. Its [ReadingLocation.end] is the progress of [end], and it
/// has no page number.
ReadingLocation pageLocation(
  String spine,
  String sectionPath,
  DomSection dom,
  EpubPlace start,
  EpubPlace end,
  String chapter,
) {
  final first = firstVisible(dom, start, end);
  return ReadingLocation(
    cfiOf(spine, dom, first),
    sectionPath,
    quoteAt(dom, first),
    chapter: chapter,
    progress: progressAt(dom, first),
    end: progressAt(dom, end),
  );
}

/// The location of a search hit of [dom] whose match starts at [start], as
/// reader.js `searchBook` writes it: the CFI and quote of [start] itself,
/// in the section at [sectionPath] whose spine step is [spine], with
/// [chapter], its [ChapterTitles.at]. Like reader.js, it has no progress.
ReadingLocation hitLocation(
  String spine,
  String sectionPath,
  DomSection dom,
  EpubPlace start,
  String chapter,
) => ReadingLocation(
  cfiOf(spine, dom, start),
  sectionPath,
  quoteAt(dom, start),
  chapter: chapter,
);

/// Whether [link], an `a` element, is a note reference: its `epub:type` has
/// the token `noteref`, or its role is `doc-noteref`.
bool isNoteReference(DomElement link) =>
    _types(link).contains('noteref') || _roles(link).contains('doc-noteref');

/// Whether [link], an `a` element, is a note's link back to its reference:
/// its `epub:type` has the token `backlink`, or its role is `doc-backlink`.
bool isBackLink(DomElement link) =>
    _types(link).contains('backlink') || _roles(link).contains('doc-backlink');

/// The note that a link to [target] shows over the page, or null when the
/// link jumps to [target]. [reference] is whether the link is a note
/// reference ([isNoteReference]).
///
/// The note is the nearest element at or around [target] whose `epub:type`
/// has the token `footnote`, `endnote`, `rearnote` or `note`, or whose role
/// is `doc-footnote` or `doc-endnote`. Without one, a note reference shows
/// [target] itself, or when [target] has no visible text, such as an empty
/// anchor, the nearest element around it with text. A link without a
/// target shows no note.
DomElement? noteOf(DomElement? target, {required bool reference}) {
  for (var element = target; element != null; element = element.parent) {
    if (_types(element).any(_noteTypes.contains) ||
        _roles(element).any(_noteRoles.contains)) {
      return element;
    }
  }
  if (!reference) return null;
  var element = target;
  while (element != null &&
      !element.texts.any(
        (text) => visibleCount(text.text, 0, text.text.length) > 0,
      )) {
    element = element.parent;
  }
  return element;
}

const _noteTypes = {'footnote', 'endnote', 'rearnote', 'note'};
const _noteRoles = {'doc-footnote', 'doc-endnote'};

/// The tokens of [element]'s `epub:type` and of its `role`.
Iterable<String> _types(DomElement element) => _tokens(element, 'epub:type');
Iterable<String> _roles(DomElement element) => _tokens(element, 'role');
Iterable<String> _tokens(DomElement element, String attribute) =>
    (element.attributes[attribute] ?? '')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty);
