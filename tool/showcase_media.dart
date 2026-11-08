// Made-up book files for the showcase fixture: EPUB books, a PDF with one
// scanned page, and long silent audio. All text is original filler written
// for screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// One chapter of a made-up book: a heading and its paragraphs.
typedef Chapter = (String, List<String>);

const firstFrost = <Chapter>[
  (
    'One. The Grafted Trees',
    [
      'Wren came back to the orchard on the first cold morning of October, '
          'when the grass along the lane was still white and the sun had not '
          'yet cleared the ridge. She left the car at the gate and walked the '
          'last of it, the way her grandmother always had.',
      'The rows were where she remembered them. The trees were not. Along the '
          'south wall, where the old russets had leaned for sixty years, the '
          'trunks wore pale new scars, neat as stitches, and above each scar '
          'the wood turned a different color.',
      'Someone had grafted them. Someone had cut the old crowns back to the '
          'knuckle and bound in a stranger\'s stock, and the stranger\'s '
          'stock had taken. She put her hand on the nearest union and felt '
          'the ridge of it under the bark, warm in a way that the air was not.',
      'In the village, nobody mentioned it. Mrs. Pell at the shop asked after '
          'the drive and the weather in the city. The postman said that the '
          'frost had come early this year, and looked at the floor while he '
          'said it.',
      '"Who has been looking after the trees?" Wren asked him.',
      '"The trees look after themselves," he said. "Mostly."',
    ],
  ),
  (
    'Two. The Ledger in the Barn',
    [
      'Her grandmother kept a ledger for the orchard, a long green book with '
          'a cloth spine, and Wren found it where it had always been: on the '
          'shelf above the grading table, between a tin of grease and a jar '
          'of copper nails.',
      'Every year had a page. Every page had the same columns, written in the '
          'same brown ink: the date of the first blossom, the date of the '
          'first frost, the weight of the harvest, and a last column with no '
          'heading at all.',
      'Most years, the last column was empty. In some years it held a single '
          'word. Rain. Bees. Gone. The year that Wren was born, it said Hers, '
          'and she did not know what that meant.',
      'The final page was dated two winters ago. The first frost was written '
          'in, and nothing else. No harvest. No blossom. And in the last '
          'column, in a hand that was not her grandmother\'s, a name she had '
          'never heard.',
    ],
  ),
  (
    'Three. What the Orchard Remembers',
    [
      'That night the wind turned and came down off the ridge, and Wren lay '
          'awake listening to the trees. Old trees creak. New wood is quiet. '
          'She could hear the difference from the bed, row by row, like a '
          'choir with half its voices missing.',
      'In the morning she walked the south wall again with the ledger under '
          'her arm. She counted the grafts. There were forty-one, one for '
          'each year that her grandmother had kept the book.',
      'A place remembers what the people in it would rather forget. Her '
          'grandmother used to say that about the house, about the kitchen '
          'where the floor dipped by the stove. Wren had thought it was a '
          'saying. Now she was not so sure.',
    ],
  ),
];

const saltAndLantern = <Chapter>[
  (
    'The Harbor Light',
    [
      'The lamp at the end of the harbor wall burned whale oil until the '
          'winter of the long ice, and then it burned whatever the town could '
          'spare. Tallow. Lard. Once, for three nights, the last of the '
          'church candles.',
      'Ada Quill kept it lit. She was twelve, and nobody had asked her to.',
      'Every evening she carried the can along the wall with the spray '
          'freezing on her sleeves, and every evening the boats that were '
          'still out turned their bows toward the small yellow point and came '
          'home.',
    ],
  ),
  (
    'Salt',
    [
      'In the spring the salt traders came back from the south with their '
          'carts, and the town paid them in fish and in stories. The traders '
          'had heard about the lamp. Everyone on the coast road had heard '
          'about the lamp.',
      'They wanted to meet the keeper. When they found a girl with chapped '
          'hands and a borrowed coat, they laughed, and then they stopped '
          'laughing, and the oldest of them gave her a lantern of blue glass '
          'that she kept for the rest of her life.',
    ],
  ),
];

const winterLedger = <Chapter>[
  (
    'January',
    [
      'The snow keeps its own accounts.\nIt writes the fox, the wren, the '
          'wheel,\nand every morning wipes the page\nfor someone else to '
          'sign.',
      'I walk the lane to read it\nbefore the plow comes through.\nMost '
          'days the only entry\nis the one I leave.',
    ],
  ),
  (
    'February',
    [
      'A thaw, and then a hard frost on the thaw.\nThe yard is glass. The '
          'hens refuse it.\nI owe the woodpile more than I can pay\nand the '
          'woodpile knows.',
    ],
  ),
];

const _windfallPages = [
  [
    'Windfall',
    'Book Three of The Orchard Cycle',
    '',
    'The storm came through in the last week of September and took the',
    'crop off the trees in a single night. By morning the grass between',
    'the rows was a floor of apples, bruised and split and still cold',
    'from the wind, and the whole valley smelled of cider.',
    '',
    'Wren stood at the kitchen window with her coffee and did the',
    'arithmetic. Windfalls do not keep. They can be pressed or fed to',
    'the pigs or left to the wasps, and the choice has to be made',
    'before noon, because by noon the wasps have made it for you.',
    '',
    'She pressed them. She pressed them for three days, with the old',
    'rack-and-cloth press from the barn and the help of anyone in the',
    'village who would come, and to her surprise most of the village',
    'came. They did not talk about the grafts. They did not talk about',
    'the ledger. They talked about the weather and the pulp and whose',
    'turn it was on the screw, and in the evenings they carried home',
    'jugs of sweet juice that would be something else by Christmas.',
  ],
  [
    'Two',
    '',
    '',
    'On the fourth day the press cracked along its oak beam, and the',
    'man who came to look at it was the man whose name was in the',
    'ledger. He was older than she expected. He walked the orchard',
    'with her in silence, stopping at each graft, and at the last',
    'one, by the gate, he put his palm flat on the bark the way she',
    'had done on her first morning.',
    '',
    '"Your grandmother asked me to do it," he said. "She knew that',
    'the old roots would outlast the old crowns. She wanted something',
    'here that would still be bearing when you came home."',
    '',
    'Wren looked down the rows at the bare trees, stripped by the',
    'storm, and at the new wood above every scar. Next year it would',
    'flower. She would write the date in the ledger, in the first',
    'column, and leave the last column empty for as long as she could.',
  ],
];

const _scannedPage = [
  'APPENDIX. FROM THE ORCHARD LEDGER',
  '',
  'Year      First blossom    First frost     Harvest',
  '1984      April 22         October 30      61 bushels',
  '1985      April 30         October 19      44 bushels',
  '1986      April 18         November 2      73 bushels',
  '',
  'Notes kept in the margin of the ledger, copied as written:',
  '',
  'Grafted the south wall with Ashmead stock, nine trees.',
  'Bees late this year. Wren born in the first week of May.',
  'Frost took the low rows. The high rows held.',
  'Pressed the windfalls with the whole village helping.',
];

/// An EPUB 3 book with a navigation document and one XHTML file per chapter.
Uint8List epub(String id, String title, String author, List<Chapter> chapters) {
  String escape(String text) =>
      const HtmlEscape(HtmlEscapeMode.element)
          .convert(text)
          .replaceAll('\n', '<br/>');
  final archive = Archive()
    ..add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    )
    ..add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    );
  final names = [
    for (var i = 0; i < chapters.length; i++) 'chapter${i + 1}.xhtml',
  ];
  archive.add(
    ArchiveFile.string(
      'OEBPS/content.opf',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">urn:bookfin:showcase:$id</dc:identifier>'
          '<dc:title>${escape(title)}</dc:title>'
          '<dc:creator>${escape(author)}</dc:creator>'
          '<dc:language>en</dc:language>'
          '<meta property="dcterms:modified">2026-11-07T00:00:00Z</meta>'
          '</metadata><manifest>'
          '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
          '<item id="css" href="style.css" media-type="text/css"/>'
          '${[for (final name in names) '<item id="${name.split('.').first}" href="$name" media-type="application/xhtml+xml"/>'].join()}'
          '</manifest><spine>'
          '${[for (final name in names) '<itemref idref="${name.split('.').first}"/>'].join()}'
          '</spine></package>',
    ),
  );
  archive.add(
    ArchiveFile.string(
      'OEBPS/style.css',
      'h1 { font-size: 1.4em; margin: 1.5em 0 1em; }\n'
          'p { margin: 0 0 0.8em; text-indent: 1.2em; line-height: 1.5; }\n'
          'h1 + p { text-indent: 0; }\n',
    ),
  );
  String page(String heading, String body) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">'
      '<head><title>${escape(heading)}</title>'
      '<link rel="stylesheet" type="text/css" href="style.css"/></head>'
      '<body>$body</body></html>';
  archive.add(
    ArchiveFile.string(
      'OEBPS/nav.xhtml',
      page(
        'Contents',
        '<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>'
            '${[for (var i = 0; i < chapters.length; i++) '<li><a href="${names[i]}">${escape(chapters[i].$1)}</a></li>'].join()}'
            '</ol></nav>',
      ),
    ),
  );
  for (var i = 0; i < chapters.length; i++) {
    final (heading, paragraphs) = chapters[i];
    archive.add(
      ArchiveFile.string(
        'OEBPS/${names[i]}',
        page(
          heading,
          '<section epub:type="chapter"><h1>${escape(heading)}</h1>'
          '${[for (final text in paragraphs) '<p>${escape(text)}</p>'].join()}'
          '</section>',
        ),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A letter-size PDF: two pages of real text and one scanned page, which is
/// only an image, so that the reader needs OCR to reflow it.
Uint8List pdfWithScan() {
  String literal(String text) =>
      '(${text.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)')})';
  final objects = <List<int>>[];
  int add(List<int> body) {
    objects.add(body);
    return objects.length;
  }

  List<int> stream(String dictionary, List<int> data) => [
    ...latin1.encode('<< $dictionary /Length ${data.length} >>\nstream\n'),
    ...data,
    ...latin1.encode('\nendstream'),
  ];

  final regular = add(
    latin1.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman '
      '/Encoding /WinAnsiEncoding >>',
    ),
  );
  final bold = add(
    latin1.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold '
      '/Encoding /WinAnsiEncoding >>',
    ),
  );
  // The page tree is written last, but each page names it as its parent.
  final pagesId = add(const []);
  final pageIds = <int>[];
  for (final lines in _windfallPages) {
    final text =
        StringBuffer('BT\n/F2 22 Tf 72 700 Td ${literal(lines[0])} Tj\n')
          ..write('/F1 13 Tf 0 -24 Td ${literal(lines[1])} Tj\n')
          ..write('/F1 12 Tf 16 TL 0 -16 Td\n');
    for (final line in lines.skip(2)) {
      text.write('${literal(line)} \'\n');
    }
    text.write('ET');
    final content = add(stream('', latin1.encode(text.toString())));
    pageIds.add(
      add(
        latin1.encode(
          '<< /Type /Page /Parent $pagesId 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 $regular 0 R /F2 $bold 0 R >> >> '
          '/Contents $content 0 R >>',
        ),
      ),
    );
  }
  final scan = scannedPage();
  final image = add(
    stream(
      '/Type /XObject /Subtype /Image /Width ${scan.width} '
      '/Height ${scan.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 '
      '/Filter /DCTDecode',
      img.encodeJpg(scan, quality: 70),
    ),
  );
  final draw = add(stream('', latin1.encode('q 612 0 0 792 0 0 cm /Im1 Do Q')));
  pageIds.add(
    add(
      latin1.encode(
        '<< /Type /Page /Parent $pagesId 0 R /MediaBox [0 0 612 792] '
        '/Resources << /XObject << /Im1 $image 0 R >> >> '
        '/Contents $draw 0 R >>',
      ),
    ),
  );
  objects[pagesId - 1] = latin1.encode(
    '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
    '/Count ${pageIds.length} >>',
  );
  final info = add(
    latin1.encode('<< /Title (Windfall) /Author (Mara Ellison) >>'),
  );
  final catalog = add(
    latin1.encode('<< /Type /Catalog /Pages $pagesId 0 R >>'),
  );
  final out = BytesBuilder()
    ..add(latin1.encode('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n'));
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(latin1.encode('${i + 1} 0 obj\n'));
    out.add(objects[i]);
    out.add(latin1.encode('\nendobj\n'));
  }
  final xref = out.length;
  out.add(
    latin1.encode('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n'),
  );
  for (final offset in offsets) {
    out.add(latin1.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(
    latin1.encode(
      'trailer\n<< /Size ${objects.length + 1} /Root $catalog 0 R '
      '/Info $info 0 R >>\nstartxref\n$xref\n%%EOF\n',
    ),
  );
  return out.toBytes();
}

/// A gray page image at 150 dots per inch with typewriter-like text and a
/// little paper noise, like a photocopy.
img.Image scannedPage() {
  final page = img.Image(width: 1275, height: 1650);
  img.fill(page, color: img.ColorUint8.rgb(236, 236, 236));
  var seed = 7;
  int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  for (var i = 0; i < 9000; i++) {
    final shade = 180 + next() % 50;
    page.setPixelRgb(next() % 1275, next() % 1650, shade, shade, shade);
  }
  var y = 180;
  for (final line in _scannedPage) {
    img.drawString(
      page,
      line,
      font: img.arial24,
      x: 150,
      y: y,
      color: img.ColorUint8.rgb(40, 40, 40),
    );
    y += 44;
  }
  return page;
}

/// Silent mono AAC audio of the given length, encoded once by FFmpeg from the
/// dev shell and kept under `.cache/showcase`.
///
/// AAC encodes digital silence in about 350 bytes a second, so a 10-hour book
/// is only 13 MB. With [fullSize], the audio is noise at -66 dBFS, which
/// AAC cannot compress, at 64 kbit/s: a 10-hour book is about 300 MB, the
/// size of a real audiobook. Use it to measure work that grows with file
/// size, such as reads and hashes.
Future<Uint8List> silence(Duration length, {bool fullSize = false}) async {
  final file = File(
    '.cache/showcase/${fullSize ? 'quiet' : 'silence'}-${length.inSeconds}.m4a',
  );
  if (!file.existsSync()) {
    await file.parent.create(recursive: true);
    final partial = '${file.path}.partial.m4a';
    final result = await Process.run('ffmpeg', [
      '-y',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      fullSize ? 'anoisesrc=r=44100:a=0.0005' : 'anullsrc=r=8000:cl=mono',
      '-t',
      '${length.inSeconds}',
      '-c:a',
      'aac',
      '-b:a',
      fullSize ? '64k' : '8k',
      '-f',
      'mp4',
      partial,
    ]);
    if (result.exitCode != 0) {
      throw StateError('ffmpeg failed: ${result.stderr}');
    }
    await File(partial).rename(file.path);
  }
  return file.readAsBytes();
}
