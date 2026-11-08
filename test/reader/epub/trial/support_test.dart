// Tool code: tests of the trial's support check, which the corpus run
// reports. Nothing in lib/ uses the check.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';
import 'support.dart';

/// A one-section EPUB whose body is [body] and whose style sheet is [css].
Uint8List epub(String body, {String css = ''}) {
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles>'
            '</container>',
      ),
    )
    ..add(
      ArchiveFile.string(
        'book.opf',
        '<package version="3.0"><metadata/><manifest>'
            '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="css" href="book.css" media-type="text/css"/>'
            '</manifest><spine><itemref idref="one"/></spine></package>',
      ),
    )
    ..add(ArchiveFile.string('book.css', css))
    ..add(
      ArchiveFile.string(
        'one.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
            '<link rel="stylesheet" href="book.css"/></head>'
            '<body>$body</body></html>',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

SupportReport check(String body, {String css = ''}) =>
    checkSupport(TrialBook.open(epub(body, css: css)));

void main() {
  test('a plain prose book passes the support check', () {
    final report = check(
      '<h1>One</h1><p>Prose with <em>emphasis</em>.</p><hr/>'
      '<blockquote><p>A quote.</p></blockquote>',
      css: 'p{text-indent:1em;margin:0} h1{text-align:center}',
    );
    expect(report.supported, isTrue);
    expect(report.supportedSections, 1);
  });

  test('a table of rows passes, and a rowspan is an approximation', () {
    final report = check(
      '<table><tr><td rowspan="2">A</td><td>B</td></tr>'
      '<tr><td>C</td></tr></table>',
    );
    expect(report.supported, isTrue);
    expect(report.approximated.keys, contains('rowspan counted as 1'));
  });

  test('a flex row and a grid are drawn as blocks', () {
    final report = check(
      '<div class="row"><p>A</p></div><div class="grid"><p>B</p></div>',
      css: '.row{display:flex}.grid{display:grid}',
    );
    expect(report.supported, isTrue);
    expect(
      report.approximated.keys,
      containsAll(['a flex row drawn as blocks', 'a grid drawn as blocks']),
    );
  });

  test('vertical writing is a feature that the renderer does not support', () {
    final report = check('<p>Text</p>', css: 'p{writing-mode:vertical-rl}');
    expect(report.unsupported.keys, contains('vertical writing'));
  });

  test('a rule that matches no element does not count', () {
    final report = check(
      '<p>Text</p>',
      css: '.missing{position:absolute;left:10px}',
    );
    expect(report.supported, isTrue);
  });

  test('text moved off the page is an approximation, not a failure', () {
    final report = check(
      '<h1 class="hidden">Title</h1><p>Text</p>',
      css: '.hidden{position:absolute;left:-999em}',
    );
    expect(report.supported, isTrue);
    expect(
      report.approximated.keys,
      contains('text moved off the page is left out'),
    );
  });

  test('a drop cap is drawn as plain text and reported', () {
    final report = check('<p>Text</p>', css: 'p::first-letter{font-size:3em}');
    expect(report.supported, isTrue);
    expect(
      report.approximated.keys,
      contains('::first-letter and ::first-line'),
    );
  });
}
