import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Edition _edition(String id, EditionKind kind) =>
    Edition(id: id, kind: kind, label: id, files: const [], memberIds: [id]);

Book _book(
  String title, {
  String? series,
  double? order,
  int? year,
  bool audio = true,
  bool text = false,
  String author = 'Mara Ellison',
}) => Book(
  id: 'book:$title',
  title: title,
  author: author,
  series: series,
  seriesOrder: order,
  year: year,
  editions: [
    if (audio) _edition('$title:audio', EditionKind.audio),
    if (text) _edition('$title:text', EditionKind.text),
  ],
);

List<String> _names(List<ShelfItem> items) => [
  for (final item in items)
    switch (item) {
      ShelfBook(:final book) => book.title,
      ShelfSeries(:final name, :final books) => '$name (${books.length})',
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
  final salt = _book('Salt and Lantern', author: 'J. Okafor', text: true);
  final ledger = _book('Winter Ledger', audio: false, text: true);
  final lonely = _book('Tidewater One', series: 'Tidewater', order: 1);
  final books = [windfall, salt, graft, ledger, frost, lonely];
  Set<String> downloaded = {};
  bool isDownloaded(Edition edition) => downloaded.contains(edition.id);

  setUp(() => downloaded = {});

  test('the library shows a series of several books as one entry', () {
    expect(_names(shelf(books, ShelfFilter.all, isDownloaded)), [
      'Salt and Lantern',
      'The Orchard Cycle (3)',
      'Tidewater One',
      'Winter Ledger',
    ]);
  });

  test('a series with only one book in the library shows the book itself', () {
    expect(
      shelf(
        books,
        ShelfFilter.all,
        isDownloaded,
      ).whereType<ShelfBook>().map((item) => item.book.title),
      contains('Tidewater One'),
    );
  });

  test('a series lists its books in reading order', () {
    final series = shelf(
      books,
      ShelfFilter.all,
      isDownloaded,
    ).whereType<ShelfSeries>().single;
    expect(series.books.map((book) => book.title), [
      'First Frost',
      'Graft',
      'Windfall',
    ]);
  });

  test('books without a series position follow by year, then title', () {
    final ordered = readingOrder([
      _book('Coda', series: 'S'),
      _book('Later', series: 'S', year: 2020),
      _book('Earlier', series: 'S', year: 2010),
      _book('Opening', series: 'S', order: 1),
    ]);
    expect(ordered.map((book) => book.title), [
      'Opening',
      'Earlier',
      'Later',
      'Coda',
    ]);
  });

  test('a filter applies to books before they are grouped', () {
    expect(_names(shelf(books, ShelfFilter.ebooks, isDownloaded)), [
      'Graft',
      'Salt and Lantern',
      'Winter Ledger',
    ]);
    expect(_names(shelf(books, ShelfFilter.audio, isDownloaded)), [
      'Salt and Lantern',
      'The Orchard Cycle (3)',
      'Tidewater One',
    ]);
  });

  test('a book counts as downloaded by its audio, or by its ebook when it has no audio', () {
    downloaded = {'Graft:text', 'Winter Ledger:text'};
    expect(bookDownloaded(graft, isDownloaded), isFalse);
    expect(bookDownloaded(ledger, isDownloaded), isTrue);
    downloaded.add('Graft:audio');
    expect(bookDownloaded(graft, isDownloaded), isTrue);
  });

  test('the downloaded filter keeps only downloaded books', () {
    downloaded = {'First Frost:audio', 'Graft:audio', 'Winter Ledger:text'};
    expect(_names(shelf(books, ShelfFilter.downloaded, isDownloaded)), [
      'The Orchard Cycle (2)',
      'Winter Ledger',
    ]);
  });

  test(
    'search finds books by title, author, or series without grouping them',
    () {
      expect(search(books, 'orch').map((book) => book.title), [
        'First Frost',
        'Graft',
        'Windfall',
      ]);
      expect(search(books, 'OKAFOR').map((book) => book.title), [
        'Salt and Lantern',
      ]);
      expect(search(books, '  '), isEmpty);
    },
  );

  test('series names that differ only in case or spacing are one series', () {
    final items = shelf(
      [
        _book('A', series: 'The Orchard Cycle', order: 1),
        _book('B', series: ' the orchard cycle', order: 2),
      ],
      ShelfFilter.all,
      isDownloaded,
    );
    expect(_names(items), ['The Orchard Cycle (2)']);
  });
}
