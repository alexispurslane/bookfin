// Tool code: tests of the support report, which the corpus run lists.
// Nothing in lib/ uses the check.
import 'package:flutter_test/flutter_test.dart';

import 'book.dart';
import 'support.dart';

SupportReport check(String body, {String css = ''}) =>
    checkSupport(CorpusBook.open(madeUpEpub([body], css: css)));

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
