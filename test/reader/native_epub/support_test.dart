import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/native_epub/book.dart';
import 'package:bookfin/reader/native_epub/support.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a book with a table of rows needs the WebView reader', () {
    final report = check('<table><tr><td>A</td><td>B</td></tr></table>');
    expect(report.unsupported.keys, contains('tables'));
    expect(report.supportedSections, 0);
  });

  test('vertical writing needs the WebView reader', () {
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
