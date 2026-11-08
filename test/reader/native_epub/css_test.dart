import 'package:bookfin/reader/native_epub/css.dart';
import 'package:bookfin/reader/native_epub/dom.dart';
import 'package:bookfin/reader/native_epub/layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The computed style of the element with id [id] in [body] under [css].
Style styleOf(String id, String body, String css) {
  final prepared = styleSection(section(body, css: css), const PageTheme());
  return prepared.styles.entries
      .firstWhere((entry) => entry.key.id == id)
      .value;
}

void main() {
  test('a later rule of equal specificity wins over an earlier one', () {
    final style = styleOf(
      'x',
      '<p id="x">A</p>',
      'p{text-align:center} p{text-align:right}',
    );
    expect(style.textAlign, Align.right);
  });

  test('an id selector wins over a class selector that comes later', () {
    final style = styleOf(
      'x',
      '<p id="x" class="c">A</p>',
      '#x{text-align:center} .c{text-align:right}',
    );
    expect(style.textAlign, Align.center);
  });

  test('an important rule wins over the style attribute', () {
    final style = styleOf(
      'x',
      '<p id="x" style="text-indent:3em">A</p>',
      'p{text-indent:1em!important}',
    );
    expect(style.textIndent.value, 20);
  });

  test('em lengths follow the element own size and rem the root size', () {
    final style = styleOf(
      'x',
      '<p id="x">A</p>',
      'p{font-size:1.5em;margin-top:2em;margin-bottom:1rem}',
    );
    // The reader sets the body to 20 pixels. The root stays at 16.
    expect(style.fontSize, 30);
    expect(style.margin[0].value, 60);
    expect(style.margin[2].value, 16);
  });

  test('child, adjacent and general sibling combinators match', () {
    const body =
        '<section><h2>T</h2><p id="a">A</p><p id="b">B</p></section>'
        '<div><p id="c">C</p></div>';
    const css =
        'section>p{text-indent:1em} h2+p{text-indent:0}'
        ' h2~p{text-align:center}';
    expect(styleOf('a', body, css).textIndent.value, 0);
    expect(styleOf('b', body, css).textIndent.value, 20);
    expect(styleOf('b', body, css).textAlign, Align.center);
    expect(styleOf('c', body, css).textIndent.value, 0);
  });

  test('pseudo-classes and namespaced attributes match', () {
    const body =
        '<div><p id="a">A</p><p id="b" epub:type="z3998:poem title">B</p>'
        '</div>';
    const css =
        'p:first-child{text-align:center} p:not(:first-child){text-align:right}'
        ' [epub|type~="title"]{font-weight:bold}';
    expect(styleOf('a', body, css).textAlign, Align.center);
    expect(styleOf('b', body, css).textAlign, Align.right);
    expect(styleOf('b', body, css).fontWeight, 700);
  });

  test('a rule whose selector list has an invalid selector is dropped', () {
    final style = styleOf(
      'x',
      '<p id="x">A</p>',
      'p, p:unknown-thing{text-align:center}',
    );
    expect(style.textAlign, Align.start);
  });

  test('print rules do not apply and screen rules do', () {
    final style = styleOf(
      'x',
      '<p id="x">A</p>',
      '@media print{p{text-align:center}} @media screen{p{font-style:italic}}',
    );
    expect(style.textAlign, Align.start);
    expect(style.italic, isTrue);
  });

  test('inherited properties pass to children and margins do not', () {
    final style = styleOf(
      'x',
      '<blockquote><em id="x">A</em></blockquote>',
      'blockquote{text-align:justify}',
    );
    expect(style.textAlign, Align.justify);
    expect(style.italic, isTrue);
    expect(style.margin[3].value, 0);
  });

  test('the user agent sheet gives headings their size and weight', () {
    final style = styleOf('x', '<h2 id="x">T</h2>', '');
    expect(style.fontSize, 30);
    expect(style.fontWeight, 700);
    expect(style.display, Display.block);
  });

  test('a page-break property names the same break as break-before', () {
    final style = styleOf(
      'x',
      '<div id="x">A</div>',
      'div{page-break-before:always}',
    );
    expect(style.breakBefore, BreakRule.page);
  });

  test('all: inherit copies every property from the parent', () {
    final style = styleOf(
      'x',
      '<div class="box"><div id="x">A</div></div>',
      '.box{margin-left:2em} #x{all:inherit;font-weight:bold}',
    );
    expect(style.margin[3].value, 40);
    expect(style.fontWeight, 700);
  });

  test('all: initial resets the size and the display', () {
    final style = styleOf('x', '<div id="x">A</div>', '#x{all:initial}');
    expect(style.fontSize, 16);
    expect(style.display, Display.inline);
  });

  test('the DOM counts element and text children as epub.js does', () {
    final dom = DomSection.parse(
      '<html><head/><body><p>One <b>two</b> three</p></body></html>',
    );
    final paragraph = dom.body.elements.single;
    final texts = paragraph.children.whereType<DomText>().toList();
    expect([for (final text in texts) text.textIndex], [0, 1]);
    expect(paragraph.elements.single.elementIndex, 0);
    expect(dom.visibleLength, 'Onetwothree'.length);
  });
}
