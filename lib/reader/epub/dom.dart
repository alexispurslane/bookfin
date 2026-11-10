// A small read-only DOM of one XHTML spine section, and the places in it.
//
// It keeps the facts that layout and EPUB CFIs need: element and text
// children in document order, each element's index among its parent's
// element children, and each text node's index among its parent's text
// children. epub.js numbers CFI steps from the same two indices. Nothing
// here uses dart:ui, so a worker isolate can build it.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// A place in an EPUB: a section, a node's document order in it, and a
/// code unit offset in a text node (0 for an element).
///
/// Nodes are named by number, so a place stays valid across two parses of
/// the same section.
class EpubPlace implements Comparable<EpubPlace> {
  const EpubPlace(this.section, this.node, this.offset);

  /// The spine index of the section.
  final int section;

  /// The [DomNode.order] of the node.
  final int node;

  /// The code unit offset in a text node, or 0 for an element.
  final int offset;

  @override
  int compareTo(EpubPlace other) => section != other.section
      ? section.compareTo(other.section)
      : node != other.node
      ? node.compareTo(other.node)
      : offset.compareTo(other.offset);

  @override
  bool operator ==(Object other) =>
      other is EpubPlace &&
      other.section == section &&
      other.node == node &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(section, node, offset);

  @override
  String toString() => 'EpubPlace($section, $node, $offset)';
}

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

  /// The number of visible characters in [text] before code unit [offset].
  ///
  /// It counts from the nearest of the counts kept at every [_chunk] code
  /// units, so that the pages of a long text node, such as a poem in one
  /// `pre` element, do not each count from the node's start.
  int visibleTo(int offset) {
    final end = math.min(offset, text.length);
    if (text.length <= _chunk) return visibleCount(text, 0, end);
    final chunk = end ~/ _chunk;
    return _chunks[chunk] + visibleCount(text, chunk * _chunk, end);
  }

  static const _chunk = 256;

  /// The visible characters before each multiple of [_chunk] code units.
  late final Int32List _chunks = () {
    final counts = Int32List(text.length ~/ _chunk + 1);
    for (var chunk = 1; chunk < counts.length; chunk++) {
      counts[chunk] =
          counts[chunk - 1] +
          visibleCount(text, (chunk - 1) * _chunk, chunk * _chunk);
    }
    return counts;
  }();
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
    for (final name in (attributes['class'] ?? '').split(_spaces))
      if (name.isNotEmpty) name,
  };
  String? get id => attributes['id'];

  static final _spaces = RegExp(r'\s+');

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
  DomSection._(
    this.root,
    this.body,
    this._nodes,
    this.texts,
    this.visibleLength,
  );

  /// Parses [source], an XHTML document.
  factory DomSection.parse(String source) {
    final document = XmlDocument.parse(source);
    final root = _convert(document.rootElement, 0);
    final nodes = <DomNode>[];
    void number(DomNode node) {
      node.order = nodes.length;
      nodes.add(node);
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
    return DomSection._(root, body, nodes, texts, visible);
  }

  final DomElement root;
  final DomElement body;

  /// Every node of the document, by [DomNode.order].
  final List<DomNode> _nodes;

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

  /// The first element of the document whose id is [id], as
  /// `getElementById` finds it, or null when none has it.
  DomElement? elementById(String id) => _ids[id];

  late final Map<String, DomElement> _ids = {
    for (final node in _nodes.reversed)
      if (node case DomElement(id: final id?)) id: node,
  };

  /// The node whose [DomNode.order] is [order].
  DomNode nodeAt(int order) => _nodes[order];

  /// The text node that [place] is in, or null when it names an element.
  DomText? textAt(EpubPlace place) => switch (_nodes[place.node]) {
    final DomText text => text,
    _ => null,
  };

  /// The number of visible characters of the body before [place]. An
  /// element's place is the first text in or after it.
  int visibleBefore(EpubPlace place) {
    final node = _nodes[place.node];
    if (node is DomText) {
      return node.visibleBefore + node.visibleTo(place.offset);
    }
    return textFrom(node)?.visibleBefore ?? visibleLength;
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
