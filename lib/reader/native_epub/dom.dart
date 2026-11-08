// A small read-only DOM of one XHTML spine section, for the trial renderer.
//
// It keeps the facts that layout and EPUB CFIs need: element and text
// children in document order, each element's index among its parent's
// element children, and each text node's index among its parent's text
// children. epub.js numbers CFI steps from the same two indices.
import 'package:xml/xml.dart';

sealed class DomNode {
  DomElement? parent;

  /// The node's place in document order: a parent comes before its
  /// children, and each child before its next sibling.
  int order = 0;
}

final class DomText extends DomNode {
  DomText(this.text, this.textIndex);

  /// The node's character data, as the browser's DOM holds it.
  final String text;

  /// The node's index among its parent's text children.
  final int textIndex;

  /// The number of visible characters (white space left out) in the
  /// section's body before this node. Set by [DomSection].
  int visibleBefore = 0;
}

final class DomElement extends DomNode {
  DomElement(this.name, this.attributes, this.elementIndex);

  /// The local name, such as `p`.
  final String name;

  /// Attributes by qualified name, such as `class` or `epub:type`.
  final Map<String, String> attributes;

  /// The element's index among its parent's element children.
  final int elementIndex;
  final List<DomNode> children = [];
  final List<DomElement> elements = [];

  late final Set<String> classes = {
    for (final name in (attributes['class'] ?? '').split(RegExp(r'\s+')))
      if (name.isNotEmpty) name,
  };
  String? get id => attributes['id'];

  Iterable<DomText> get texts sync* {
    for (final child in children) {
      if (child is DomText) {
        yield child;
      } else if (child is DomElement) {
        yield* child.texts;
      }
    }
  }
}

/// One parsed spine section.
class DomSection {
  DomSection._(this.root, this.body, this.texts, this.visibleLength);

  /// Parses [source], an XHTML document.
  factory DomSection.parse(String source) {
    final document = XmlDocument.parse(source);
    final root = _convert(document.rootElement, 0);
    var order = 0;
    void number(DomNode node) {
      node.order = order++;
      if (node is DomElement) node.children.forEach(number);
    }

    number(root);
    final body =
        root.elements.where((element) => element.name == 'body').firstOrNull ??
        root;
    final texts = body.texts.toList(growable: false);
    var visible = 0;
    for (final text in texts) {
      text.visibleBefore = visible;
      visible += visibleCount(text.text, 0, text.text.length);
    }
    return DomSection._(root, body, texts, visible);
  }

  final DomElement root;
  final DomElement body;

  /// The body's text nodes in document order.
  final List<DomText> texts;

  /// The number of visible characters in the body.
  final int visibleLength;

  /// The first body text node at or after [node] in document order, or
  /// null when none follows.
  DomText? textFrom(DomNode node) {
    var low = 0;
    var high = texts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (texts[middle].order < node.order) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < texts.length ? texts[low] : null;
  }
}

/// The number of characters in [text] from [start] to [end] that are not
/// white space, as JavaScript's `\s` defines it.
int visibleCount(String text, int start, int end) {
  var count = 0;
  for (var index = start; index < end; index++) {
    if (!isSpace(text.codeUnitAt(index))) count++;
  }
  return count;
}

/// Whether [unit] is white space as JavaScript's `\s` defines it.
bool isSpace(int unit) =>
    unit == 0x20 ||
    (unit >= 0x09 && unit <= 0x0d) ||
    unit == 0xa0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200a) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202f ||
    unit == 0x205f ||
    unit == 0x3000 ||
    unit == 0xfeff;

DomElement _convert(XmlElement source, int index) {
  final element = DomElement(source.name.local, {
    for (final attribute in source.attributes)
      attribute.name.qualified: attribute.value,
  }, index);
  var elements = 0;
  var texts = 0;
  for (final child in source.children) {
    // The browser's DOM merges adjacent character data into one text node.
    // A CDATA section stays its own node, which epub.js does not count.
    if (child is XmlText) {
      final previous = element.children.lastOrNull;
      if (previous is DomText && child.previousSibling is XmlText) {
        element.children.last = DomText(
          previous.text + child.value,
          previous.textIndex,
        )..parent = element;
        continue;
      }
      element.children.add(DomText(child.value, texts++)..parent = element);
    } else if (child is XmlCDATA) {
      element.children.add(DomText(child.value, -1)..parent = element);
    } else if (child is XmlElement) {
      final converted = _convert(child, elements++)..parent = element;
      element.children.add(converted);
      element.elements.add(converted);
    }
  }
  return element;
}
