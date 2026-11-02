import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart' hide Image;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:pdfrx/pdfrx.dart';

import 'reader_probe.dart';
import 'license_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  LicenseRegistry.addLicense(() async* {
    final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in assets.listAssets().where(
      (path) => path.startsWith('assets/licenses/'),
    )) {
      final data = await rootBundle.load(path);
      yield LicenseEntryWithLineBreaks(
        [path.split('/').last],
        decodeLicense(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    }
  });
  runApp(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xff895c3a)),
      home: const ReaderFiniteProof(),
    ),
  );
}

class ReaderFiniteProof extends StatefulWidget {
  const ReaderFiniteProof({super.key});

  @override
  State<ReaderFiniteProof> createState() => _ReaderFiniteProofState();
}

class _ReaderFiniteProofState extends State<ReaderFiniteProof> {
  final _sources = <({int page, String text, int character})>[];
  final _images = <ui.Image>[];
  final _books = <({String name, String text, Uint8List image})>[];
  late final Future<void> _loading;
  PdfDocument? _document;
  PdfDocument? _scan;
  Directory? _work;
  var _view = 'Original';
  var _sourcePage = 1;
  var _width = 360.0;
  var _bookIndex = 0;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<Uint8List> _asset(String name) async =>
      (await rootBundle.load('assets/$name')).buffer.asUint8List();

  Future<ui.Image> _render(PdfPage page) async {
    final image = await page.render(
      fullWidth: 360,
      fullHeight: page.height * 360 / page.width,
    );
    if (image == null) throw StateError('Original page did not render');
    try {
      return await image.createImage();
    } finally {
      image.dispose();
    }
  }

  Future<void> _load() async {
    final source = await _asset('simple.pdf');
    _document = await PdfDocument.openData(source, sourceName: 'simple.pdf');
    final anchors = <Map<String, Object>>[];
    for (final page in _document!.pages) {
      final extracted = (await page.loadText())!;
      final character = extracted.fullText.indexOf('old road');
      if (character < 0) throw StateError('Source phrase was not extracted');
      final rectangle = extracted.charRects[character];
      final text = extracted.fullText.replaceAll(RegExp(r'\s+'), ' ').trim();
      _sources.add((page: page.pageNumber, text: text, character: character));
      _images.add(await _render(page));
      final layouts = <String, int>{};
      for (final width in [200.0, 360.0]) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: 18, height: 1.4),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: width);
        layouts['${width.toInt()}'] = painter.computeLineMetrics().length;
        painter.dispose();
      }
      if (layouts['200']! <= layouts['360']!)
        throw StateError('Narrow text did not reflow');
      anchors.add({
        'source_page_1_based': page.pageNumber,
        'character_index_utf16': character,
        'quote': extracted.fullText.substring(character, character + 8),
        'rectangle_pdf_points': [
          rectangle.left,
          rectangle.top,
          rectangle.right,
          rectangle.bottom,
        ],
        'body_logical_pixels': 18,
        'line_counts_by_width_logical_pixels': layouts,
        'render_pixels': [360, _images.last.height],
      });
    }
    _scan = await PdfDocument.openData(
      await _asset('scanned.pdf'),
      sourceName: 'scanned.pdf',
    );
    final scanText = (await _scan!.pages.first.loadText())!.fullText;
    if (scanText.trim().isNotEmpty)
      throw StateError('Scan unexpectedly has extracted text');
    _images.add(await _render(_scan!.pages.first));
    final conversion = DynamicLibrary.open('libreader_convert.so')
        .lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('bookfin_convert');
    _work = await Directory.systemTemp.createTemp('reader-finite-');
    final conversions = <Map<String, Object>>[];
    for (final name in [
      'river.epub',
      'mobi6-plain.mobi',
      'mobi6-palmdoc.mobi',
      'pg11-kf8.mobi',
    ]) {
      final original = await _asset(name);
      var bytes = original;
      var status = 0;
      if (name.endsWith('.mobi')) {
        final file = await File('${_work!.path}/$name').writeAsBytes(original);
        final path = file.path.toNativeUtf8();
        try {
          status = conversion(path);
        } finally {
          calloc.free(path);
        }
        if (status != 0) throw StateError('$name conversion failed: $status');
        bytes = await File(file.path.replaceFirst(RegExp(r'\.mobi$'), '.epub'))
            .readAsBytes();
        if (sha256.convert(await file.readAsBytes()) !=
            sha256.convert(original)) {
          throw StateError('Conversion modified the original');
        }
      }
      final book = await EpubReader.readBook(bytes);
      final package = book.Schema!.Package!;
      final chapters = <String>[];
      for (final item in package.Spine!.Items!) {
        final manifest = package.Manifest!.Items!.firstWhere(
          (entry) => entry.Id == item.IdRef,
        );
        chapters.add(book.Content!.Html![manifest.Href]!.Content!);
      }
      final text = html
          .parse(chapters.join('\n'))
          .body!
          .text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final expected = name == 'pg11-kf8.mobi'
          ? 'Alice'
          : 'The river follows the old road.';
      if (!text.contains(expected))
        throw StateError('$name lost expected text');
      final image = Uint8List.fromList(
        book.Content!.Images!.values.first.Content!,
      );
      _books.add((
        name: name,
        text: text.substring(0, text.length.clamp(0, 700)),
        image: image,
      ));
      conversions.add({
        'name': name,
        'status': status,
        'original_sha256': sha256.convert(original).toString(),
        'epub_sha256': sha256.convert(bytes).toString(),
        'epub_bytes': bytes.length,
        'spine_items': chapters.length,
        'images': book.Content!.Images!.length,
        'expected_text_retained': true,
      });
    }
    final malformed = await File('${_work!.path}/broken.mobi')
        .writeAsString('not a MOBI book');
    final malformedPath = malformed.path.toNativeUtf8();
    final int malformedStatus;
    try {
      malformedStatus = conversion(malformedPath);
    } finally {
      calloc.free(malformedPath);
    }
    if (malformedStatus == 0 ||
        await File('${_work!.path}/broken.epub').exists()) {
      throw StateError('Malformed input was not rejected');
    }
    debugPrint(
      'READER_PDF ${jsonEncode({'source_sha256': sha256.convert(source).toString(), 'pdf_anchors': anchors})}',
    );
    debugPrint(
      'READER_SCAN ${jsonEncode({
        'scan_text_characters': scanText.length,
        'scan_render_pixels': [360, _images.last.height],
      })}',
    );
    for (final conversion in conversions) {
      debugPrint('READER_CONVERSION ${jsonEncode(conversion)}');
    }
    debugPrint('READER_MALFORMED ${jsonEncode({'status': malformedStatus})}');
  }

  @override
  void dispose() {
    for (final image in _images) {
      image.dispose();
    }
    _document?.dispose();
    _scan?.dispose();
    _work?.delete(recursive: true);
    super.dispose();
  }

  void _showSource(int page) {
    debugPrint(
      'READER_SOURCE ${jsonEncode({'page': page, 'character': _sources[page - 1].character})}',
    );
    setState(() {
      _sourcePage = page;
      _view = 'Original';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reader finite proof'),
      actions: [
        IconButton(
          onPressed: () => showLicensePage(context: context),
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return SelectableText('Proof failed: ${snapshot.error}');
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Generated/public-domain corpus. No network permission. Research only.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final view in [
                    'Original',
                    'PDF reflow',
                    'Scan',
                    'EPUB/MOBI',
                  ])
                    ChoiceChip(
                      label: Text(view),
                      selected: _view == view,
                      onSelected: (_) => setState(() => _view = view),
                    ),
                ],
              ),
              if (_view == 'Original') ...[
                Text('Original source page $_sourcePage of 2'),
                Wrap(
                  children: [
                    for (final source in _sources)
                      TextButton(
                        onPressed: () => _showSource(source.page),
                        child: Text('Page ${source.page}'),
                      ),
                  ],
                ),
                Text(
                  'Source quote: old road; character ${_sources[_sourcePage - 1].character}',
                ),
                RawImage(image: _images[_sourcePage - 1], width: 360),
              ],
              if (_view == 'PDF reflow') ...[
                Wrap(
                  children: [
                    for (final width in [200.0, 360.0])
                      TextButton(
                        onPressed: () => setState(() => _width = width),
                        child: Text('Width ${width.toInt()}'),
                      ),
                  ],
                ),
                for (final source in _sources)
                  ReflowPage(
                    text: source.text,
                    width: _width,
                    sourcePage: source.page,
                    sourceCharacter: source.character,
                    onSource: () => _showSource(source.page),
                  ),
              ],
              if (_view == 'Scan') ...[
                const Text(
                  'Scan: 0 text characters. Original page only. No OCR.',
                ),
                RawImage(image: _images.last, width: 360),
              ],
              if (_view == 'EPUB/MOBI') ...[
                Wrap(
                  children: [
                    for (var index = 0; index < _books.length; index++)
                      TextButton(
                        onPressed: () => setState(() => _bookIndex = index),
                        child: Text(_books[index].name),
                      ),
                  ],
                ),
                const Text(
                  'EPUBX compatibility candidate. Plain text and first image, not an EPUB navigator.',
                ),
                Text(
                  _books[_bookIndex].text,
                  style: const TextStyle(fontSize: 18),
                ),
                Image.memory(_books[_bookIndex].image, width: 80, height: 100),
              ],
            ],
          ),
        );
      },
    ),
  );
}
