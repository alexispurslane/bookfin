import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:xml/xml.dart';

Uint8List epub({String? chapter, Map<String, List<int>> extra = const {}}) {
  final entries = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    ),
    'OPS/book.opf': utf8.encode(
      '<package version="3.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="png" href="dot.png" media-type="image/png"/><item id="css" href="book.css" media-type="text/css"/><item id="svg" href="active.svg" media-type="image/svg+xml"/></manifest><spine><itemref idref="one"/></spine></package>',
    ),
    'OPS/one.xhtml': utf8.encode(
      chapter ?? '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>River</title><link rel="stylesheet" href="book.css"/></head><body><h1 id="start">River</h1><p>A river <em>follows</em> the road.</p><img src="dot.png" alt="Sepia square"/><img src="active.svg" alt="Cover drawing"/></body></html>',
    ),
    'OPS/book.css': utf8.encode(
      'body{color:#39291f} p{background:url(https://evil.invalid/pixel)}',
    ),
    'OPS/dot.png': File('tool/research/readers/fixtures/dot.png')
        .readAsBytesSync(),
    'OPS/active.svg': utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><image href="https://evil.invalid/pixel"/></svg>',
    ),
    ...extra,
  };
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('rewritten wrapper references cannot bypass processed resource limits', () {
    final name = '${List.filled(400, 'c').join()}.jpg';
    final package = utf8
        .decode(ZipDecoder().decodeBytes(epub()).find('OPS/book.opf')!.content)
        .replaceFirst(
          '</manifest>',
          '<item id="jpg" href="$name" media-type="image/jpeg"/></manifest>',
        );
    final bytes = epub(
      chapter:
          '<html><head/><body>${List.filled(45000, '<img src="active.svg"/>').join()}</body></html>',
      extra: {
        'OPS/book.opf': utf8.encode(package),
        'OPS/$name': raster.encodeJpg(raster.Image(width: 2, height: 3)),
        'OPS/active.svg': utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 2 3" preserveAspectRatio="xMidYMid meet"><image width="2" height="3" xlink:href="$name"/></svg>',
        ),
      },
    );
    expect(() => Publication.admit(bytes), throwsFormatException);
  });

  test(
    'EPUB2 keeps its admitted contents document in the package manifest',
    () {
      final publication = Publication.admit(
        epub(
          extra: {
            'OPS/book.opf': utf8.encode(
              '<package version="2.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="toc"><itemref idref="one"/></spine></package>',
            ),
            'OPS/toc.ncx': utf8.encode(
              '<ncx><navMap><navPoint id="start"><navLabel><text>River opening</text></navLabel><content src="one.xhtml#start"/></navPoint></navMap></ncx>',
            ),
          },
        ),
      );
      final package = XmlDocument.parse(
        utf8.decode(publication.resources['OPS/book.opf']!),
      );
      final contents = package
          .findAllElements('item')
          .where((item) => item.getAttribute('id') == 'toc');
      expect(contents, hasLength(1));
      expect(contents.single.getAttribute('href'), 'toc.ncx');
      expect(publication.resources['OPS/toc.ncx'], isNotNull);
    },
  );

  test('publication code and active SVG cannot reach reading resources', () {
    final publication = Publication.admit(
      epub(
        chapter: '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Book</title></head><body onload="alert(1)"><h1>Heading</h1><script>alert(1)</script><iframe src="https://evil.invalid"/><img src="active.svg" alt="Cover drawing"/><p>Readable</p></body></html>',
      ),
    );
    final body = utf8.decode(publication.resources['OPS/one.xhtml']!);
    final document = XmlDocument.parse(body);
    expect(document.findAllElements('script'), isEmpty);
    expect(document.findAllElements('iframe'), isEmpty);
    expect(body, isNot(contains('onload')));
    expect(body, contains('Cover drawing'));
    expect(body, contains('Unsupported image'));
    expect(publication.resources.containsKey('OPS/active.svg'), isFalse);
    expect(document.findAllElements('h1').single.innerText, 'Heading');
  });

  test('remote CSS URLs cannot leave the passive publication', () {
    final publication = Publication.admit(epub());
    expect(
      utf8.decode(publication.resources['OPS/book.css']!),
      isNot(contains('evil.invalid')),
    );
  });

  test('archive aliases cannot overwrite a local resource', () {
    expect(
      () => Publication.admit(
        epub(extra: {'OPS/../one.xhtml': utf8.encode('alias')}),
      ),
      throwsFormatException,
    );
  });

  test('an admitted publication keeps its resources unchanged and its identity '
      'follows its content', () {
    final publication = Publication.admit(epub());
    expect(
      publication.resources['OPS/dot.png'],
      File('tool/research/readers/fixtures/dot.png').readAsBytesSync(),
    );
    expect(
      () => publication.resources['OPS/dot.png']![0] = 0,
      throwsUnsupportedError,
    );
    expect(Publication.admit(epub()).identity, publication.identity);
    expect(
      Publication.admit(
        epub(chapter: '<html><head/><body>Changed</body></html>'),
      ).identity,
      isNot(publication.identity),
    );
    publication.checkInvariants();
  });

  test('local styles, PNG, fonts, headings, and encoded destination fragments survive', () {
    final font = File('docs/mockups/fonts/source-serif-4-latin.woff2')
        .readAsBytesSync();
    final opf = utf8
        .decode(ZipDecoder().decodeBytes(epub()).find('OPS/book.opf')!.content)
        .replaceFirst(
          '</manifest>',
          '<item id="font" href="Fonts/font.woff2" media-type="font/woff2"/></manifest>',
        );
    final publication = Publication.admit(
      epub(
        chapter: '<html lang="fr"><head><link rel="stylesheet" href="book.css"/></head><body><h1 id="café">Title</h1><a href="#caf%C3%A9">Go</a><img src="dot.png" alt="Sepia square"/></body></html>',
        extra: {
          'OPS/book.opf': utf8.encode(opf),
          'OPS/Fonts/font.woff2': font,
          'OPS/book.css': utf8.encode(
            '@font-face{font-family:Book;src:url("Fonts/font.woff2")}body{font-family:Book}',
          ),
        },
      ),
    );
    final document = XmlDocument.parse(
      utf8.decode(publication.resources['OPS/one.xhtml']!),
    );
    expect(
      document.findAllElements('a').single.getAttribute('href'),
      'one.xhtml#caf%C3%A9',
    );
    expect(
      document.findAllElements('img').single.getAttribute('alt'),
      'Sepia square',
    );
    expect(document.findAllElements('h1').single.getAttribute('id'), 'café');
    expect(publication.resources['OPS/Fonts/font.woff2'], font);
    expect(
      utf8.decode(publication.resources['OPS/book.css']!),
      contains('font-family:Book'),
    );
  });

  test('only the exact local single-JPEG SVG wrapper uses a raster fallback', () {
    final jpeg = raster.encodeJpg(
      raster.Image(width: 2, height: 3)..setPixelRgb(0, 0, 255, 0, 0),
    );
    final opf = utf8
        .decode(ZipDecoder().decodeBytes(epub()).find('OPS/book.opf')!.content)
        .replaceFirst(
          '</manifest>',
          '<item id="jpg" href="cover.jpg" media-type="image/jpeg"/></manifest>',
        );
    const wrapper =
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 2 3" preserveAspectRatio="xMidYMid meet"><image width="2" height="3" xlink:href="cover.jpg"/></svg>';
    for (final svg in [
      wrapper,
      wrapper.replaceFirst('width="100%"', 'onload="alert(1)" width="100%"'),
      wrapper.replaceFirst('cover.jpg', 'https://evil.invalid/cover.jpg'),
      wrapper.replaceFirst('0 0 2 3', '0 0 3 2'),
    ]) {
      final publication = Publication.admit(
        epub(
          extra: {
            'OPS/book.opf': utf8.encode(opf),
            'OPS/cover.jpg': jpeg,
            'OPS/active.svg': utf8.encode(svg),
          },
        ),
      );
      final chapter = utf8.decode(publication.resources['OPS/one.xhtml']!);
      expect(publication.resources['OPS/cover.jpg'], jpeg);
      expect(chapter.contains('src="cover.jpg"'), svg == wrapper);
      expect(
        chapter.contains('Unsupported image: Cover drawing'),
        svg != wrapper,
      );
      expect(publication.resources.containsKey('OPS/active.svg'), isFalse);
    }
  });

  test('unsafe reference and active attribute forms never enter XHTML', () {
    for (final reference in [
      'https://evil.invalid/x',
      '//evil.invalid/x',
      'javascript:alert(1)',
      'data:image/svg+xml,active',
      'file:///tmp/x',
      '../../../x',
      'dot.png?track=1',
      'dot%2fpng',
    ]) {
      final publication = Publication.admit(
        epub(
          chapter:
              '<html><head/><body><h2>Keep</h2><a href="$reference" onclick="bad()">Link</a><img src="$reference" alt="Description"/><form action="https://evil.invalid"><p>Keep paragraph</p></form></body></html>',
        ),
      );
      final document = utf8.decode(publication.resources['OPS/one.xhtml']!);
      expect(document, isNot(contains('onclick')));
      expect(document, isNot(contains('evil.invalid')));
      expect(document, contains('Unsupported image: Description'));
      expect(document, contains('Keep paragraph'));
    }
  });

  test('XML entities, encrypted books, and oversized resources fail before rendering', () {
    expect(
      () => Publication.admit(
        epub(
          chapter: '<!DOCTYPE html [<!ENTITY remote SYSTEM "file:///etc/passwd">]><html><body>&remote;</body></html>',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => Publication.admit(
        epub(extra: {'META-INF/encryption.xml': utf8.encode('<encryption/>')}),
      ),
      throwsFormatException,
    );
    expect(
      () => Publication.admit(
        epub(extra: {'huge': Uint8List(Publication.maxResourceBytes + 1)}),
      ),
      throwsFormatException,
    );
  });

  test(
    'the committed public-domain EPUB becomes a passive navigable publication',
    () {
      final publication = Publication.admit(
        File('tool/research/readers/fixtures/river.epub').readAsBytesSync(),
      );
      expect(publication.spine, isNotEmpty);
      final content = publication.spine
          .map((path) => utf8.decode(publication.resources[path]!))
          .join();
      expect(content, contains('The river follows the old road.'));
      expect(content, isNot(contains('<script')));
    },
  );

  test(
    'local CSS imports stay local and retain the imported publisher styles',
    () {
      final opf = utf8
          .decode(
            ZipDecoder().decodeBytes(epub()).find('OPS/book.opf')!.content,
          )
          .replaceFirst(
            '</manifest>',
            '<item id="extra-css" href="Styles/extra.css" media-type="text/css"/></manifest>',
          );
      final publication = Publication.admit(
        epub(
          extra: {
            'OPS/book.opf': utf8.encode(opf),
            'OPS/book.css': utf8.encode(
              '@import "Styles/extra.css";body{color:#39291f}',
            ),
            'OPS/Styles/extra.css': utf8.encode('h1{font-weight:700}'),
          },
        ),
      );
      expect(
        utf8.decode(publication.resources['OPS/book.css']!),
        contains('Styles/extra.css'),
      );
      expect(
        utf8.decode(publication.resources['OPS/Styles/extra.css']!),
        contains('font-weight:700'),
      );
    },
  );
}
