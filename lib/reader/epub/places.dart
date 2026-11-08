// Converts between places in the native DOM and the EPUB CFIs, quotes and
// text progress that Bookfin saves today.
//
// The WebView reader saves a place as epub.js writes it (reader.js
// `visibleLocation`): a collapsed CFI, the first 120 characters of the
// body's text from the place on, and the share of the section's visible
// characters before the place. These functions write the same three
// values, so a place saved by one renderer opens in the other.
import 'package:xml/xml.dart';

import 'dom.dart';

/// The spine step of a CFI for spine item [index] of the package document
/// [opf], as epub.js writes it: `/6/4`, with the itemref's id as an
/// assertion when it has one.
String spineStep(String opf, int index) {
  final package = XmlDocument.parse(opf).rootElement;
  final elements = package.childElements.toList();
  final spine = elements.indexWhere((element) => element.localName == 'spine');
  final itemref = elements[spine].childElements
      .where((element) => element.localName == 'itemref')
      .elementAt(index);
  final id = itemref.getAttribute('id');
  return '/${(spine + 1) * 2}/${(index + 1) * 2}'
      '${id == null || id.isEmpty ? '' : '[$id]'}';
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

/// The place that epub.js saves for a page of [dom] whose first character
/// is at [place].
///
/// epub.js (mapping.js `splitTextNodeIntoRanges`) trims the text node,
/// finds each space in the trimmed text, and starts a range after each
/// one, at that offset in the untrimmed node. It saves the start of the
/// first range that lies on the page: the first range start after the
/// node's last visible character before [place]. A node that starts with
/// white space therefore gets starts that sit before their words.
EpubPlace wordStart(DomSection dom, EpubPlace place) {
  final text = dom.textAt(place);
  if (text == null) return place;
  final data = text.text;
  var lastVisible = place.offset - 1;
  while (lastVisible >= 0 && isSpace(data.codeUnitAt(lastVisible))) {
    lastVisible--;
  }
  var lead = 0;
  while (lead < data.length && isSpace(data.codeUnitAt(lead))) {
    lead++;
  }
  var end = data.length;
  while (end > lead && isSpace(data.codeUnitAt(end - 1))) {
    end--;
  }
  final trimmed = data.substring(lead, end);
  if (lastVisible < 0) return EpubPlace(place.section, place.node, 0);
  for (var space = trimmed.indexOf(' '); space >= 0;) {
    final start = space + 1;
    if (start > lastVisible) return EpubPlace(place.section, place.node, start);
    space = trimmed.indexOf(' ', space + 1);
  }
  return place;
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
  for (
    var index = dom.texts.indexOf(first) + 1;
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
