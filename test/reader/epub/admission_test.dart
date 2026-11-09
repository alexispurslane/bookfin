// Admission keeps what the native renderer needs beside the admitted files:
// the book's own style sheets, the sizes of its images and its contents. The
// admitted files themselves stay byte for byte, because the publication
// identity hashes every one of them and every saved place of a book matches
// on that identity.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

import '../../../tool/showcase_media.dart' as media;

/// An EPUB archive with the package document at `OPS/book.opf` and [files]
/// beside it, by archive path.
Uint8List archive(
  Map<String, String> files, {
  Map<String, List<int>> binary = const {},
}) {
  final entries = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    ),
    for (final MapEntry(:key, :value) in files.entries) key: utf8.encode(value),
    ...binary,
  };
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.addFile(ArchiveFile(key, value.length, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A package document with the manifest [items] and the spine [spine], each
/// given as raw XML.
String package(String items, String spine, {String version = '3.0'}) =>
    '<package xmlns="http://www.idpf.org/2007/opf" version="$version">'
    '<metadata/><manifest>$items</manifest><spine>$spine</spine></package>';

String xhtml(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>Part</title><link rel="stylesheet" href="../css/core.css"/></head>'
    '<body>$body</body></html>';

/// The start of every Standard Ebooks style sheet.
const namespace = '@namespace epub "http://www.idpf.org/2007/ops";';

const core =
    '$namespace\n\n'
    'body{\n\tfont-variant-numeric: oldstyle-nums;\n}\n\n'
    '[epub|type~="z3998:verse"] p{\n\tpadding-left: 1em;\n}\n';

/// A book shaped like a Standard Ebooks EPUB: a navigation document beside
/// the package document with landmarks before the toc, style sheets that
/// declare a CSS namespace, and two chapters, the first with a part that
/// starts half way through its text.
Uint8List standardEbook() => archive({
  'OPS/book.opf': package(
    '<item id="toc" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        '<item id="core.css" href="css/core.css" media-type="text/css"/>'
        '<item id="local.css" href="css/local.css" media-type="text/css"/>'
        '<item id="title" href="text/titlepage.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="one" href="text/chapter-1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="two" href="text/chapter-2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="colophon" href="text/colophon.xhtml" media-type="application/xhtml+xml"/>',
    '<itemref idref="title"/><itemref idref="one"/><itemref idref="two"/>',
  ),
  'OPS/toc.xhtml': xhtml(
    '<nav epub:type="landmarks"><ol>'
    '<li><a href="text/chapter-2.xhtml" epub:type="bodymatter">Body</a></li>'
    '</ol></nav>'
    '<nav id="toc" role="doc-toc" epub:type="toc"><h2>Table of Contents</h2><ol>'
    '<li><a href="text/titlepage.xhtml">Titlepage</a></li>'
    '<li><a href="text/chapter-1.xhtml">\n  I:\n  The Road\n</a><ol>'
    '<li><a href="text/chapter-1.xhtml#part-2">Part Two</a></li>'
    '</ol></li>'
    '<li><a href="text/chapter-2.xhtml#chapter-2">II</a></li>'
    '<li><a href="text/colophon.xhtml">Colophon</a></li>'
    '</ol></nav>',
  ),
  'OPS/css/core.css': core,
  'OPS/css/local.css': '$namespace\n\nh2{\n\tfont-variant: small-caps;\n}\n',
  'OPS/text/titlepage.xhtml': xhtml('<h1>The Road</h1>'),
  // 100 visible characters come before the heading "Part", and 100 from it.
  'OPS/text/chapter-1.xhtml': xhtml(
    '<h2 id="chapter-1">I</h2><p>${'a' * 99}</p>'
    '<h3 id="part-2">Part</h3><p>${'b' * 96}</p>',
  ),
  'OPS/text/chapter-2.xhtml': xhtml(
    '<h2 id="chapter-2">II</h2><p>${'c' * 300}</p>',
  ),
  'OPS/text/colophon.xhtml': xhtml('<p>Colophon</p>'),
});

/// An EPUB 2 book whose NCX sits in its own folder below the package
/// document.
Uint8List epub2({String? navMap}) => archive({
  'OPS/book.opf': package(
    '<item id="ncx" href="nav/toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '<item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="two" href="text/two.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="notes" href="text/notes.xhtml" media-type="application/xhtml+xml"/>',
    '<itemref idref="one"/><itemref idref="two"/>',
    version: '2.0',
  ),
  'OPS/nav/toc.ncx':
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
      '<navMap>${navMap ?? '<navPoint id="n1"><navLabel><text> One </text></navLabel>'
              '<content src="../text/one.xhtml"/>'
              '<navPoint id="n2"><navLabel><text>A part of one</text></navLabel>'
              '<content src="../text/one.xhtml#part"/></navPoint>'
              '</navPoint>'
              '<navPoint id="n3"><navLabel><text></text></navLabel>'
              '<content src="../text/two.xhtml"/></navPoint>'
              '<navPoint id="n4"><navLabel><text>Notes</text></navLabel>'
              '<content src="../text/notes.xhtml"/></navPoint>'}'
      '</navMap></ncx>',
  'OPS/text/one.xhtml': xhtml('<p>One</p><p id="part">Part</p>'),
  'OPS/text/two.xhtml': xhtml('<p>Two</p>'),
  'OPS/text/notes.xhtml': xhtml('<p>Notes</p>'),
});

/// A book with one chapter and the navigation document [nav], whose toc
/// links point at `text/one.xhtml`.
Uint8List withNav(String nav, {bool ncx = false}) => archive({
  'OPS/book.opf': package(
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="scripted nav"/>'
        '${ncx ? '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' : ''}'
        '<item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/>',
    '<itemref idref="one"/>',
  ),
  'OPS/nav.xhtml': xhtml(nav),
  if (ncx)
    'OPS/toc.ncx':
        '<ncx><navMap><navPoint><navLabel><text>From the NCX</text></navLabel>'
        '<content src="text/one.xhtml"/></navPoint></navMap></ncx>',
  'OPS/text/one.xhtml': xhtml('<p id="a">One</p>'),
});

List<(String, String, int)> listed(Publication publication) => [
  for (final entry in publication.contents)
    (entry.title, entry.href, entry.depth),
];

/// A showcase book from `tool/showcase_media.dart`, zipped again with a
/// fixed file time, because the showcase stamps each file with the time it
/// was made and the identity hashes the archive bytes too.
Uint8List showcase(
  String id,
  String title,
  String author,
  List<media.Chapter> chapters,
) => ZipEncoder().encodeBytes(
  ZipDecoder().decodeBytes(media.epub(id, title, author, chapters)),
  modified: DateTime(2026, 11, 7),
);

/// The sha-256 of each book's bytes and the publication identity that
/// admission gave it before tc-acl5, by book.
const identities = {
  'frost': (
    '53bd37512798f89a6af0db87b0e57b7c004f1fde4736e78d19268d89c3573f53',
    '8917584cf2df9384f7e22457ef3f141b5f9ef39ef0f7816887e1c68de150aea2',
  ),
  'salt': (
    '1a5d6f77b72048aa1f499281e6c2e30b4ea5512b57f6135ca3271f0580b36322',
    '04a781c07036dc3b7edb738add3bb2434d31c0293980d3875f761578a3d0b58e',
  ),
  'ledger': (
    '2b10044ae2b21527c92dbc2da7837275bacf5ccbc441a4de0d784699e752fed3',
    '8caf95938e22e81b69f171073bd8b5f95d9be5d0e3258c38cb89f1c4d87d37de',
  ),
  'tool/research/readers/fixtures/river.epub': (
    'd1208cdf94fbe5565926daa452c75f26b678b650f6c3b5258e2961ea7b49e37a',
    '4d294c0ac46e1f893f06d1d95a2507953065e9aac64b6d11d8bf569a0eed821b',
  ),
  'tool/evidence/reader/android-remaining/initial-synthetic.epub': (
    '23c5416e3db33bdfe48b363a52f8ae9ab9de93bccc45ecb1156486284402251f',
    '2c4b0cfef46f0ecb0a6bb4d043bf624b70c73d9bc64391a36e5a39e41612e57e',
  ),
  'tool/evidence/reader/android-remaining/synthetic.epub': (
    'bcf88777f524e966d9f2445f5a253b83659644a704def64510674876082c7207',
    '66b8218f87a845923c2724e259a99fa22f6423f7960a0c4b31791660f4da72a0',
  ),
  // Public-domain books of the boo-ju83 trial, which are not committed (see
  // docs/research/native-epub.md). Their tests run where the files exist.
  'pg-46-christmas-carol': (
    '8557960c8d5e62e23ebfeedacad8ad0a4ebf8d056c1ad37210b2a528c2a2d6cb',
    '6e5671c36d7f92aa7c4955c39334482bcc2cb3d6d374f71c0cff41e8f91447ce',
  ),
  'pg-84-frankenstein': (
    '0bfcc8cacdc72e132272844ed465c6198f1049a8d2b9e3f16806d02beee452e3',
    'ea29645e32933c44326ffcc0a8069500aff727800beddbe1386d668937481e16',
  ),
  'se-alices-adventures-in-wonderland': (
    '431719c25bcb0b6a67fc03938b4633723d775324ac2c62a06a04f98862148bef',
    '0d2f8b432170171eea18090937acada8d53833932e71cd9ac601011cf833e413',
  ),
  'se-frankenstein': (
    '0b5c070e2cde4d8bb36ef707f9d024465b00d0c49c078f0a148270f55b8c8780',
    '4d53fbba25986fed7306c286a20948f5dc29ca66b36cfef1f10e0c42a8edeca3',
  ),
  'se-moby-dick': (
    '4f0a70cac781ab8f30b5efb8d20ee78db9e7e1fc23e0c261e35c8690f48db34c',
    'b8c4982ddcec03eada89786372f11315e1fa0e6a27cad51b5d4006e7d885e4bf',
  ),
  'se-poetry': (
    '93468bc5a4cbb523809171b99d27ad418e5f4f764762ffc4f4cb1386fabcbdfe',
    '287473e137e08c74a3dc228418bd8a57911061a7cb88e4003582482c77b8ba6a',
  ),
  'se-pride-and-prejudice': (
    '85814417c1a74d2ca7f3b077b47454d0cfc728392d40d846d1c97d44f24c5279',
    'ee3a269772b740e8d1016a5ff8d61caba4b0aff9ef5820adc6c8924419e8f759',
  ),
};

void main() {
  group('the publication identity of a known book stays the same', () {
    void pin(String name, Uint8List Function() bytes, {Object? skip}) {
      test(name, () {
        final (digest, identity) = identities[name]!;
        final publication = Publication.admit(bytes());
        expect(
          publication.originalDigest,
          digest,
          reason: 'The book itself changed, so its identity proves nothing.',
        );
        expect(
          publication.identity,
          identity,
          reason:
              'Admission output changed, so every saved place and bookmark of '
              'this book would stop matching it.',
        );
        publication.checkInvariants();
      }, skip: skip);
    }

    pin(
      'frost',
      () => showcase('frost', 'First Frost', 'Mara Ellison', media.firstFrost),
    );
    pin(
      'salt',
      () => showcase(
        'salt',
        'Salt and Lantern',
        'J. Okafor',
        media.saltAndLantern,
      ),
    );
    pin(
      'ledger',
      () =>
          showcase('ledger', 'Winter Ledger', 'S. Moreau', media.winterLedger),
    );
    for (final path in identities.keys.where(
      (name) => name.endsWith('.epub'),
    )) {
      pin(path, () => File(path).readAsBytesSync());
    }
    for (final name in identities.keys.where((name) => !name.contains('.'))) {
      if (['frost', 'salt', 'ledger'].contains(name)) continue;
      final file = File('.cache/epub-trial/books/$name.epub');
      pin(
        name,
        file.readAsBytesSync,
        skip: file.existsSync()
            ? null
            : 'The trial book ${file.path} is not here.',
      );
    }
  });

  group("the publication's language", () {
    Publication withMetadata(String metadata) => Publication.admit(
      archive({
        'OPS/book.opf': package(
          '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>',
          '<itemref idref="one"/>',
        ).replaceFirst('<metadata/>', metadata),
        'OPS/one.xhtml': xhtml('<p>One</p>'),
      }),
    );

    test("is the package's first dc:language, without the space around it", () {
      expect(
        withMetadata(
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:language>\n  en-GB\n</dc:language><dc:language>fr</dc:language>'
          '</metadata>',
        ).language,
        'en-GB',
      );
    });

    test('is unknown when the package names no language', () {
      expect(withMetadata('<metadata/>').language, isNull);
      expect(
        withMetadata(
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:language> </dc:language></metadata>',
        ).language,
        isNull,
      );
    });

    test('of each showcase book is English, and the identity that saved '
        'places match on stays the same', () {
      for (final (name, title, author, chapters) in [
        ('frost', 'First Frost', 'Mara Ellison', media.firstFrost),
        ('salt', 'Salt and Lantern', 'J. Okafor', media.saltAndLantern),
        ('ledger', 'Winter Ledger', 'S. Moreau', media.winterLedger),
      ]) {
        final publication = Publication.admit(
          showcase(name, title, author, chapters),
        );
        expect(publication.language, 'en', reason: name);
        expect(publication.identity, identities[name]!.$2, reason: name);
      }
    });
  });

  test('a Standard Ebooks style sheet keeps its full text beside the admitted '
      'sheet, which stays as before', () {
    final publication = Publication.admit(standardEbook());
    expect(publication.bookStyles['OPS/css/core.css'], core);
    expect(publication.bookStyles['OPS/css/local.css'], startsWith(namespace));
    expect(publication.resources['OPS/css/core.css'], isEmpty);
    expect(publication.resources['OPS/css/local.css'], isEmpty);
    publication.checkInvariants();
  });

  test('the book styles hold only the style sheets that admission kept', () {
    final publication = Publication.admit(
      archive({
        'OPS/book.opf': package(
          '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
              '<item id="css" href="book.css" media-type="text/css"/>'
              '<item id="less" href="book.less" media-type="text/x-less"/>',
          '<itemref idref="one"/>',
        ),
        'OPS/one.xhtml': xhtml('<p>One</p>'),
        'OPS/book.css': 'p{margin:0}',
        'OPS/book.less': 'p{margin:0}',
      }),
    );
    expect(publication.bookStyles, {'OPS/book.css': 'p{margin:0}'});
  });

  test('the contents of an EPUB 3 book list its toc nav with depths, relative '
      'to the package document, and only entries in the spine', () {
    final publication = Publication.admit(standardEbook());
    expect(listed(publication), [
      ('Titlepage', 'text/titlepage.xhtml', 0),
      ('I: The Road', 'text/chapter-1.xhtml', 0),
      ('Part Two', 'text/chapter-1.xhtml#part-2', 1),
      ('II', 'text/chapter-2.xhtml#chapter-2', 0),
    ]);
    publication.checkInvariants();
  });

  test('the contents of an EPUB 2 book list its NCX navMap', () {
    final publication = Publication.admit(epub2());
    expect(listed(publication), [
      ('One', 'text/one.xhtml', 0),
      ('A part of one', 'text/one.xhtml#part', 1),
      ('Untitled chapter', 'text/two.xhtml', 0),
    ]);
    publication.checkInvariants();
  });

  test('a toc entry without a title is an untitled chapter, a heading without '
      'a link keeps its children, and links outside the spine are dropped', () {
    final publication = Publication.admit(
      withNav(
        '<nav epub:type="toc"><ol>'
        '<li><a href="text/one.xhtml">  </a></li>'
        '<li><span>Part One</span><ol>'
        '<li><a href="text/one.xhtml#a">First</a></li>'
        '<li><a href="https://example.invalid/one.xhtml">Away</a></li>'
        '<li><a href="nav.xhtml">Contents</a></li>'
        '</ol></li>'
        '</ol></nav>',
      ),
    );
    expect(listed(publication), [
      ('Untitled chapter', 'text/one.xhtml', 0),
      ('First', 'text/one.xhtml#a', 1),
    ]);
  });

  test('a target fragment keeps its characters through the relative href', () {
    final publication = Publication.admit(
      withNav(
        '<nav epub:type="toc"><ol>'
        '<li><a href="text/one.xhtml#caf%C3%A9">Café</a></li>'
        '</ol></nav>',
      ),
    );
    final href = Uri.parse(publication.contents.single.href);
    expect(href.path, 'text/one.xhtml');
    expect(Uri.decodeComponent(href.fragment), 'café');
  });

  test(
    'a toc nested deeper than 16 levels lists the deep entries at depth 16',
    () {
      final nested = StringBuffer();
      for (var level = 0; level < 20; level++) {
        nested.write('<ol><li><a href="text/one.xhtml">Level $level</a>');
      }
      for (var level = 0; level < 20; level++) {
        nested.write('</li></ol>');
      }
      final publication = Publication.admit(
        withNav('<nav epub:type="toc">$nested</nav>'),
      );
      expect(publication.contents.map((entry) => entry.depth), [
        for (var level = 0; level < 20; level++) level < 16 ? level : 16,
      ]);
    },
  );

  test('a navigation document comes before the NCX, and the NCX fills in for '
      'a navigation document without a toc', () {
    const toc =
        '<nav epub:type="toc"><ol><li><a href="text/one.xhtml">From the nav</a></li></ol></nav>';
    expect(listed(Publication.admit(withNav(toc, ncx: true))), [
      ('From the nav', 'text/one.xhtml', 0),
    ]);
    expect(
      listed(
        Publication.admit(
          withNav(
            '<nav epub:type="landmarks"><ol><li><a href="text/one.xhtml">Start</a></li></ol></nav>',
            ncx: true,
          ),
        ),
      ),
      [('From the NCX', 'text/one.xhtml', 0)],
    );
  });

  test('an NCX link whose fragment is not UTF-8 leaves the contents and still '
      'admits the book', () {
    final publication = Publication.admit(
      epub2(
        navMap:
            '<navPoint><navLabel><text>Broken</text></navLabel>'
            '<content src="../text/one.xhtml#%FF"/></navPoint>'
            '<navPoint><navLabel><text>Two</text></navLabel>'
            '<content src="../text/two.xhtml"/></navPoint>',
      ),
    );
    expect(listed(publication), [('Two', 'text/two.xhtml', 0)]);
  });

  test('a book without a navigation document or an NCX has empty contents', () {
    final publication = Publication.admit(
      archive({
        'OPS/book.opf': package(
          '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>',
          '<itemref idref="one"/>',
        ),
        'OPS/one.xhtml': xhtml('<p>One</p>'),
      }),
    );
    expect(publication.contents, isEmpty);
  });

  test(
    'the book map puts each chapter of the contents at its target element',
    () async {
      final publication = Publication.admit(standardEbook());
      final book = (await BookMap.of(
        EpubDocument(publication),
        publication.contents,
        hop: <M, R>(FutureOr<R> Function(M) work, M input) async => work(input),
      ))!;
      int size(int part) =>
          publication.resources[publication.spine[part]]!.length;
      final whole = size(0) + size(1) + size(2);
      expect(
        [for (final chapter in book.chapters) chapter.title],
        ['Titlepage', 'I: The Road', 'Part Two', 'II'],
      );
      expect(
        [for (final chapter in book.chapters) chapter.start],
        [
          0,
          closeTo(size(0) / whole, 1e-9),
          closeTo((size(0) + size(1) * .5) / whole, 1e-9),
          closeTo((size(0) + size(1)) / whole, 1e-9),
        ],
      );
    },
  );

  test('the image sizes hold the width and height of every admitted PNG and '
      'JPEG, and of nothing else', () {
    final publication = Publication.admit(
      archive(
        {
          'OPS/book.opf': package(
            '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="png" href="images/plate.png" media-type="image/png"/>'
                '<item id="jpg" href="images/cover.jpg" media-type="image/jpeg"/>'
                '<item id="bad" href="images/broken.png" media-type="image/png"/>',
            '<itemref idref="one"/>',
          ),
          'OPS/one.xhtml': xhtml('<img src="images/plate.png" alt="Plate"/>'),
        },
        binary: {
          'OPS/images/plate.png': raster.encodePng(
            raster.Image(width: 3, height: 5),
          ),
          'OPS/images/cover.jpg': raster.encodeJpg(
            raster.Image(width: 7, height: 2),
          ),
          'OPS/images/broken.png': utf8.encode('not a png'),
        },
      ),
    );
    expect(publication.imageSizes, {
      'OPS/images/plate.png': (3, 5),
      'OPS/images/cover.jpg': (7, 2),
    });
    publication.checkInvariants();
  });
}
