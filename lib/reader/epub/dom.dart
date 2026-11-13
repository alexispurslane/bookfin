// A small read-only DOM of one XHTML spine section, and the places in it.
//
// It keeps the facts that layout and EPUB CFIs need: element and text
// children in document order, each element's index among its parent's
// element children, and each text node's index among its parent's text
// children. epub.js numbers CFI steps from the same two indices. Nothing
// here uses dart:ui, so a worker isolate can build it.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart' show XmlDocument;
import 'package:xml/xml_events.dart';

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

/// A contiguous selection of original nodes inside [root]. No node is copied
/// or reparented. [from] is included; [before] and everything after it are
/// excluded. Omitting both selects the whole element.
class DomSelection {
  DomSelection(this.root, {DomNode? from, DomNode? before})
    : first = (from ?? root).order,
      end = before?.order ?? _endOf(root) {
    if (first < root.order || end > _endOf(root) || first >= end) {
      throw ArgumentError('The selection must lie inside its root.');
    }
  }

  final DomElement root;
  final int first;
  final int end;

  /// The same selection on [document]'s original node instances after a
  /// worker hop. The document must be the same admitted section; stable
  /// document-order numbers identify its nodes across isolates.
  DomSelection inDocument(DomSection document) =>
      DomSelection._(document.nodeAt(root.order) as DomElement, first, end);

  DomSelection._(this.root, this.first, this.end);

  bool contains(int order) => order >= first && order < end;

  Iterable<DomText> get texts =>
      root.texts.where((node) => contains(node.order));

  /// Selected elements in document order, including the root when selected.
  Iterable<DomElement> get elements sync* {
    Iterable<DomElement> visit(DomElement element) sync* {
      if (element.order >= end) return;
      if (contains(element.order)) yield element;
      for (final child in element.elements) {
        yield* visit(child);
      }
    }

    yield* visit(root);
  }

  static int _endOf(DomNode node) {
    while (node is DomElement && node.children.isNotEmpty) {
      node = node.children.last;
    }
    return node.order + 1;
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
  ///
  /// It reads the parser's events into the DOM, with the checks that
  /// `XmlDocument.parse` makes: tags must nest and close, and the document
  /// must have one root element. So it accepts and rejects the documents
  /// that `XmlDocument.parse` does, with the same exceptions, and builds no
  /// tree of package:xml's nodes first.
  factory DomSection.parse(String source) {
    final DomElement root;
    try {
      root = _build(
        parseEvents(source, validateNesting: true, validateDocument: true),
      );
    } on _NotAnElementChild {
      // NOTE: package:xml's tree rejects these documents with its own
      // exception, which the events do not raise.
      XmlDocument.parse(source);
      throw StateError('package:xml accepted a declaration in an element.');
    }
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

  /// The body text node that holds the visible character that [visible]
  /// visible characters come before, from 0 to [visibleLength] − 1.
  DomText textHolding(int visible) {
    RangeError.checkValidIndex(visible, null, 'visible', visibleLength);
    // The last text node that starts at or before the character holds it,
    // because a node without visible characters starts where the next one
    // does.
    var low = 0;
    var high = texts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (texts[middle].visibleBefore <= visible) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return texts[low];
  }

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

/// The root element of the document whose events are [events].
///
/// The browser's DOM merges adjacent character data into one text node, as
/// `XmlDocument.parse` keeps adjacent text events apart. A CDATA section
/// stays its own node, which epub.js does not count. Comments, processing
/// instructions and everything outside the root leave no node, but a
/// comment or a processing instruction still keeps the texts around it
/// apart.
DomElement _build(Iterable<XmlEvent> events) {
  DomElement? root;
  final open = <DomElement>[];
  // For each open element, how many element and text children it has.
  final elementCounts = <int>[];
  final textCounts = <int>[];
  // The text of the text events since the last other event.
  String? pending;
  void flush() {
    final text = pending;
    if (text == null) return;
    pending = null;
    final parent = open.last;
    final index = textCounts.last;
    textCounts.last = index + 1;
    parent.children.add(DomText(text, index)..parent = parent);
  }

  for (final event in events) {
    switch (event) {
      case XmlTextEvent(:final value):
        if (open.isNotEmpty) {
          pending = pending == null ? value : pending! + value;
        }
        continue;
      case XmlStartElementEvent(:final localName, :final attributes):
        flush();
        final DomElement element;
        if (open.isEmpty) {
          element = DomElement(localName, {
            for (final attribute in attributes) attribute.name: attribute.value,
          }, 0);
          root ??= element;
        } else {
          final parent = open.last;
          final index = elementCounts.last;
          elementCounts.last = index + 1;
          element = DomElement(localName, {
            for (final attribute in attributes) attribute.name: attribute.value,
          }, index)..parent = parent;
          parent.children.add(element);
          parent.elements.add(element);
        }
        if (!event.isSelfClosing) {
          open.add(element);
          elementCounts.add(0);
          textCounts.add(0);
        }
      case XmlEndElementEvent():
        flush();
        open.removeLast();
        elementCounts.removeLast();
        textCounts.removeLast();
      case XmlCDATAEvent(:final value):
        flush();
        if (open.isNotEmpty) {
          open.last.children.add(DomText(value, -1)..parent = open.last);
        }
      case XmlDeclarationEvent() || XmlDoctypeEvent() when open.isNotEmpty:
        throw const _NotAnElementChild();
      default:
        flush();
    }
  }
  return root!;
}

/// An XML declaration or a document type inside an element, which an
/// element of package:xml's tree cannot hold.
class _NotAnElementChild {
  const _NotAnElementChild();
}
