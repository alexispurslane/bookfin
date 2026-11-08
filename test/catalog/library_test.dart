import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Edition _edition(String id, EditionKind kind) =>
    Edition(id: id, kind: kind, label: id, files: const [], memberIds: [id]);

Book _book(
  String title, {
  String? series,
  double? order,
  bool audio = true,
  bool text = false,
  String author = 'Mara Ellison',
  Map<String, String> providerIds = const {},
}) => Book(
  id: 'book:$title:${audio ? 'a' : ''}${text ? 't' : ''}',
  title: title,
  author: author,
  series: series,
  seriesOrder: order,
  providerIds: providerIds,
  editions: [
    if (audio) _edition('$title:audio', EditionKind.audio),
    if (text) _edition('$title:text', EditionKind.text),
  ],
);

/// Each entry as its book, or as its series name followed by its books.
List<Object> _shape(List<ShelfItem> items) => [
  for (final item in items)
    switch (item) {
      ShelfBook(:final book) => book,
      ShelfSeries(:final name, :final books) => [name, ...books],
    },
];

void main() {
  final frost = _book('First Frost', series: 'The Orchard Cycle', order: 1);
  final graft = _book(
    'Graft',
    series: 'The Orchard Cycle',
    order: 2,
    text: true,
  );
  final windfall = _book('Windfall', series: 'The Orchard Cycle', order: 3);
  final salt = _book(
    'Salt and Lantern',
    author: 'J. Okafor',
    text: true,
    providerIds: {'Isbn': '978-1'},
  );
  final saltEbook = _book(
    'Brine',
    audio: false,
    text: true,
    providerIds: {'Isbn': '978-1'},
  );
  final ledger = _book('Winter Ledger', audio: false, text: true);
  final ledgerAudio = _book('winter ledger!');
  final lonely = _book('Tidewater One', series: 'Tidewater', order: 1);
  // The catalog publishes its books in natural order of their titles.
  final books = sortedNaturally([
    windfall,
    salt,
    saltEbook,
    graft,
    ledger,
    ledgerAudio,
    frost,
    lonely,
  ], (book) => book.title);
  final library = CatalogLibrary.build(books);
  bool nothingDownloaded(Edition edition) => false;

  test('the library keeps the books it was built from', () {
    expect(library.books, books);
  });

  test('the library gives the same shelf as shelf for every filter that needs no download state', () {
    for (final filter in [
      ShelfFilter.all,
      ShelfFilter.audio,
      ShelfFilter.ebooks,
    ]) {
      expect(
        _shape(library.shelf(filter, nothingDownloaded)),
        _shape(shelf(books.toList(), filter, nothingDownloaded)),
        reason: '$filter',
      );
    }
  });

  test('the library gives back the same shelf list on every call', () {
    expect(
      library.shelf(ShelfFilter.audio, nothingDownloaded),
      same(library.shelf(ShelfFilter.audio, nothingDownloaded)),
    );
  });

  test('the downloaded shelf groups only the downloaded books', () {
    final downloaded = {'First Frost:audio', 'Graft:audio', 'Brine:text'};
    bool isDownloaded(Edition edition) => downloaded.contains(edition.id);
    expect(_shape(library.shelf(ShelfFilter.downloaded, isDownloaded)), [
      saltEbook,
      ['The Orchard Cycle', frost, graft],
    ]);
  });

  test('a series is found by its name', () {
    expect(library.series('The Orchard Cycle')!.books, [
      frost,
      graft,
      windfall,
    ]);
    expect(library.series('Tidewater'), isNull);
  });

  test(
    'each series is found by its name as the same entry that its books know',
    () {
      for (final book in books) {
        final series = library.seriesOf(book);
        if (series == null) continue;
        expect(library.series(series.name), same(series));
      }
      expect(library.series('No such series'), isNull);
    },
  );

  test('a book in a series of several books knows that series', () {
    expect(library.seriesOf(graft)!.name, 'The Orchard Cycle');
    expect(library.seriesOf(lonely), isNull);
    expect(library.seriesOf(salt), isNull);
  });

  test('a book is found by its id', () {
    expect(library.book(graft.id), same(graft));
    expect(library.book('book:missing'), isNull);
  });

  test('possible matches are the same as possibleMatches for every book', () {
    for (final book in books) {
      expect(
        library.matches(book),
        possibleMatches(book, books),
        reason: book.title,
      );
    }
    expect(library.matches(salt), [saltEbook]);
    expect(library.matches(ledger), [ledgerAudio]);
  });

  test('search finds the same books as search, in the same order', () {
    for (final query in ['orch', 'OKAFOR', 'winter', 'e', '  ', 'nothing']) {
      expect(library.search(query), search(books, query), reason: query);
    }
  });

  test('the empty library has no books, shelves, series or matches', () {
    final empty = CatalogLibrary.empty;
    expect(empty.books, isEmpty);
    expect(empty.shelf(ShelfFilter.all, nothingDownloaded), isEmpty);
    expect(empty.series('The Orchard Cycle'), isNull);
    expect(empty.search('orch'), isEmpty);
    empty.checkInvariants();
  });

  test('the invariant check accepts a library built from its books', () {
    library.checkInvariants();
  });
}
