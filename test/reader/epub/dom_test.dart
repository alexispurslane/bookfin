import 'package:bookfin/reader/epub/dom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  group('a section parses into the DOM that package:xml\'s tree gives', () {
    // Each document is wrapped in an html root unless it starts with <.
    const documents = {
      'plain paragraphs': '<body><p>One</p><p>Two <i>three</i> four</p></body>',
      'a declaration, a doctype and comments around the root':
          '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n'
          '<!-- before --><html><body><p>Text</p></body></html>\n<!-- after -->',
      'entities and character references': '<body><p>Fish &amp; chips &lt;3 &#233;t&#xE9; &quot;q&quot;</p></body>',
      'a comment between two texts keeps them apart':
          '<body><p>before<!-- note -->after</p></body>',
      'a processing instruction between two texts keeps them apart':
          '<body><p>before<?pi data?>after</p></body>',
      'CDATA between texts is a node of its own':
          '<body><p>a<![CDATA[b < c]]>d</p></body>',
      'namespaced elements and attributes':
          '<body xmlns:epub="http://www.idpf.org/2007/ops">'
          '<section epub:type="chapter" xml:lang="en-GB"><epub:switch>'
          '<p>x</p></epub:switch></section></body>',
      'self-closing elements and empty elements':
          '<body><p>one<br/>two<br></br><img src="a.png" alt=""/></p></body>',
      'a repeated attribute keeps its last value':
          '<body><p class="a" class="b">x</p></body>',
      'white space between blocks': '<body>\n\t<p> x </p>\n\t<p>y</p>\n</body>',
      'a self-closing root': '<html/>',
    };
    for (final MapEntry(key: name, value: body) in documents.entries) {
      test(name, () {
        final source = body.startsWith('<?') || body.startsWith('<html')
            ? body
            : '<html>$body</html>';
        expect(_dump(DomSection.parse(source)), _treeDump(source));
      });
    }

    // Each of these fails to parse in package:xml's tree.
    const malformed = {
      'a tag that does not close': '<html><body><p>x</body></html>',
      'a closing tag that does not match': '<html><body><p>x</i></body></html>',
      'a closing tag with nothing open': '</p><html></html>',
      'two root elements': '<html></html><html></html>',
      'no root element': '<!-- nothing -->',
      'text outside the root': 'text<html></html>',
      'an unknown entity': '<html><body>&nbsp;</body></html>',
      'a doctype inside an element':
          '<html><body><!DOCTYPE html><p>x</p></body></html>',
      'a declaration inside an element':
          '<html><body><?xml version="1.0"?><p>x</p></body></html>',
      'a broken attribute': '<html><body><p class=a>x</p></body></html>',
    };
    for (final MapEntry(key: name, value: source) in malformed.entries) {
      test('$name is rejected with package:xml\'s exception', () {
        Object? treeError;
        try {
          XmlDocument.parse(source);
        } on Object catch (error) {
          treeError = error;
        }
        Object? error;
        try {
          DomSection.parse(source);
        } on Object catch (caught) {
          error = caught;
        }
        expect('$error', '$treeError');
        expect(error.runtimeType, treeError.runtimeType);
      });
    }
  });

  test('the visible characters before a place deep in a long text node are '
      'those of the nodes before it and of the text before the place', () {
    // Verse in one pre element: one text node of thousands of code units,
    // with spaces and newlines throughout.
    final verse = [
      for (var line = 0; line < 200; line++) 'I sing line  $line\n',
    ].join();
    final dom = DomSection.parse(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Title page</p>'
      '<pre>$verse</pre></body></html>',
    );
    final node = dom.texts.last;
    int counted(int end) => [
      for (var unit = 0; unit < end; unit++)
        if (!isSpace(verse.codeUnitAt(unit))) unit,
    ].length;
    for (final offset in [0, 1, 255, 256, 257, 511, 512, 2047, 3000]) {
      expect(
        dom.visibleBefore(EpubPlace(0, node.order, offset)),
        'Titlepage'.length + counted(offset),
        reason: 'offset $offset',
      );
    }
    expect(
      dom.visibleBefore(EpubPlace(0, node.order, verse.length)),
      dom.visibleLength,
    );
  });
}

/// Every node of [dom] with what layout and places read of it.
List<Object?> _dump(DomSection dom) {
  return [_node(dom.root), dom.body.order, dom.visibleLength];
}

List<Object?> _node(DomNode node) => switch (node) {
  DomText() => [
    'text',
    node.order,
    node.textIndex,
    node.text,
    node.parent?.order,
  ],
  DomElement() => [
    node.order,
    node.name,
    node.elementIndex,
    node.attributes,
    [for (final child in node.children) _node(child)],
    [for (final element in node.elements) element.order],
    node.parent?.order,
  ],
};

/// The dump of [source] as package:xml's tree gives it: the root element,
/// with adjacent text merged into one text node and CDATA as a node of its
/// own that has no text index, numbered in document order.
List<Object?> _treeDump(String source) {
  final document = XmlDocument.parse(source);
  var order = 0;
  var visible = 0;
  int? body;
  List<Object?> convert(XmlElement element, int index, int? parent) {
    final own = order++;
    if (element.name.local == 'body' && parent == 0) body ??= own;
    final children = <List<Object?>>[];
    final elements = <int>[];
    var texts = 0;
    for (final child in element.children) {
      if (child is XmlText) {
        if (children.isNotEmpty &&
            children.last.first == 'text' &&
            child.previousSibling is XmlText) {
          final last = children.removeLast();
          children.add([
            'text',
            last[1],
            last[2],
            '${last[3]}${child.value}',
            own,
          ]);
          continue;
        }
        children.add(['text', order++, texts++, child.value, own]);
      } else if (child is XmlCDATA) {
        children.add(['text', order++, -1, child.value, own]);
      } else if (child is XmlElement) {
        elements.add(order);
        children.add(convert(child, elements.length - 1, own));
      }
    }
    return [
      own,
      element.name.local,
      index,
      {
        for (final attribute in element.attributes)
          attribute.name.qualified: attribute.value,
      },
      children,
      elements,
      parent,
    ];
  }

  final root = convert(document.rootElement, 0, null);
  // The visible characters of the body's text nodes, or of the root's.
  void count(List<Object?> node, bool inside) {
    if (node.first == 'text') {
      if (inside) {
        final text = node[3]! as String;
        visible += visibleCount(text, 0, text.length);
      }
      return;
    }
    final children = node[4]! as List;
    final within = inside || node[0] == (body ?? 0);
    for (final child in children) {
      count(child as List<Object?>, within);
    }
  }

  count(root, false);
  return [root, body ?? 0, visible];
}
