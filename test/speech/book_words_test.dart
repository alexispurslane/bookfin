import 'dart:convert';

import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../reader/publication_test.dart' show epub;
import '../reader/section_publication.dart';
import '../reader/session_native_test.dart' show navBook;

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

BookWords wordsOf(Publication publication) =>
    bookWordsOf(publication, measureTextOutline(publication));

void main() {
  test('missing section bytes add no speech words or visible characters', () {
    final source = book(['<p>one</p>', '<p>two</p>']);
    final outline = measureTextOutline(source);
    final publication = SectionPublication(
      source,
      source.textFiles,
      spine: [source.spine.first, 'missing.xhtml', source.spine.last],
    );
    final words = bookWordsOf(publication, outline);
    expect(words.words, ['one', 'two']);
    expect(words.offsets, [0, 3]);
  });

  test('a malformed middle section keeps the offsets before and after it', () {
    final source = book(['<p>one</p>', '<p>discard</p>', '<p>two</p>']);
    final publication = SectionPublication(source, {
      ...source.textFiles,
      source.spine[1]: utf8.encode('<body><p>discard words</p><broken'),
    });
    final words = wordsOf(publication);
    expect(words.words, ['one', 'two']);
    expect(words.offsets, [0, 3]);
  });

  final cases =
      <
        ({
          String name,
          String xml,
          List<String> words,
          List<int> offsets,
          int count,
          int? target,
        })
      >[
        (
          name: 'UTF-16 surrogate pairs, combining marks and spoken numbers',
          xml: _section('<p>A😀 B𝄞 c&#x301; 42</p><p id="target">end</p>'),
          words: ['a', 'b', 'c', 'forty', 'two', 'end'],
          offsets: [0, 3, 6, 8, 8, 10],
          count: 13,
          target: 10,
        ),
        (
          name: 'every whitespace unit',
          xml: _section(
            '<p>one\t\n\r\u000b\u000c \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff</p><p id="target">two</p>',
          ),
          words: ['one', 'two'],
          offsets: [0, 3],
          count: 6,
          target: 3,
        ),
        (
          name: 'entities and supplementary characters',
          xml: _section(
            '<p>one&amp;two &#x1F600; three</p><p id="target">end</p>',
          ),
          words: ['onetwo', 'three', 'end'],
          offsets: [0, 9, 14],
          count: 17,
          target: 14,
        ),
        (
          name: 'CDATA and inline markup inside a word',
          xml: _section(
            '<p>be<![CDATA[gin]]><i>ning</i></p><p id="target">end</p>',
          ),
          words: ['beginning', 'end'],
          offsets: [0, 9],
          count: 12,
          target: 9,
        ),
        (
          name: 'dashes, ellipsis and a normalized number',
          xml: _section('<p>one—two–three…42</p><p id="target">end</p>'),
          words: ['one', 'two', 'three', 'forty', 'two', 'end'],
          offsets: [0, 4, 8, 14, 14, 16],
          count: 19,
          target: 16,
        ),
        (
          name: 'empty sections and empty IDs',
          xml: _section('<p id="target"/>'),
          words: [],
          offsets: [],
          count: 0,
          target: 0,
        ),
        (
          name: 'first ID wins, including before the body, and text after body counts',
          xml: '<html><head id="target">ignored</head><body><p>one</p><p id="target">two</p></body><tail>three</tail></html>',
          words: ['one', 'two', 'three'],
          offsets: [0, 3, 6],
          count: 11,
          target: 0,
        ),
        (
          name: 'body events count hidden text without a CSS visibility rule',
          xml: _section(
            '<p hidden="hidden">one</p><p style="display:none">two</p><p id="target">three</p>',
          ),
          words: ['one', 'two', 'three'],
          offsets: [0, 3, 6],
          count: 11,
          target: 6,
        ),
        (
          name: 'no body gives no text but still records IDs',
          xml: '<html><head><title id="target">ignored</title></head></html>',
          words: [],
          offsets: [],
          count: 0,
          target: 0,
        ),
        (
          name: 'a malformed section rolls back words, characters and IDs',
          xml: '<html><body><p id="target">discard these words</p><broken',
          words: [],
          offsets: [],
          count: 0,
          target: null,
        ),
      ];
  for (final c in cases) {
    test('speech and outline offsets agree for ${c.name}', () {
      final admitted = Publication.admit(
        navBook(
          ['<p>placeholder</p>', '<p>after</p>'],
          [('Target', 'text/s0.xhtml#target')],
        ),
      );
      final bytes = utf8.encode(c.xml);
      final publication = SectionPublication(admitted, {
        ...admitted.textFiles,
        admitted.spine.first: bytes,
      });
      final counted = countSection(bytes, {'target', 'missing'});
      expect(counted.visible, c.count);
      expect(counted.before, {if (c.target != null) 'target': c.target});
      final outline = measureTextOutline(publication);
      expect(outline.parts.map((p) => p.characters), [c.count, 5]);
      expect(outline.entries.single.start, c.target ?? 0);
      final words = wordsOf(publication);
      expect(words.words, [...c.words, 'after']);
      expect(words.offsets, [...c.offsets, c.count]);
    });
  }

  test('each book word lies at its visible characters from the book start', () {
    final publication = book([
      '<h1>One</h1><p>Alice was beginning</p>',
      '<p>to get very\n tired</p>',
    ]);
    final words = wordsOf(publication);
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
      final words = wordsOf(
        book(['<p>be<i>gin</i>ning</p><p>end</p><div>start</div>']),
      );
      expect(words.words, ['beginning', 'end', 'start']);
    },
  );

  test('a dash between two words parts them and counts as a character', () {
    final words = wordsOf(book(['<p>was—the</p>']));
    expect(words.words, ['was', 'the']);
    expect(words.offsets, [0, 4]);
  });

  test('the back matter of the book is left out of its body', () {
    final words = wordsOf(
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
    final words = wordsOf(book(['<p>call me ishmael</p>']));
    expect(words.bodyEnd, 3);
  });

  test('the word at a place is the first word that starts there or after', () {
    final words = wordsOf(book(['<p>Alice was beginning</p>']));
    // "Alice" starts at 0, "was" at 5 and "beginning" at 8.
    expect(words.wordAt(0), 0);
    expect(words.wordAt(5), 1);
    expect(words.wordAt(6), 2);
    expect(words.wordAt(1000), 2);
  });
}
