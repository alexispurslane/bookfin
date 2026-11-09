// A synthetic Jellyfin server for looking at the library screens. It serves
// books with series, covers, and descriptions. No real data or credentials.
//
// nix develop --command dart run tool/showcase_fixture.dart 8096
// Sign in at http://127.0.0.1:8096 with any username and password.
// Add --full-size to serve audio files of real audiobook size (see
// showcase_media.silence).
// Add --sync-conflict to serve the Bookfin Storage plugin's contract, in
// memory. When the phone uploads its first listening place, a made-up
// second device, a made-up "Pixel Tablet", saves a different place in the
// same file without having seen the phone's, so the next sync shows a
// conflict to choose from.
// Add --footnotes to give First Frost's EPUB endnotes, with a note
// reference at the end of each of the first chapter's first paragraphs, and
// a footnote without a number after them.
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
    // Ebook only: outside a series, an audiobook and an ebook with the same
    // title join only after the user confirms, so the grid would show both.
    audio: false,
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
    'almanac',
    'The Lamplighter\'s Almanac',
    'Odile Fenn',
    cover: (0xB5793E, 0x6E4220),
    year: 2024,
    genres: ['Fantasy'],
    narrator: 'Ruth Calder',
    minutes: 598,
  ),
  _Book(
    'north',
    'Northbound',
    'Teodor Halse',
    cover: (0x5E7F8F, 0x2B3D47),
    year: 2021,
    genres: ['Travel'],
    narrator: 'Teodor Halse',
    minutes: 388,
  ),
  _Book(
    'weather',
    'A Field Guide to Small Weather',
    'June Ashby',
    cover: (0x8A8A4E, 0x4A4A26),
    year: 2018,
    genres: ['Nature writing'],
    narrator: 'Priya Rao',
    minutes: 455,
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
    'people in it would rather forget.</p>';

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
  // The title wraps at word ends to lines of at most 20 letters, which fit
  // the 320-pixel text column.
  final lines = <String>[];
  for (final word in book.title.toUpperCase().split(' ')) {
    if (lines.isNotEmpty && lines.last.length + 1 + word.length <= 20) {
      lines.last = '${lines.last} $word';
    } else {
      lines.add(word);
    }
  }
  for (var i = 0; i < lines.length; i++) {
    img.drawString(
      image,
      lines[i],
      font: img.arial24,
      x: 40,
      y: 440 + i * 30,
      color: img.ColorRgb8(255, 249, 239),
    );
  }
  img.drawString(
    image,
    book.author,
    font: img.arial14,
    x: 40,
    y: 450 + lines.length * 30,
    color: img.ColorRgba8(255, 249, 239, 200),
  );
  return img.encodePng(image);
}

/// The ebook file of a book: a made-up EPUB, or a PDF with a scanned page.
/// With [footnotes], First Frost has [_frostNotes] and [_frostFootnotes].
Uint8List _ebook(_Book book, {bool footnotes = false}) => switch (book.ebook) {
  'pdf' => media.pdfWithScan(),
  _ => media.epub(
    book.id,
    book.title,
    book.author,
    switch (book.id) {
      'frost' => media.firstFrost,
      'salt' => media.saltAndLantern,
      _ => media.winterLedger,
    },
    endnotes: footnotes && book.id == 'frost' ? _frostNotes : const [],
    footnotes: footnotes && book.id == 'frost' ? _frostFootnotes : const [],
  ),
};

/// The endnotes of First Frost with --footnotes: a note of one line, a
/// note of a few lines, a note of several paragraphs, and a note long
/// enough to scroll.
const _frostNotes = [
  'The Frost Road, as the village still calls it.',
  'Russets are apples with rough, brownish skin. The old trees on the south '
      'wall were Egremont Russets, planted in the spring of 1961.',
  'Grafting joins a cut branch, the scion, to a rooted tree, the stock, so '
      'that the two grow as one. The union stays visible as a ridge in the '
      'bark for years.\n\n'
      'A whip graft joins a scion and a stock of the same width. A cleft '
      'graft sets one or two thin scions into a split in a thick stock, as '
      'on the old russets.\n\n'
      'Either way, the cut faces must meet along their green inner bark.',
  'Mrs. Pell kept the shop for forty years. She took it over from her '
      'father, who sold seed and paraffin from the same counter and kept the '
      'post office in a cupboard behind it. In the hard winter of 1963 the '
      'lane was closed for six weeks, and the shop fed the village from its '
      'cellar: flour, tinned milk, dried peas and the last of the autumn '
      'apples, which Wren\'s grandmother brought down on a sledge. Every '
      'family in the parish owed the shop money by the thaw, and Mrs. Pell\'s '
      'father wrote none of it down. When he died, the village paid for his '
      'stone. Mrs. Pell still keeps his scales on the counter, though they '
      'have not weighed anything since decimal money came in, and she still '
      'opens at six, in case the lane is closed again and somebody needs '
      'bread before the plough comes through. People who have moved away '
      'send her cards at Christmas. She keeps them in the cupboard where the '
      'post office was, in a biscuit tin, sorted by year.',
];

/// The footnote of First Frost with --footnotes, which has no number.
const _frostFootnotes = [
  'The postman, Tom Ash, has walked the same round since 1989.',
];

Map<String, Object?> _item(
  _Book book, {
  required bool text,
  required int size,
}) => {
  'Id': text ? '${book.id}-text' : book.id,
  'Name': book.title,
  'Type': text ? 'Book' : 'AudioBook',
  'SeriesName': ?book.series,
  'IndexNumber': ?book.index,
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
  if (book.cover != null) 'ImageTags': {'Primary': 'v2'},
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

/// The Bookfin Storage plugin's object store for one user, in memory: each
/// object has an identity, a sequence that grows with every write, and a
/// payload. See plugin/Bookfin.Storage/StorageController.cs.
class _Storage {
  final _objects = <String, Map<String, Object?>>{};
  var _sequence = 0;
  var _conflictAdded = false;

  Map<String, Object?> _store(String id, String payload) => _objects[id] = {
    'Id': id,
    'Sequence': ++_sequence,
    'Payload': payload,
    'Deleted': false,
  };

  /// Answers one request to /BookfinStorage/v1/objects[/{id}].
  Future<(int, Object?)> handle(HttpRequest request, List<String> parts) async {
    final at = parts.indexOf('objects');
    final id = parts.length > at + 1 ? parts[at + 1] : null;
    if (id == null) {
      if (request.method != 'GET') return (405, null);
      final after = int.tryParse(request.uri.queryParameters['after'] ?? '0');
      final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '4');
      if (after == null || after < 0 || limit == null || limit < 1) {
        return (400, null);
      }
      final newer =
          _objects.values
              .where((object) => (object['Sequence'] as int) > after)
              .toList()
            ..sort(
              (a, b) => (a['Sequence'] as int).compareTo(b['Sequence'] as int),
            );
      final page = newer.take(limit).toList();
      return (
        200,
        {
          'Objects': page,
          'Cursor': page.isEmpty ? after : page.last['Sequence'],
          'HasMore': newer.length > limit,
        },
      );
    }
    if (request.method == 'GET') {
      final object = _objects[id];
      return object == null ? (404, null) : (200, object);
    }
    if (request.method != 'PUT') return (405, null);
    final body = jsonDecode(await utf8.decodeStream(request));
    final payload = body is Map ? body['Payload'] : null;
    if (payload is! String || payload.isEmpty) return (400, null);
    if (_objects[id] case final existing?) {
      return (existing['Payload'] == payload ? 200 : 409, existing);
    }
    final stored = _store(id, payload);
    _addConflict(payload);
    return (201, stored);
  }

  /// After the phone's first listening place, stores a place in the same
  /// file from another device whose context has not seen the phone's
  /// actions, so both versions stay current.
  void _addConflict(String payload) {
    if (_conflictAdded) return;
    final action = jsonDecode(payload) as Map<String, dynamic>;
    final address = jsonDecode(action['record'] as String) as List;
    final value = action['value'];
    if (address[0] != 'audio' || address[1] != 'resumes' || value is! Map) {
      return;
    }
    _conflictAdded = true;
    // The tablet stopped at 4:12:47, or at 1:08:20 when the phone is there.
    const tabletPlace = (4 * 3600 + 12 * 60 + 47) * 1000;
    final tablet = {
      'version': 1,
      'account': action['account'],
      'replica': 'showcase-tablet',
      'sequence': 1,
      'context': <String, int>{},
      'record': action['record'],
      'value': {
        ...value,
        'milliseconds': value['milliseconds'] == tabletPlace
            ? (3600 + 8 * 60 + 20) * 1000
            : tabletPlace,
      },
      'preserve': <String>[],
      'device': 'Pixel Tablet',
      'savedAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
    };
    _store('action.showcase-tablet.1', jsonEncode(tablet));
  }
}

Future<void> main(List<String> arguments) async {
  final fullSize = arguments.contains('--full-size');
  final storage = arguments.contains('--sync-conflict') ? _Storage() : null;
  final footnotes = arguments.contains('--footnotes');
  final port = arguments.where((argument) => !argument.startsWith('--'));
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port.isEmpty ? 8096 : int.parse(port.single),
  );
  final covers = {
    for (final book in _books)
      if (book.cover != null) book.id: _cover(book),
  };
  // Every audiobook plays the same silence, long enough for the longest book.
  final silence = await media.silence(
    Duration(minutes: _books.map((book) => book.minutes).reduce(max)),
    fullSize: fullSize,
  );
  final ebooks = {
    for (final book in _books)
      if (book.ebook != null)
        '${book.id}-text': _ebook(book, footnotes: footnotes),
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
    } else if (storage != null && parts.contains('BookfinStorage')) {
      final (status, answer) = await storage.handle(request, parts);
      response.statusCode = status;
      data = answer;
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
