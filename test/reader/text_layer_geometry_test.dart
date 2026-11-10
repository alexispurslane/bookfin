import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;

const equationPage = 'test/reader/fixtures/reflow/equation-page.pdf';

/// The width and the height of the equation page in PDF points (A5).
const pageWidth = 419.5275573730469, pageHeight = 595.2755737304688;

/// The printed lines of the equation page, each as its words joined by one
/// space. U+0002 is pdfium's mark of a hyphen that ends a line.
const printedLines = [
  'Falling Bodies',
  'A stone that falls from rest gains speed at a steady rate. After a',
  'time 𝑡 it moves at 𝑣 = 𝑔𝑡, and it has fallen a distance of 𝑔𝑡 2/2. The',
  'square of the time is the reason that a fall of twice the height takes',
  'less than twice as long.',
  'If the stone starts with a speed 𝑢, its speed after a fall through a',
  'height ℎ follows from the same rule:',
  '𝑣 2 = 𝑢 2 + 2𝑔ℎ',
  'The table gives three falls that the rule predicts.',
  'Body Height Time',
  'Stone 5 m 1.0 s',
  'Apple 20 m 2.0 s',
  'Measurements of extraordinarily unhurried descents through viscous',
  'atmospheres nevertheless demonstrate approximately identical accel\u0002',
  'erations, notwithstanding considerable differences between individual',
  'specimens.',
];

/// Character boxes that set each line of [lines] 20 points below the one
/// before it, 6 points a character, with one box for each UTF-16 code unit
/// of the text that joins the lines with '\n'. Left, top, right and bottom
/// in PDF points, y up, on a page 400 by 600 points.
({String source, Float64List boxes}) setLines(List<String> lines) {
  final source = lines.join('\n');
  final boxes = Float64List(source.length * 4);
  var index = 0;
  for (final (row, line) in lines.indexed) {
    final baseline = 560.0 - row * 20;
    for (var column = 0; column <= line.length; column++) {
      if (index == source.length) break;
      final left = 20.0 + column * 6;
      boxes.setAll(index * 4, [left, baseline + 8, left + 5, baseline]);
      index++;
    }
  }
  return (source: source, boxes: boxes);
}

PreparedPdfPage prepare(({String source, Float64List boxes}) page) =>
    preparePdfPage((
      source: page.source,
      boxes: page.boxes,
      width: 400,
      height: 600,
    ));

/// The text of each word of [words], as its range names it.
List<String> wordTexts(PdfText text, TextLayerWords words) => [
  for (var word = 0; word < words.geometry.wordCount; word++)
    text.source.substring(
      words.attachment[word * 2],
      words.attachment[word * 2 + 1],
    ),
];

Uint8List rotatedTextPage() {
  const drawing =
      'BT /F1 12 Tf 60 300 Td (The river flows) Tj '
      '380 -40 Td (Far field) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 400] /Rotate 90 '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${drawing.length} >>\nstream\n$drawing\nendstream',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(output.length);
    output.write('${index + 1} 0 obj\n$object\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 6\n0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(ascii.encode(output.toString()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  late List<Function> hopped;

  Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) {
    hopped.add(work);
    return runInWorker(work, input);
  }

  Future<PdfBook> open(String path) async {
    final book = await PdfRuntime.instance.open(
      await File(path).readAsBytes(),
      'd' * 64,
      hop: hop,
    );
    addTearDown(book.dispose);
    return book;
  }

  /// The equation page's text, geometry and attachment, through [PdfBook].
  Future<(PdfText, TextLayerWords)> equationWords() async {
    final pdf = await open(equationPage);
    final geometry = (await pdf.geometry(1))!;
    final attached = await pdf.attachedText(1, geometry);
    return (
      attached.text,
      (geometry: geometry, attachment: attached.attachment!),
    );
  }

  setUp(() => hopped = []);
  tearDownAll(() => PdfRuntime.instance.shutdown());

  test('each word of a text layer page is a run of its text without white '
      'space, and its box holds its characters\' boxes', () async {
    final (text, words) = await equationWords();
    final document = await native.PdfDocument.openFile(equationPage);
    addTearDown(document.dispose);
    final page = document.pages.single;
    final raw = (await page.loadText())!;
    expect(raw.fullText, text.source);

    expect(
      wordTexts(text, words),
      RegExp(r'[^\s\u0002]*\u0002|[^\s\u0002]+')
          .allMatches(text.source)
          .map((match) => match[0]),
    );
    final boxes = words.geometry.boxes;
    for (var word = 0; word < words.geometry.wordCount; word++) {
      for (
        var character = words.attachment[word * 2];
        character < words.attachment[word * 2 + 1];
        character++
      ) {
        final box = raw.charRects[character];
        const slack = 1e-4;
        expect(
          boxes[word * 4] <= box.left / page.width + slack &&
              boxes[word * 4 + 1] <=
                  (page.height - box.top) / page.width + slack &&
              boxes[word * 4 + 2] >= box.right / page.width - slack &&
              boxes[word * 4 + 3] >=
                  (page.height - box.bottom) / page.width - slack,
          isTrue,
          reason: 'word $word holds character $character',
        );
      }
    }
    words.geometry.checkInvariants(
      attachment: words.attachment,
      source: text.source,
    );
  });

  test('the words of the equation page fall into its printed lines', () async {
    final (text, words) = await equationWords();
    final geometry = words.geometry;
    final texts = wordTexts(text, words);
    expect([
      for (var line = 0; line < geometry.lineCount; line++)
        texts
            .sublist(geometry.lineStarts[line], geometry.lineStarts[line + 1])
            .join(' '),
    ], printedLines);
  });

  test('a line\'s baseline sits on the bottoms of its letters, above the '
      'descenders and below the raised marks', () async {
    final (text, words) = await equationWords();
    final geometry = words.geometry;
    // On the printed line "height ℎ follows from the same rule:", the h of
    // "height" sits on the baseline at y = 424.84 points, and its g
    // descends to 422.25 points.
    final line = printedLines.indexOf('height ℎ follows from the same rule:');
    final height = geometry.lineStarts[line];
    expect(
      geometry.lineBaselineAt(line, 0.5),
      closeTo((pageHeight - 424.8) / pageWidth, 0.3 / pageWidth),
    );
    expect(
      geometry.ownBaselines[height * 2],
      closeTo((pageHeight - 424.8) / pageWidth, 0.3 / pageWidth),
    );
    expect(
      geometry.boxes[height * 4 + 3],
      closeTo((pageHeight - 422.25) / pageWidth, 0.01 / pageWidth),
    );
    // The display equation's squares are raised marks. Its baseline is the
    // bottom of its v at y = 402.44 points.
    final equation = printedLines.indexOf('𝑣 2 = 𝑢 2 + 2𝑔ℎ');
    expect(
      geometry.lineBaselineAt(equation, 0.5),
      closeTo((pageHeight - 402.44) / pageWidth, 0.3 / pageWidth),
    );
    final square = geometry.lineStarts[equation] + 1;
    expect(text.source.substring(words.attachment[square * 2]).trim()[0], '2');
    expect(
      geometry.ownBaselines[square * 2],
      lessThan(geometry.lineBaselineAt(equation, 0.5) - 3 / pageWidth),
    );
  });

  test('a word\'s own baseline is the bottom of its letters without '
      'descenders', () {
    final page = setLines(['The gappy river']);
    final boxes = Float64List.fromList(page.boxes);
    for (var index = 0; index < page.source.length; index++) {
      if ('gpy'.contains(page.source[index])) boxes[index * 4 + 3] -= 3;
    }
    final words = prepare((source: page.source, boxes: boxes)).words!;
    // The letters sit on y = 560 points of a page 600 points high and 400
    // wide. The g, the p's and the y reach 3 points lower.
    expect(words.geometry.ownBaselines[1 * 2], closeTo(40 / 400, 1e-6));
    expect(words.geometry.boxes[1 * 4 + 3], closeTo(43 / 400, 1e-6));
    expect(words.geometry.lineBaselineAt(0, 0.5), closeTo(40 / 400, 1e-6));
  });

  test('the centered display equation is a block of its own', () async {
    final (_, words) = await equationWords();
    final geometry = words.geometry;
    final equation = printedLines.indexOf('𝑣 2 = 𝑢 2 + 2𝑔ℎ');
    final block = [
      for (var block = 0; block < geometry.blockCount; block++)
        if (geometry.blockStarts[block] == equation) block,
    ].single;
    expect(geometry.blockStarts[block + 1], equation + 1);
    expect(geometry.blockKind(block), PageBlockKind.text);
    expect(geometry.paragraphStarts, isEmpty);
    for (var block = 0; block < geometry.blockCount; block++) {
      final first = geometry.lineStarts[geometry.blockStarts[block]];
      final end = geometry.lineStarts[geometry.blockStarts[block + 1]];
      for (var word = first; word < end; word++) {
        expect(
          geometry.blockBoxes[block * 4] <= geometry.boxes[word * 4] &&
              geometry.blockBoxes[block * 4 + 1] <=
                  geometry.boxes[word * 4 + 1] &&
              geometry.blockBoxes[block * 4 + 2] >=
                  geometry.boxes[word * 4 + 2] &&
              geometry.blockBoxes[block * 4 + 3] >=
                  geometry.boxes[word * 4 + 3],
          isTrue,
          reason: 'block $block holds word $word',
        );
      }
    }
  });

  test('a gap of more than two line pitches above a line starts a new '
      'block', () {
    final page = setLines([
      'The river runs',
      'on to the sea.',
      'The sea is near',
      'the old road.',
    ]);
    final apart = Float64List.fromList(page.boxes);
    for (
      var index = page.source.indexOf('The sea');
      index < page.source.length;
      index++
    ) {
      apart[index * 4 + 1] -= 30;
      apart[index * 4 + 3] -= 30;
    }
    // The lines are 20 points apart, and 8 points tall: a gap of 12 points.
    // The third line moves 30 points lower, so its gap is 42 points.
    expect(prepare(page).words!.geometry.blockStarts, [0, 4]);
    expect(
      prepare((source: page.source, boxes: apart)).words!.geometry.blockStarts,
      [0, 2, 4],
    );
  });

  test('a word that ends a line with a hyphen records the hyphen\'s '
      'width', () async {
    final (text, words) = await equationWords();
    final texts = wordTexts(text, words);
    final hyphenated = texts.indexOf('accel\u0002');
    // pdfium's box of the hyphen spans x = 367.27 to 370.11 points.
    expect(
      words.geometry.hyphens[hyphenated],
      closeTo((370.11 - 367.27) / pageWidth, 0.01 / pageWidth),
    );
    expect(
      [
        for (var word = 0; word < texts.length; word++)
          if (words.geometry.hyphens[word] != 0) texts[word],
      ],
      ['accel\u0002'],
    );
  });

  test('a text layer page makes its text and its words in one hop', () async {
    final pdf = await open(equationPage);
    final text = await pdf.text(1);
    final geometry = (await pdf.geometry(1))!;
    final attached = await pdf.attachedText(1, geometry);
    expect(hopped, [preparePdfPage]);
    expect(attached.text.digest, text.digest);
    expect(geometry.wordCount, greaterThan(100));
  });

  group('words entirely outside the page do not hide its printed words', () {
    final original = setLines([
      'The river flows',
      'Printer proof',
      'runs with accel\u0002',
      'eration.',
    ]);
    final first = original.source.indexOf('Printer');
    final end = original.source.indexOf('\n', first);

    for (final (edge, horizontal, vertical) in [
      ('left', -200.0, 0.0),
      ('right', 400.0, 0.0),
      ('top', 0.0, 80.0),
      ('bottom', 0.0, -600.0),
    ]) {
      test(
        'outside the $edge edge, with unchanged reading text and places',
        () {
          final boxes = Float64List.fromList(original.boxes);
          for (var unit = first; unit < end; unit++) {
            boxes[unit * 4] += horizontal;
            boxes[unit * 4 + 1] += vertical;
            boxes[unit * 4 + 2] += horizontal;
            boxes[unit * 4 + 3] += vertical;
          }
          final page = prepare((source: original.source, boxes: boxes));
          final before = prepare(original).text;
          expect(page.text.status, PdfTextStatus.candidate);
          expect(page.text.source, original.source);
          expect(page.text.text, before.text);
          expect(page.text.sourceOffsets, before.sourceOffsets);
          expect(page.text.digest, before.digest);
          expect(page.words, isNotNull);
          final words = page.words!;
          expect(wordTexts(page.text, words), [
            'The',
            'river',
            'flows',
            'runs',
            'with',
            'accel\u0002',
            'eration.',
          ]);
          expect(words.attachment[6], original.source.indexOf('runs'));
          expect(words.geometry.hyphens[5], closeTo(5 / 400, 1e-6));
          words.geometry.checkInvariants(
            attachment: words.attachment,
            source: page.text.source,
          );
        },
      );
    }
  });

  test('rotated page coordinates never discard visible words as off-page '
      'printing labels', () async {
    final pdf = await PdfRuntime.instance.open(rotatedTextPage(), 'd' * 64);
    addTearDown(pdf.dispose);
    final text = await pdf.text(1);
    expect(text.status, PdfTextStatus.candidate);
    expect(text.text, 'The river flows Far field');
    expect(await pdf.geometry(1), isNull);
    final reread = await pdf.text(1);
    expect(reread.source, text.source);
    expect(reread.digest, text.digest);
  });

  group('unusable character boxes give the page no words, and its text '
      'stays the same', () {
    final usable = setLines(['The river', 'runs to the sea.']);

    void expectNoWords(Float64List boxes) {
      final page = prepare((source: usable.source, boxes: boxes));
      final good = prepare(usable);
      expect(good.words, isNotNull);
      expect(page.words, isNull);
      expect(page.text.status, PdfTextStatus.candidate);
      expect(page.text.text, good.text.text);
      expect(page.text.digest, good.text.digest);
    }

    test('a letter without a box of positive area', () {
      final boxes = Float64List.fromList(usable.boxes);
      boxes[5 * 4 + 2] = boxes[5 * 4]; // The "i" of "river" has no width.
      expectNoWords(boxes);
    });

    test('a letter outside the page', () {
      final boxes = Float64List.fromList(usable.boxes);
      boxes[6 * 4 + 2] = 401; // The "v" of "river" ends past the page.
      expectNoWords(boxes);
    });

    test('a word taller than three lines', () {
      final boxes = Float64List.fromList(usable.boxes);
      boxes[0 * 4 + 1] = 560 + 8 + 70; // The "T" rises 70 points.
      expectNoWords(boxes);
    });

    test('every word is outside the page', () {
      final boxes = Float64List.fromList(usable.boxes);
      for (var unit = 0; unit < usable.source.length; unit++) {
        boxes[unit * 4 + 1] += 100;
        boxes[unit * 4 + 3] += 100;
      }
      expectNoWords(boxes);
    });

    test('an outside word has a character without positive area', () {
      final boxes = Float64List.fromList(usable.boxes);
      for (var unit = 0; unit < 3; unit++) {
        boxes[unit * 4 + 1] += 100;
        boxes[unit * 4 + 3] += 100;
      }
      boxes[2] = boxes[0];
      expectNoWords(boxes);
    });
  });

  test('a page whose text layer is not a candidate gives no words from its '
      'character boxes', () {
    final absent = prepare(setLines([' ', ' ']));
    expect(absent.text.status, PdfTextStatus.absent);
    expect(absent.words, isNull);
    final page = setLines(['The river']);
    final unreliable = preparePdfPage((
      source: page.source,
      boxes: Float64List(4),
      width: 400,
      height: 600,
    ));
    expect(unreliable.text.status, PdfTextStatus.unreliable);
    expect(unreliable.words, isNull);
  });

  // Recorded with the code before tb-xwlj. Saved places name a page's text
  // by its digest, so word geometry must not change them.
  test('text layer pages keep the reading text and digest that they had '
      'before word geometry', () async {
    final pages = {
      (equationPage, 1): (
        PdfTextStatus.candidate,
        'c7be9db9046159529930f59de8a4d3c1ae6baf69459ab5621b50ccccb53ce85c',
      ),
      ('tool/research/readers/fixtures/simple.pdf', 1): (
        PdfTextStatus.candidate,
        '6809befa2062965afe8125645eb4e02934d3edbf04af2c75be151563f835558e',
      ),
      ('tool/research/readers/fixtures/simple.pdf', 2): (
        PdfTextStatus.candidate,
        '578cbaabc45fbdc4510f6166f42cc3a7a72654e9c4cbcff31581c7dbb88cccc4',
      ),
      ('tool/research/readers/fixtures/columns.pdf', 1): (
        PdfTextStatus.unreliable,
        'ad8b3e02f96e282340b6d28a36f1f0e9b10cea9f058cdbc3834417abe9df7520',
      ),
      ('tool/research/readers/fixtures/table.pdf', 1): (
        PdfTextStatus.unreliable,
        'b64ca4e0b42dc74161a9db8e35fb5303e613edecd9df88a754dcde041c448960',
      ),
    };
    for (final MapEntry(key: (path, page), value: (status, digest))
        in pages.entries) {
      final pdf = await open(path);
      final text = await pdf.text(page);
      expect(text.status, status, reason: '$path $page');
      expect(pdfTextDigest(text.source), digest, reason: '$path $page');
      expect(
        text.digest,
        status == PdfTextStatus.candidate ? digest : isNull,
        reason: '$path $page',
      );
      expect(text.text, text.source.trim().split(RegExp(r'\s+')).join(' '));
    }
    final pdf = await open(equationPage);
    expect(
      (await pdf.text(1)).text,
      'Falling Bodies A stone that falls from rest gains speed at a steady '
      'rate. After a time 𝑡 it moves at 𝑣 = 𝑔𝑡, and it has fallen a '
      'distance of 𝑔𝑡 2/2. The square of the time is the reason that a fall '
      'of twice the height takes less than twice as long. If the stone '
      'starts with a speed 𝑢, its speed after a fall through a height ℎ '
      'follows from the same rule: 𝑣 2 = 𝑢 2 + 2𝑔ℎ The table gives three '
      'falls that the rule predicts. Body Height Time Stone 5 m 1.0 s Apple '
      '20 m 2.0 s Measurements of extraordinarily unhurried descents through '
      'viscous atmospheres nevertheless demonstrate approximately identical '
      'accel\u0002erations, notwithstanding considerable differences between '
      'individual specimens.',
    );
  });
}
