import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry entry(
  String id, {
  String title = 'The Orchard',
  String type = 'AudioBook',
  int track = 1,
  int disc = 1,
  String? isbn,
  String source = 'source',
  String? modified = '2026-01-01',
  String container = 'm4b',
  Map<String, dynamic> fields = const {},
}) => CatalogEntry.fromJson({
  'Id': id,
  'Name': title,
  'Type': type,
  'Album': 'The Orchard',
  'AlbumArtist': 'A. Writer',
  'Artists': ['A. Writer'],
  'IndexNumber': track,
  'ParentIndexNumber': disc,
  'RunTimeTicks': 900000000,
  'DateModified': modified,
  'ProviderIds': {'Isbn': ?isbn},
  'MediaSources': [
    {
      'Id': source,
      'Container': container,
      'Size': 1000,
      'RunTimeTicks': 900000000,
    },
  ],
  'Chapters': [
    {'Name': 'Opening', 'StartPositionTicks': 15000000},
  ],
  ...fields,
}, libraryId: 'books');

void main() {
  test('one M4B remains one audio edition with chapter ranges', () {
    final book = buildBooks([entry('one')]).single;
    expect(book.title, 'The Orchard');
    expect(book.editions.single.files.single.itemId, 'one');
    expect(book.editions.single.files.single.chapters.single.startMs, 1500);
    expect(book.editions.single.files.single.durationMs, 90000);
  });

  test('identical titles and folder metadata never merge recordings', () {
    final books = buildBooks([entry('first'), entry('second')]);
    expect(books, hasLength(2));
    expect(possibleMatches(books.first, books).single.id, books.last.id);
  });

  test(
    'possible ebook matches require confirmation even with the same ISBN',
    () {
      final entries = [
        entry('audio', isbn: '978-1'),
        entry('ebook', type: 'Book', isbn: '978-1', container: 'epub'),
      ];
      final separate = buildBooks(entries);
      expect(separate, hasLength(2));
      expect(possibleMatches(separate.first, separate), hasLength(1));
      final paired = buildBooks(
        entries,
        edits: CatalogEdits(bookLinks: {'ebook:source': 'book:audio'}),
      );
      expect(paired, hasLength(1));
      expect(
        paired.single.editions.map((edition) => edition.kind),
        containsAll([EditionKind.audio, EditionKind.text]),
      );
    },
  );

  test('confirmed files of one recording use disc then track order', () {
    final entries = [
      entry('third', track: 1, disc: 2),
      entry('second', track: 2),
      entry('first'),
    ];
    final books = buildBooks(
      entries,
      edits: CatalogEdits(
        bookLinks: {
          'third:source': 'book:first',
          'second:source': 'book:first',
        },
        recordingLinks: {
          'third:source': 'first:source',
          'second:source': 'first:source',
        },
      ),
    );
    expect(books.single.editions.single.files.map((file) => file.itemId), [
      'first',
      'second',
      'third',
    ]);
    expect(
      books.single.editions.single.memberIds,
      containsAll(['first:source', 'second:source', 'third:source']),
    );
  });

  test('a confirmed file order overrides misleading source track numbers', () {
    final books = buildBooks(
      [entry('first'), entry('second', track: 2)],
      edits: CatalogEdits(
        bookLinks: {'second:source': 'book:first'},
        recordingLinks: {'second:source': 'first:source'},
        fileOrders: {
          'first:source': ['second:source', 'first:source'],
        },
      ),
    );
    expect(books.single.editions.single.files.first.itemId, 'second');
  });

  test(
    'alternate media sources remain separate editions, never consecutive files',
    () {
      final item = entry(
        'one',
        fields: {
          'MediaSources': [
            {'Id': 'abridged', 'Container': 'm4b'},
            {'Id': 'full', 'Container': 'm4b'},
          ],
        },
      );
      final book = buildBooks([item]).single;
      expect(book.editions, hasLength(2));
      expect(
        book.editions.every((edition) => edition.files.length == 1),
        isTrue,
      );
    },
  );

  test('explicit series order retains fractional side stories and ignores series fields on plain audio files', () {
    final first = entry(
      'one',
      type: 'Audio',
      fields: {'SeriesName': 'Not a book series'},
    );
    expect(buildBooks([first]).single.series, isNull);
    final books = buildBooks(
      [first, entry('two')],
      edits: CatalogEdits(
        details: {
          'book:one': const BookDetails(
            title: 'Side story',
            author: 'Writer',
            series: 'Orchard',
            seriesOrder: 1.5,
          ),
          'book:two': const BookDetails(
            title: 'Second',
            author: 'Writer',
            series: 'Orchard',
            seriesOrder: 2,
          ),
        },
      ),
    );
    expect(books.map((book) => book.seriesOrder), containsAll([1.5, 2]));
  });

  test('books and audiobooks take their series from Jellyfin', () {
    final books = buildBooks([
      entry(
        'ebook',
        title: 'Graft',
        type: 'Book',
        container: 'epub',
        fields: {'SeriesName': 'The Orchard Cycle', 'IndexNumber': 2},
      ),
      entry(
        'audio',
        title: 'First Frost',
        fields: {'SeriesName': 'The Orchard Cycle'},
      ),
    ]);
    final graft = books.singleWhere((book) => book.title == 'Graft');
    final frost = books.singleWhere((book) => book.title == 'First Frost');
    expect(graft.series, 'The Orchard Cycle');
    expect(graft.seriesOrder, 2);
    expect(frost.series, 'The Orchard Cycle');
  });

  CatalogEntry seriesEntry(
    String id, {
    String title = 'Graft',
    String type = 'AudioBook',
    String series = 'The Orchard Cycle',
    int? index,
  }) => entry(
    id,
    title: title,
    type: type,
    container: type == 'Book' ? 'epub' : 'm4b',
    fields: {'SeriesName': series, 'IndexNumber': ?index},
  );

  test(
    'an audiobook and an ebook with the same title in one series are one book',
    () {
      final books = buildBooks([
        seriesEntry('audio'),
        seriesEntry('ebook', type: 'Book', index: 2),
        seriesEntry('other', title: 'Windfall', type: 'Book', index: 3),
      ]);
      expect(books, hasLength(2));
      final graft = books.singleWhere((book) => book.title == 'Graft');
      expect(graft.editions.map((edition) => edition.kind), {
        EditionKind.audio,
        EditionKind.text,
      });
      expect(graft.seriesOrder, 2, reason: 'the ebook supplies the position');
    },
  );

  test('same-titled editions outside a series still wait for confirmation', () {
    final books = buildBooks([
      entry('audio'),
      entry('ebook', type: 'Book', container: 'epub'),
    ]);
    expect(books, hasLength(2));
  });

  test('same-titled editions in different series stay separate', () {
    final books = buildBooks([
      seriesEntry('audio'),
      seriesEntry('ebook', type: 'Book', series: 'Another Cycle'),
    ]);
    expect(books, hasLength(2));
  });

  test(
    'two recordings of one title in a series are never merged automatically',
    () {
      final books = buildBooks([
        seriesEntry('first'),
        seriesEntry('second'),
        seriesEntry('ebook', type: 'Book'),
      ]);
      expect(books, hasLength(3));
    },
  );

  test('a separated ebook stays separate from its same-titled audiobook', () {
    final books = buildBooks(
      [seriesEntry('audio'), seriesEntry('ebook', type: 'Book')],
      edits: CatalogEdits(
        bookLinks: {'ebook:source': 'book:edition:ebook:source'},
      ),
    );
    expect(books, hasLength(2));
  });

  test('a book in one Jellyfin collection belongs to that series', () {
    final book = buildBooks([
      entry(
        'crown',
        title: 'A Crown of Swords',
        fields: {
          'IndexNumber': 7,
          'BookfinCollections': ['The Wheel of Time'],
        },
      ),
    ]).single;
    expect(book.series, 'The Wheel of Time');
    expect(book.seriesOrder, 7, reason: 'the item number orders a collection');
  });

  test('a title ending in (Series #N) names the series and its position', () {
    final book = buildBooks([
      entry('crown', title: 'A Crown of Swords (The Wheel of Time #7)'),
    ]).single;
    expect(book.title, 'A Crown of Swords');
    expect(book.series, 'The Wheel of Time');
    expect(book.seriesOrder, 7);
  });

  test('a title number wins over the item number for the position', () {
    final book = buildBooks([
      entry(
        'egg',
        title: "Cuckoo's Egg (The Age of Exploration #5)",
        fields: {
          'IndexNumber': 1,
          'BookfinCollections': ['Alliance-Union'],
        },
      ),
    ]).single;
    expect(book.series, 'Alliance-Union', reason: 'the collection is explicit');
    expect(book.seriesOrder, 5);
    expect(book.title, "Cuckoo's Egg");
  });

  test('a book in two collections takes its series from neither', () {
    final book = buildBooks([
      entry(
        'one',
        title: 'Mort (Discworld #4)',
        fields: {
          'BookfinCollections': ['Discworld', 'Favourites'],
        },
      ),
    ]).single;
    expect(book.series, 'Discworld', reason: 'the title still names it');
  });

  group('a (Series #N) part with text after it', () {
    Map<String, dynamic> writtenBy(String author) => {
      'People': [
        {'Name': author, 'Type': 'Author'},
        {'Name': 'Narrator Person', 'Type': 'Narrator'},
      ],
    };

    test('names the series, its position, and the plain title', () {
      final book = buildBooks([
        entry(
          'queen',
          title:
              '2.6 Sun Eater Series - Queen Amid Ashes (The Sun Eater #4.5) '
              'by Christopher Ruocchio',
          fields: writtenBy('Christopher Ruocchio'),
        ),
      ]).single;
      expect(book.series, 'The Sun Eater');
      expect(book.seriesOrder, 4.5);
      expect(book.title, 'Queen Amid Ashes');
    });

    test('keeps a fractional side story between its neighbors', () {
      final books = buildBooks([
        entry(
          'kingdoms',
          title: 'Kingdoms of Death (The Sun Eater #4) by Christopher Ruocchio',
          fields: writtenBy('Christopher Ruocchio'),
        ),
        entry(
          'queen',
          title:
              '2.6 Sun Eater Series - Queen Amid Ashes (The Sun Eater #4.5) '
              'by Christopher Ruocchio',
          fields: writtenBy('Christopher Ruocchio'),
        ),
        entry(
          'ashes',
          title: 'Ashes of Man (The Sun Eater #5) by Christopher Ruocchio',
          fields: writtenBy('Christopher Ruocchio'),
        ),
      ]);
      expect(books.map((book) => book.series).toSet(), {'The Sun Eater'});
      expect(readingOrder(books).map((book) => book.title), [
        'Kingdoms of Death',
        'Queen Amid Ashes',
        'Ashes of Man',
      ]);
    });

    test('drops a trailing credit to the album artist', () {
      final book = buildBooks([
        entry('mort', title: 'Mort (Discworld #4) by A. Writer'),
      ]).single;
      expect(book.title, 'Mort');
      expect(book.series, 'Discworld');
    });

    test('drops a trailing credit only when it names every author', () {
      Map<String, dynamic> coauthors = {
        'People': [
          {'Name': 'Douglas Preston', 'Type': 'Author'},
          {'Name': 'Lincoln Child', 'Type': 'Author'},
        ],
      };
      final books = buildBooks([
        entry(
          'relic',
          title: 'Relic (Pendergast #1) by Douglas Preston and Lincoln Child',
          fields: coauthors,
        ),
        entry(
          'reliquary',
          title: 'Reliquary (Pendergast #2) by Douglas Preston & A. Stranger',
          fields: coauthors,
        ),
      ]);
      expect(books.map((book) => book.title), [
        'Relic',
        'Reliquary by Douglas Preston & A. Stranger',
      ]);
    });

    test('keeps a trailing credit to someone who is not an author', () {
      final books = buildBooks([
        entry(
          'rising',
          title: 'Red Rising (Red Rising Saga #1) read by Tim Gerard Reynolds',
          fields: writtenBy('Pierce Brown'),
        ),
        entry(
          'golden',
          title: 'Golden Son (Red Rising Saga #2) by Narrator Person',
          fields: writtenBy('Pierce Brown'),
        ),
      ]);
      expect(books.map((book) => book.title), [
        'Golden Son by Narrator Person',
        'Red Rising read by Tim Gerard Reynolds',
      ]);
      expect(books.map((book) => book.seriesOrder), [2, 1]);
    });

    test('keeps other trailing text in the title', () {
      final book = buildBooks([
        entry('dune', title: 'Dune (Dune #1) [Dramatized Adaptation]'),
      ]).single;
      expect(book.title, 'Dune [Dramatized Adaptation]');
      expect(book.series, 'Dune');
      expect(book.seriesOrder, 1);
    });
  });

  group('a leading part before " - "', () {
    test('is dropped when it names the series of the title', () {
      final books = buildBooks([
        entry(
          'empire',
          title: 'Mistborn - The Final Empire (Mistborn #1)',
          track: 1,
        ),
        entry(
          'crown',
          title:
              'The Wheel of Time 07 - A Crown of Swords (The Wheel of Time #7)',
          track: 2,
        ),
      ]);
      expect(books.map((book) => book.title), [
        'A Crown of Swords',
        'The Final Empire',
      ]);
    });

    test('is dropped when it names only the authors of the book', () {
      final book = buildBooks([
        entry(
          'coalescent',
          title: "Stephen Baxter - (Destiny's Children #1) Coalescent",
          fields: {
            'People': [
              {'Name': 'Stephen Baxter', 'Type': 'Author'},
            ],
          },
        ),
      ]).single;
      expect(book.title, 'Coalescent');
      expect(book.series, "Destiny's Children");
      expect(book.seriesOrder, 1);
    });

    test('stays when it names something other than the series', () {
      final book = buildBooks([
        entry('thrawn', title: 'Star Wars - Thrawn (Thrawn #1)'),
      ]).single;
      expect(book.title, 'Star Wars - Thrawn');
      expect(book.series, 'Thrawn');
    });

    test('stays when it is only a number', () {
      final book = buildBooks([
        entry('two', title: '2 - The Two Towers (The Lord of the Rings #2)'),
      ]).single;
      expect(book.title, '2 - The Two Towers');
    });
  });

  test('titles without a series label keep " by " and " - " as written', () {
    final titles = [
      ('poems', 'Poems by Emily Dickinson', 'Emily Dickinson'),
      ('hole', 'Death by Black Hole', 'Neil deGrasse Tyson'),
      ('sapiens', 'Sapiens - A Brief History of Humankind', 'Yuval Harari'),
      ('wars', 'Star Wars - Thrawn by Timothy Zahn', 'Timothy Zahn'),
      ('zahn', 'Timothy Zahn - Thrawn', 'Timothy Zahn'),
      (
        'death',
        'Kingdoms of Death - Christopher Ruocchio',
        'Christopher Ruocchio',
      ),
    ];
    final books = buildBooks([
      for (final (id, title, author) in titles)
        entry(
          id,
          title: title,
          fields: {
            'People': [
              {'Name': author, 'Type': 'Author'},
            ],
            'BookfinCollections': ['The Sun Eater'],
          },
        ),
    ]);
    expect(
      books.map((book) => book.title).toSet(),
      titles.map((title) => title.$2).toSet(),
    );
  });

  group('a title without a (Series #N) part', () {
    Map<String, dynamic> sunEater({List<String> collections = const []}) => {
      'People': [
        {'Name': 'Christopher Ruocchio', 'Type': 'Author'},
      ],
      'IndexNumber': 4,
      'BookfinCollections': collections,
    };

    test('loses a series label and an author credit in its series', () {
      final books = buildBooks([
        entry(
          'spaced',
          title: 'Sun Eater Series - Kingdoms of Death- Christopher Ruocchio',
          fields: sunEater(collections: ['The Sun Eater']),
        ),
        entry(
          'joined',
          type: 'Book',
          container: 'epub',
          title: 'Sun Eater Series - Kingdoms of Death-Christopher Ruocchio',
          fields: sunEater(collections: ['The Sun Eater']),
        ),
      ]);
      final book = books.single;
      expect(book.title, 'Kingdoms of Death');
      expect(book.series, 'The Sun Eater');
      expect(book.seriesOrder, 4, reason: 'the item number, not a guess');
      expect(book.editions, hasLength(2), reason: 'the clean titles match');
    });

    test('outside a series keeps its title and gains no series', () {
      final book = buildBooks([
        entry(
          'alone',
          title: 'Sun Eater Series - Kingdoms of Death-Christopher Ruocchio',
          fields: sunEater(),
        ),
      ]).single;
      expect(book.series, isNull);
      expect(
        book.title,
        'Sun Eater Series - Kingdoms of Death-Christopher Ruocchio',
      );
    });
  });

  test('the series page on the phone puts the #4.5 side story after #4', () {
    // The names, item numbers, and years of the Sun Eater items in the
    // phone's saved library on 2026-11-07. Without a title number, Queen Amid
    // Ashes took its item number 2.
    final sunEater = [
      ('empire', 'Empire of Silence (Sun Eater #1)', 1, 2018),
      ('devil', 'The Lesser Devil (Sun Eater #1)', 1, 2020),
      (
        'queen',
        '2.6 Sun Eater Series - Queen Amid Ashes (The Sun Eater #4.5) '
            'by Christopher Ruocchio',
        2,
        2022,
      ),
      ('howling', 'Howling Dark (Sun Eater #2)', 2, 2019),
      ('demon', 'Demon in White (Sun Eater #3)', 3, 2020),
      (
        'kingdoms',
        'Sun Eater Series - Kingdoms of Death-Christopher Ruocchio',
        4,
        2022,
      ),
      ('ashes', 'Ashes of Man (Sun Eater #5)', 5, 2022),
    ];
    final books = buildBooks([
      for (final (id, title, number, year) in sunEater)
        entry(
          id,
          title: title,
          fields: {
            'People': [
              {'Name': 'Christopher Ruocchio', 'Type': 'Author'},
            ],
            'IndexNumber': number,
            'ProductionYear': year,
            'BookfinCollections': ['Sun Eater'],
          },
        ),
    ]);
    expect(books.map((book) => book.series).toSet(), {'Sun Eater'});
    expect(readingOrder(books).map((book) => book.title), [
      'Empire of Silence',
      'The Lesser Devil',
      'Howling Dark',
      'Demon in White',
      'Kingdoms of Death',
      'Queen Amid Ashes',
      'Ashes of Man',
    ]);
  });

  test('a title in parentheses without a number is not a series', () {
    final book = buildBooks([
      entry('cloud', title: 'Cloud Atlas (20th Anniversary Edition)'),
    ]).single;
    expect(book.series, isNull);
    expect(book.title, 'Cloud Atlas (20th Anniversary Edition)');
  });

  test('plain audio files take no series from their collection', () {
    final book = buildBooks([
      entry(
        'track',
        type: 'Audio',
        fields: {
          'BookfinCollections': ['Mixtapes'],
        },
      ),
    ]).single;
    expect(book.series, isNull);
  });

  test('a corrected series wins over the Jellyfin series', () {
    final book = buildBooks(
      [
        entry('one', fields: {'SeriesName': 'Wrong'}),
      ],
      edits: CatalogEdits(
        details: {
          'book:one': const BookDetails(title: 'One', author: 'Writer'),
        },
      ),
    ).single;
    expect(book.series, isNull);
  });

  test('a book shows its own cover, or the album cover of its audio files', () {
    final own = buildBooks([
      entry(
        'own',
        fields: {
          'ImageTags': {'Primary': 'tag-own'},
        },
      ),
    ]).single;
    expect(own.cover, const CoverRef('own', 'tag-own'));
    final album = buildBooks([
      entry(
        'track',
        type: 'Audio',
        fields: {'AlbumId': 'album', 'AlbumPrimaryImageTag': 'tag-album'},
      ),
    ]).single;
    expect(album.cover, const CoverRef('album', 'tag-album'));
    expect(buildBooks([entry('bare')]).single.cover, isNull);
  });

  test('a linked book borrows a cover from any of its editions', () {
    final book = buildBooks([
      entry('audio'),
      entry(
        'ebook',
        type: 'Book',
        container: 'epub',
        fields: {
          'ImageTags': {'Primary': 'tag-ebook'},
        },
      ),
    ], edits: CatalogEdits(bookLinks: {'ebook:source': 'book:audio'})).single;
    expect(book.cover, const CoverRef('ebook', 'tag-ebook'));
  });

  test('an audio edition names its narrators', () {
    final edition = buildBooks([
      entry(
        'one',
        fields: {
          'People': [
            {'Name': 'Tom Avery', 'Type': 'Narrator'},
            {'Name': 'Mara Ellison', 'Type': 'Author'},
          ],
        },
      ),
    ]).single.editions.single;
    expect(edition.narrator, 'Tom Avery');
    expect(buildBooks([entry('two')]).single.editions.single.narrator, isNull);
  });

  test('book details come from Jellyfin metadata as plain text', () {
    final book = buildBooks([
      entry(
        'one',
        fields: {
          'Overview': '<p>Two winters after the frost,</p><p>Wren returns &amp; waits.</p>',
          'Genres': ['Literary fantasy', 'Fiction'],
          'Studios': [
            {'Name': 'Halyard Press', 'Id': 'studio'},
          ],
          'ProductionYear': 2021,
        },
      ),
    ]).single;
    expect(
      book.description,
      'Two winters after the frost,\n\nWren returns & waits.',
    );
    expect(book.genres, ['Literary fantasy', 'Fiction']);
    expect(book.publisher, 'Halyard Press');
    expect(book.year, 2021);
  });

  test('audio positions cannot cross editions or reuse replaced files', () {
    final edition = buildBooks([entry('one')]).single.editions.single;
    final file = edition.files.single;
    final position = AudioPosition(
      editionId: edition.id,
      sourceKey: file.key,
      revision: file.revision,
      milliseconds: 2500,
    );
    expect(position.fits(edition), isTrue);
    final replacement = buildBooks([entry('one', modified: '2026-02-01')])
        .single
        .editions
        .single;
    expect(position.fits(replacement), isFalse);
    expect(
      position.fits(buildBooks([entry('other')]).single.editions.single),
      isFalse,
    );
    expect(
      AudioPosition(
        editionId: edition.id,
        sourceKey: file.key,
        revision: file.revision,
        milliseconds: -1,
      ).fits(edition),
      isFalse,
    );
  });

  test(
    'text anchors belong to a text edition and retain a PDF source page',
    () {
      final edition = buildBooks([
        entry('ebook', type: 'Book', container: 'pdf'),
      ]).single.editions.single;
      final file = edition.files.single;
      final position = TextPosition(
        editionId: edition.id,
        sourceKey: file.key,
        revision: file.revision,
        anchor: 'page:4:paragraph:2',
        sourcePage: 4,
      );
      expect(position.fits(edition), isTrue);
      expect(position.sourcePage, 4);
      expect(
        position.fits(buildBooks([entry('audio')]).single.editions.single),
        isFalse,
      );
    },
  );

  test('non-book media cannot enter the catalog', () {
    expect(buildBooks([entry('movie', type: 'Movie')]), isEmpty);
  });

  test(
    'an unidentified file revision never validates a saved audio position',
    () {
      final item = entry('one', modified: null);
      final edition = buildBooks([item]).single.editions.single;
      final file = edition.files.single;
      expect(
        AudioPosition(
          editionId: edition.id,
          sourceKey: file.key,
          revision: file.revision,
          milliseconds: 1000,
        ).fits(edition),
        isFalse,
      );
    },
  );

  test('cached metadata does not change when the caller changes its input', () {
    final input = <String, dynamic>{
      ...entry('one').json,
      'MediaSources': [
        {'Id': 'original', 'Container': 'm4b', 'Size': 1000},
      ],
    };
    final cached = CatalogEntry.fromJson(input, libraryId: 'books');
    input['Name'] = 'Changed outside catalog';
    (input['MediaSources'] as List).single['Id'] = 'replacement';
    final book = buildBooks([cached]).single;
    expect(book.title, 'The Orchard');
    expect(book.editions.single.files.single.mediaSourceId, 'original');
  });
}
