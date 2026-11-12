import 'dart:convert';

import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../reader/publication_test.dart' show epub;

String _section(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Part</title></head>'
    '<body>$body</body></html>';

/// A book of [sections] in spine order, whose navigation lists [contents]:
/// (title, section index).
Publication book(
  List<String> sections, {
  List<(String, int)> contents = const [],
}) {
  final names = [
    for (var index = 0; index < sections.length; index++) 's$index',
  ];
  return Publication.admit(
    epub(
      extra: {
        'OPS/book.opf': utf8.encode(
          '<package version="3.0"><metadata/><manifest>'
          '${[for (final name in names) '<item id="$name" href="$name.xhtml" media-type="application/xhtml+xml"/>'].join()}'
          '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
          '</manifest><spine>'
          '${[for (final name in names) '<itemref idref="$name"/>'].join()}'
          '</spine></package>',
        ),
        for (final (index, body) in sections.indexed)
          'OPS/${names[index]}.xhtml': utf8.encode(_section(body)),
        'OPS/nav.xhtml': utf8.encode(
          '<html xmlns="http://www.w3.org/1999/xhtml" '
          'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
          '<nav epub:type="toc"><ol>'
          '${[for (final (title, index) in contents) '<li><a href="${names[index]}.xhtml">$title</a></li>'].join()}'
          '</ol></nav></body></html>',
        ),
      },
    ),
  );
}

void main() {
  test('each book word lies at its visible characters from the book start', () {
    final publication = book([
      '<h1>One</h1><p>Alice was beginning</p>',
      '<p>to get very\n tired</p>',
    ]);
    final words = bookWordsOf(publication);
    expect(words.words, [
      'one', 'alice', 'was', 'beginning', 'to', 'get', 'very', 'tired', //
    ]);
    // "OneAlicewasbeginning" holds 20 visible characters.
    expect(words.offsets, [0, 3, 8, 11, 20, 22, 25, 29]);
    // The text outline, which the book map agrees with, counts the same.
    expect(measureTextOutline(publication).parts.first.characters, 20);
  });

  test(
    'markup inside a word keeps it whole, and a new block starts a word',
    () {
      final words = bookWordsOf(
        book(['<p>be<i>gin</i>ning</p><p>end</p><div>start</div>']),
      );
      expect(words.words, ['beginning', 'end', 'start']);
    },
  );

  test('a dash between two words parts them and counts as a character', () {
    final words = bookWordsOf(book(['<p>was—the</p>']));
    expect(words.words, ['was', 'the']);
    expect(words.offsets, [0, 4]);
  });

  test('the back matter of the book is left out of its body', () {
    final words = bookWordsOf(
      book(
        [
          '<p>call me ishmael some years ago</p>',
          '<p>never mind how long precisely having little</p>',
          '<p>the end</p>',
          '<p>ishmael is quoted here</p>',
        ],
        contents: [
          ('Loomings', 0),
          ('Two', 1),
          ('Epilogue', 2),
          ('Endnotes', 3),
        ],
      ),
    );
    expect(words.words[words.bodyEnd], 'ishmael');
    expect(words.bodyEnd, 15);
  });

  test('a book without back matter searches every word', () {
    final words = bookWordsOf(book(['<p>call me ishmael</p>']));
    expect(words.bodyEnd, 3);
  });

  test('the word at a place is the first word that starts there or after', () {
    final words = bookWordsOf(book(['<p>Alice was beginning</p>']));
    // "Alice" starts at 0, "was" at 5 and "beginning" at 8.
    expect(words.wordAt(0), 0);
    expect(words.wordAt(5), 1);
    expect(words.wordAt(6), 2);
    expect(words.wordAt(1000), 2);
  });
}
