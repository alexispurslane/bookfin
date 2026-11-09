import 'dart:io';

import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The computed style of the element with id [id] in [body] under [css].
Style styleOf(String id, String body, String css) {
  final source = section(body, css: css);
  final (:styles, faces: _) = styleSection(
    source,
    DomSection.parse(source.xhtml),
    readerPage,
  );
  return styles.entries.firstWhere((entry) => entry.key.id == id).value;
}

/// The computed style of each element with an id in [body], in a section at
/// `epub/text/one.xhtml` whose head links the sheet at [link]. [sheets]
/// holds the book's style sheets by publication path.
Map<String, Style> linkedStyles(
  String body, {
  required String link,
  required Map<String, String> sheets,
  PageSettings settings = readerPage,
}) {
  final source = SectionSource(
    index: 0,
    path: 'epub/text/one.xhtml',
    xhtml:
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
        '<link href="$link" rel="stylesheet" type="text/css"/></head>'
        '<body>$body</body></html>',
    fontPrefix: testFontPrefix,
    styleSheets: sheets,
  );
  final (:styles, faces: _) = styleSection(
    source,
    DomSection.parse(source.xhtml),
    settings,
  );
  return {
    for (final MapEntry(key: element, value: style) in styles.entries)
      ?element.id: style,
  };
}

/// The style of [id] in `<p id="x">A</p>`, styled by the sheet
/// `epub/css/main.css` among [sheets].
Style mainStyle(Map<String, String> sheets, {PageSettings? settings}) =>
    linkedStyles(
      '<p id="x">A</p>',
      link: '../css/main.css',
      sheets: sheets,
      settings: settings ?? readerPage,
    )['x']!;

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

  group('table borders', () {
    const tables =
        '<table id="one"><tr><td id="cell">A</td></tr></table>'
        '<table id="two"><tr><td>B</td></tr></table>'
        '<table id="plain"><tr><td>C</td></tr></table>'
        '<table id="bad"><tr><td>D</td></tr></table>';

    test('border-spacing takes one length for both directions, or one '
        'across and one down, and cells inherit it', () {
      const css =
          '#one{border-spacing:0.5em;font-size:12px}'
          '#two{border-spacing:4px 10px}';
      expect(styleOf('one', tables, css).borderSpacing, (6.0, 6.0));
      expect(styleOf('cell', tables, css).borderSpacing, (6.0, 6.0));
      expect(styleOf('two', tables, css).borderSpacing, (4.0, 10.0));
    });

    test('a table has Chromium\'s border-spacing of 2 pixels unless a rule '
        'sets one, and a negative or percentage spacing is ignored', () {
      const css = '#bad{border-spacing:-3px}#bad{border-spacing:10%}';
      expect(styleOf('plain', tables, css).borderSpacing, (2.0, 2.0));
      expect(styleOf('bad', tables, css).borderSpacing, (2.0, 2.0));
    });

    test('a table separates its borders unless border-collapse collapses '
        'them, and its cells inherit the choice', () {
      const css =
          '#one{border-collapse:collapse}#two{border-collapse:separate}';
      expect(styleOf('one', tables, css).collapseBorders, isTrue);
      expect(styleOf('cell', tables, css).collapseBorders, isTrue);
      expect(styleOf('two', tables, css).collapseBorders, isFalse);
      expect(styleOf('plain', tables, css).collapseBorders, isFalse);
    });
  });

  test('the user agent sheet gives headings their size and weight', () {
    final style = styleOf('x', '<h2 id="x">T</h2>', '');
    expect(style.fontSize, 30);
    expect(style.fontWeight, 700);
    expect(style.display, Display.block);
  });

  test('a book rule beats a user agent rule of higher specificity', () {
    // The user agent sets `section h1 { font-size: 1.5em }`.
    final style = styleOf(
      'x',
      '<section><h1 id="x">T</h1></section>',
      'h1{font-size:1.4em;margin:1.5em 0 1em}',
    );
    expect(style.fontSize, closeTo(28, 1e-9));
    expect(style.margin[0].value, closeTo(42, 1e-9));
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

  test('a Standard Ebooks core.css sets small caps headings and hanging '
      'verse indents', () {
    final styles = linkedStyles(
      '<section epub:type="chapter"><h2 id="heading">I</h2>'
      '<p id="opening">Text</p>'
      '<blockquote epub:type="z3998:poem"><p><span id="line">A line</span>'
      '<br/><span id="indented" class="i1">Indented</span></p></blockquote>'
      '</section>',
      link: '../css/core.css',
      sheets: {
        'epub/css/core.css': File('test/reader/epub/fixtures/se-core.css')
            .readAsStringSync(),
      },
    );
    expect(styles['heading']!.smallCaps, isTrue);
    expect(styles['heading']!.textAlign, Align.center);
    expect(styles['opening']!.textIndent.value, 0);
    // The reader's text is 20 pixels, so 1em is 20 pixels.
    expect(styles['line']!.display, Display.block);
    expect(styles['line']!.padding[3].value, 20);
    expect(styles['line']!.textIndent.value, -20);
    expect(styles['indented']!.padding[3].value, 40);
    expect(styles['indented']!.textIndent.value, -20);
  });

  test('an imported sheet applies before the rules of the sheet that '
      'imports it', () {
    final style = mainStyle({
      'epub/css/main.css':
          '@import url("parts/verse.css"); p{text-align:center}',
      'epub/css/parts/verse.css': 'p{font-style:italic;text-align:right}',
    });
    expect(style.italic, isTrue);
    expect(style.textAlign, Align.center);
  });

  test('an import resolves against the sheet that names it', () {
    final style = mainStyle({
      'epub/css/main.css': "@import 'parts/one.css';",
      'epub/css/parts/one.css': '@import "two.css";',
      'epub/css/parts/two.css': 'p{font-style:italic}',
    });
    expect(style.italic, isTrue);
  });

  test('a remote import or one outside the publication does nothing', () {
    final style = mainStyle({
      'epub/css/main.css':
          '@import url("https://example.com/remote.css");'
          '@import url(../../../outside.css);'
          '@import "data:text/css,p{text-align:center}";'
          '@import "missing.css";',
      'outside.css': 'p{text-align:right}',
    });
    expect(style.textAlign, Align.start);
  });

  test('an import with a media query applies only when the query holds', () {
    final style = mainStyle({
      'epub/css/main.css':
          '@import "print.css" print; @import "screen.css" screen;',
      'epub/css/print.css': 'p{text-align:center}',
      'epub/css/screen.css': 'p{font-style:italic}',
    });
    expect(style.textAlign, Align.start);
    expect(style.italic, isTrue);
  });

  test('an import after a style rule is ignored, as Chromium ignores it', () {
    final style = mainStyle({
      'epub/css/main.css': 'p{font-weight:bold} @import "late.css";',
      'epub/css/late.css': 'p{font-style:italic}',
    });
    expect(style.fontWeight, 700);
    expect(style.italic, isFalse);
  });

  test('imports reach four sheets deep and no further', () {
    final style = mainStyle({
      'epub/css/main.css': '@import "one.css";',
      'epub/css/one.css': '@import "two.css"; p{font-style:italic}',
      'epub/css/two.css': '@import "three.css"; p{text-align:center}',
      'epub/css/three.css': '@import "four.css"; p{font-weight:bold}',
      'epub/css/four.css': '@import "five.css"; p{text-indent:2em}',
      'epub/css/five.css': 'p{letter-spacing:3px}',
    });
    expect(style.italic, isTrue);
    expect(style.textAlign, Align.center);
    expect(style.fontWeight, 700);
    expect(style.textIndent.value, 40);
    expect(style.letterSpacing, 0);
  });

  test('a sheet that is imported twice applies once', () {
    final style = mainStyle({
      'epub/css/main.css':
          '@import "right.css"; @import "center.css"; @import "right.css";',
      'epub/css/right.css': 'p{text-align:right}',
      'epub/css/center.css': '@import "main.css"; p{text-align:center}',
    });
    expect(style.textAlign, Align.center);
  });

  test('dark color scheme rules apply only on night pages', () {
    const css =
        '@media (prefers-color-scheme: dark){p{text-align:center}}'
        '@media (prefers-color-scheme: light){p{font-style:italic}}';
    final cream = mainStyle({'epub/css/main.css': css});
    final night = mainStyle(
      {'epub/css/main.css': css},
      settings: const PageSettings(
        width: 412,
        height: 671,
        fontSize: 20,
        night: true,
      ),
    );
    expect((cream.textAlign, cream.italic), (Align.start, true));
    expect((night.textAlign, night.italic), (Align.center, false));
  });

  test('a font face names its family, its first supported publication '
      'file, its weight and its style', () {
    final sheet = StyleSheet.parse(
      '@font-face{font-family:"Old Face";'
      'src:url("../fonts/old.woff2") format("woff2"),'
      ' url("../fonts/old.woff") format("woff");'
      'font-weight:bold;font-style:italic}'
      '@font-face{font-family:Plain;src:local("Plain"),'
      ' url(https://example.com/plain.ttf), url(../fonts/plain.otf.woff2),'
      ' url(../fonts/plain.ttf)}'
      '@font-face{font-family:Remote;src:url(https://example.com/r.ttf)}'
      '@font-face{src:url(../fonts/nameless.ttf)}'
      '@media print{@font-face{font-family:Paper;src:url(../fonts/p.ttf)}}',
      path: 'epub/css/fonts.css',
    );
    expect(sheet.fontFaces, const [
      FontFaceRule(
        family: 'old face',
        path: 'epub/fonts/old.woff',
        weight: 700,
        italic: true,
      ),
      FontFaceRule(family: 'plain', path: 'epub/fonts/plain.ttf'),
    ]);
  });

  test('an imported sheet brings its font faces', () {
    final source = SectionSource(
      index: 0,
      path: 'epub/text/one.xhtml',
      xhtml:
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
          '<link href="../css/main.css" rel="stylesheet"/></head>'
          '<body><p>A</p></body></html>',
      fontPrefix: testFontPrefix,
      styleSheets: {
        'epub/css/main.css': '@import "fonts/faces.css";',
        'epub/css/fonts/faces.css':
            '@font-face{font-family:Book;src:url(book.ttf)}',
      },
    );
    final (styles: _, :faces) = styleSection(
      source,
      DomSection.parse(source.xhtml),
      readerPage,
    );
    expect(faces, const [
      FontFaceRule(family: 'book', path: 'epub/css/fonts/book.ttf'),
    ]);
  });

  test('a sheet keeps its first 20,000 rules', () {
    final css = [for (var index = 0; index <= 20000; index++) '.c$index{}'];
    final sheet = StyleSheet.parse(css.join());
    expect(sheet.rules.length, 20000);
    expect(sheet.rules.last.selector.compounds.single.classes, ['c19999']);
  });

  test('a selector longer than 1,024 characters ends the sheet', () {
    final longest = '.${'x' * 1023}';
    final sheet = StyleSheet.parse('p{} $longest{} .${'y' * 1024}{} q{}');
    expect(
      [for (final rule in sheet.rules) rule.selector.compounds.single.tag],
      ['p', null],
    );
  });

  test('blocks nested deeper than 32 end the sheet', () {
    String nested(int depth, String rule) =>
        '${'@media screen{' * depth}$rule${'}' * depth}';
    final sheet = StyleSheet.parse(
      'p{} ${nested(31, 'q{}')} ${nested(32, 'b{}')} i{}',
    );
    expect(
      [for (final rule in sheet.rules) rule.selector.compounds.single.tag],
      ['p', 'q'],
    );
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
