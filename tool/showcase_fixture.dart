// A synthetic Jellyfin server for looking at the library screens. It serves
// books with series, covers, and descriptions. No real data or credentials.
//
// nix develop --command dart run tool/showcase_fixture.dart 8096
// Sign in at http://127.0.0.1:8096 with any username and password.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'showcase_media.dart' as media;

const _token = 'showcase-token';

class _Book {
  const _Book(
    this.id,
    this.title,
    this.author, {
    this.series,
    this.index,
    this.audio = true,
    this.ebook,
    this.cover,
    this.year,
    this.genres = const [],
    this.narrator,
    this.minutes = 540,
  });
  final String id;
  final String title;
  final String author;
  final String? series;
  final int? index;
  final bool audio;
  final String? ebook;
  final (int, int)? cover;
  final int? year;
  final List<String> genres;
  final String? narrator;
  final int minutes;
}

const _books = [
  _Book(
    'frost',
    'First Frost',
    'Mara Ellison',
    series: 'The Orchard Cycle',
    index: 1,
    ebook: 'epub',
    cover: (0xA8653A, 0x6B3B22),
    year: 2019,
    genres: ['Literary fantasy'],
    narrator: 'Tom Avery',
    minutes: 612,
  ),
  _Book(
    'graft',
    'Graft',
    'Mara Ellison',
    series: 'The Orchard Cycle',
    index: 2,
    cover: (0xC49A4B, 0x80602A),
    year: 2021,
    genres: ['Literary fantasy'],
    narrator: 'Tom Avery',
    minutes: 584,
  ),
  _Book(
    'windfall',
    'Windfall',
    'Mara Ellison',
    series: 'The Orchard Cycle',
    index: 3,
    ebook: 'pdf',
    year: 2023,
    genres: ['Literary fantasy'],
    narrator: 'Tom Avery',
  ),
  _Book(
    'tide1',
    'Tidewater',
    'R. Hale',
    series: 'Tidewater',
    index: 1,
    cover: (0x8B6F9E, 0x4D3B5C),
    year: 2016,
    genres: ['Mystery'],
    narrator: 'Ines Okoro',
  ),
  _Book(
    'tide2',
    'The Low Tide Ledger',
    'R. Hale',
    series: 'Tidewater',
    index: 2,
    cover: (0x5C7D8A, 0x2F4750),
    year: 2018,
    genres: ['Mystery'],
    narrator: 'Ines Okoro',
  ),
  _Book(
    'salt',
    'Salt and Lantern',
    'J. Okafor',
    ebook: 'epub',
    cover: (0x4F6B5A, 0x2E3F35),
    year: 2020,
    genres: ['Historical fiction'],
    narrator: 'Ada Lin',
  ),
  _Book(
    'quiet',
    'A Map of Quiet Rooms',
    'Ines Varga',
    cover: (0x3D4F73, 0x232D45),
    year: 2022,
    genres: ['Essays'],
    narrator: 'Ines Varga',
    minutes: 301,
  ),
  _Book(
    'ferry',
    'The Glass Ferry',
    'Petra Lind',
    year: 2017,
    genres: ['Science fiction'],
    narrator: 'Sam Ortiz',
  ),
  _Book(
    'ledger',
    'Winter Ledger',
    'S. Moreau',
    audio: false,
    ebook: 'epub',
    cover: (0x7A3D3D, 0x472020),
    year: 2015,
    genres: ['Poetry'],
  ),
];

const _overview =
    '<p>Two winters after the frost, Wren returns to the orchard to find the '
    'old trees grafted with a stranger\'s stock, and the village quietly '
    'pretending not to notice.</p><p>What follows is a patient, strange book '
    'about inheritance, weather, and the things a place remembers when the '
    'people in it would rather forget. Synthetic description for the '
    'Bookfin showcase fixture.</p>';

Uint8List _cover(_Book book) {
  final (top, bottom) = book.cover!;
  final image = img.Image(width: 400, height: 600);
  img.ColorRgb8 color(int rgb) =>
      img.ColorRgb8(rgb >> 16 & 0xff, rgb >> 8 & 0xff, rgb & 0xff);
  for (var y = 0; y < 600; y++) {
    final t = y / 599;
    final a = color(top), b = color(bottom);
    img.drawLine(
      image,
      x1: 0,
      y1: y,
      x2: 399,
      y2: y,
      color: img.ColorRgb8(
        (a.r + (b.r - a.r) * t).round(),
        (a.g + (b.g - a.g) * t).round(),
        (a.b + (b.b - a.b) * t).round(),
      ),
    );
  }
  final light = img.ColorRgba8(255, 249, 239, 90);
  img.drawCircle(image, x: 300, y: 170, radius: 120, color: light);
  img.drawCircle(image, x: 300, y: 170, radius: 80, color: light);
  img.fillRect(image, x1: 40, y1: 420, x2: 360, y2: 424, color: light);
  img.drawString(
    image,
    book.title.toUpperCase(),
    font: img.arial24,
    x: 40,
    y: 440,
    color: img.ColorRgb8(255, 249, 239),
  );
  img.drawString(
    image,
    book.author,
    font: img.arial14,
    x: 40,
    y: 480,
    color: img.ColorRgba8(255, 249, 239, 200),
  );
  return img.encodePng(image);
}

/// The ebook file of a book: a made-up EPUB, or a PDF with a scanned page.
Uint8List _ebook(_Book book) => switch (book.ebook) {
  'pdf' => media.pdfWithScan(),
  _ => media.epub(book.id, book.title, book.author, switch (book.id) {
    'frost' => media.firstFrost,
    'salt' => media.saltAndLantern,
    _ => media.winterLedger,
  }),
};

Map<String, Object?> _item(
  _Book book, {
  required bool text,
  required int size,
}) => {
  'Id': text ? '${book.id}-text' : book.id,
  'Name': book.title,
  'Type': text ? 'Book' : 'AudioBook',
  'SeriesName': ?book.series,
  if (text && book.index != null) 'IndexNumber': book.index,
  'People': [
    {'Name': book.author, 'Type': 'Author'},
    if (!text && book.narrator != null)
      {'Name': book.narrator, 'Type': 'Narrator'},
  ],
  'Overview': _overview,
  'Genres': book.genres,
  'Studios': [
    {'Name': 'Halyard Press', 'Id': 'halyard'},
  ],
  'ProductionYear': ?book.year,
  if (book.cover != null) 'ImageTags': {'Primary': 'v1'},
  'DateModified': '2026-11-07T00:00:00Z',
  'RunTimeTicks': text ? null : book.minutes * 60 * 10000000,
  'ProviderIds': <String, String>{},
  'Chapters': text
      ? []
      : [
          for (var chapter = 0; chapter < 12; chapter++)
            {
              'Name': 'Chapter ${chapter + 1}',
              'StartPositionTicks': chapter * book.minutes * 5 * 10000000,
            },
        ],
  'MediaSources': [
    {
      'Id': text ? '${book.id}-text' : book.id,
      'Container': text ? book.ebook : 'm4b',
      'Size': size,
      'RunTimeTicks': text ? null : book.minutes * 60 * 10000000,
      'ETag': 'showcase-${book.id}-${text ? 'text' : 'audio'}',
    },
  ],
};

Future<void> main(List<String> arguments) async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    arguments.isEmpty ? 8096 : int.parse(arguments.single),
  );
  final covers = {
    for (final book in _books)
      if (book.cover != null) book.id: _cover(book),
  };
  // Every audiobook plays the same silence, long enough for the longest book.
  final silence = await media.silence(
    Duration(minutes: _books.map((book) => book.minutes).reduce(max)),
  );
  final ebooks = {
    for (final book in _books)
      if (book.ebook != null) '${book.id}-text': _ebook(book),
  };
  final items = [
    for (final book in _books) ...[
      if (book.audio) _item(book, text: false, size: silence.length),
      if (book.ebook != null)
        _item(book, text: true, size: ebooks['${book.id}-text']!.length),
    ],
  ];
  const user = {
    'Id': 'showcase-user',
    'Name': 'reader',
    'Policy': {'EnableContentDownloading': true, 'IsAdministrator': false},
  };
  stdout.writeln('Showcase fixture on http://127.0.0.1:${server.port}');
  await for (final request in server) {
    final response = request.response;
    final path = request.uri.path;
    final parts = request.uri.pathSegments;
    Object? data;
    if (path.endsWith('/Users/AuthenticateByName')) {
      await request.drain<void>();
      data = {'User': user, 'ServerId': 'showcase', 'AccessToken': _token};
    } else if (path.endsWith('/System/Info/Public')) {
      data = {'Id': 'showcase'};
    } else if (parts.length >= 4 &&
        parts[parts.length - 4] == 'Items' &&
        parts.last == 'Primary') {
      final id = parts[parts.length - 3].replaceAll('-text', '');
      final bytes = covers[id];
      if (bytes == null) {
        response.statusCode = 404;
      } else {
        response.headers.contentType = ContentType('image', 'png');
        response.add(bytes);
      }
      await response.close();
      continue;
    } else if (request.headers.value('X-Emby-Token') != _token) {
      response.statusCode = 401;
    } else if (path.endsWith('/Users/Me')) {
      data = user;
    } else if (path.endsWith('/UserViews')) {
      data = {
        'Items': [
          {'Id': 'books', 'Name': 'Audiobooks', 'CollectionType': 'books'},
        ],
      };
    } else if (parts.length >= 2 && parts[parts.length - 2] == 'Items') {
      data = {
        ...items.firstWhere(
          (item) => item['Id'] == parts.last,
          orElse: () => {'Id': null},
        ),
        'CanDownload': true,
      };
    } else if (parts.isNotEmpty && parts.last == 'Items') {
      data = {
        'Items': items,
        'TotalRecordCount': items.length,
        'StartIndex': 0,
      };
    } else if (parts.isNotEmpty && parts.last == 'Download') {
      response.headers.contentType = ContentType.binary;
      final bytes = parts.length >= 2
          ? ebooks[parts[parts.length - 2]] ?? silence
          : silence;
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
      continue;
    } else {
      response.statusCode = 404;
    }
    response.headers.contentType = ContentType.json;
    if (data != null) response.write(jsonEncode(data));
    await response.close();
  }
}
