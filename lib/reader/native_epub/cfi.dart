// Converts between the trial renderer's DOM positions and the EPUB CFIs,
// quotes and text progress that Bookfin saves today.
//
// The WebView reader saves a place as epub.js writes it (reader.js
// `visibleLocation`): a collapsed CFI, the first 120 characters of the
// body's text from the place on, and the share of the section's visible
// characters before the place. These functions write the same three
// values, so a place saved by one renderer opens in the other.
import 'package:xml/xml.dart';

import 'dom.dart';
import 'layout.dart';

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

/// The CFI of [position] in a section whose spine step is [spine].
String cfiOf(String spine, DomPosition position) {
  final steps = <String>[];
  DomNode node = position.text ?? position.element!;
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
  final terminal = position.text == null ? '' : ':${position.offset}';
  return 'epubcfi($spine!/${steps.reversed.join('/')}$terminal)';
}

/// The spine index of [cfi], or null when it is not a CFI.
int? spineIndexOf(String cfi) {
  final match = RegExp(r'^epubcfi\(/\d+/(\d+)').firstMatch(cfi);
  if (match == null) return null;
  return int.parse(match.group(1)!) ~/ 2 - 1;
}

/// The position that [cfi] names in [section], or null when its path does
/// not exist. A range resolves to its start. Like epub.js, an offset past
/// the end of its text node stops at that end.
DomPosition? positionOf(DomSection section, String cfi) {
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
  DomNode node = section.root;
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
  if (node is DomText) {
    return DomPosition.text(node, offset.clamp(0, node.text.length));
  }
  return DomPosition.element(node as DomElement);
}

/// The place that epub.js saves for a page whose first character is at
/// [position].
///
/// epub.js (mapping.js `splitTextNodeIntoRanges`) trims the text node,
/// finds each space in the trimmed text, and starts a range after each
/// one, at that offset in the untrimmed node. It saves the start of the
/// first range that lies on the page: the first range start after the
/// node's last visible character before [position]. A node that starts
/// with white space therefore gets starts that sit before their words.
DomPosition wordStart(DomPosition position) {
  final text = position.text;
  if (text == null) return position;
  final data = text.text;
  var lastVisible = position.offset - 1;
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
  if (lastVisible < 0) return DomPosition.text(text, 0);
  for (var space = trimmed.indexOf(' '); space >= 0;) {
    final start = space + 1;
    if (start > lastVisible) return DomPosition.text(text, start);
    space = trimmed.indexOf(' ', space + 1);
  }
  return position;
}

/// The first 120 characters of the body's text from [position] on, as
/// reader.js `quoteAt` gives them.
String quoteAt(DomSection section, DomPosition position) {
  final first = position.text ?? section.textFrom(position.element!);
  if (first == null) return '';
  final buffer = StringBuffer(
    position.text == null ? first.text : first.text.substring(position.offset),
  );
  for (
    var index = section.texts.indexOf(first) + 1;
    index < section.texts.length && buffer.length < 120;
    index++
  ) {
    buffer.write(section.texts[index].text);
  }
  final quote = buffer.toString();
  return quote.length > 120 ? quote.substring(0, 120) : quote;
}

/// The text progress of [position] through [section], as reader.js
/// `progressAt` gives it: the share of visible characters before it,
/// rounded to six decimals.
double progressAt(DomSection section, DomPosition position) {
  if (section.visibleLength == 0) return 0;
  final before = visibleIndex(section, position);
  return (before / section.visibleLength * 1e6).round() / 1e6;
}
