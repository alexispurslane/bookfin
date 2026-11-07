import 'package:bookfin/catalog/model.dart';
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
    expect(
      frost.seriesOrder,
      isNull,
      reason: 'audio track numbers are not series positions',
    );
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
