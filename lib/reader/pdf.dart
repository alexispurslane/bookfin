import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueListenable, compute;
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

import '../foundation/hop.dart';
import 'document.dart';

enum PdfTextStatus { candidate, absent, unreliable }

class PdfText {
  const PdfText({
    required this.source,
    required this.text,
    required this.sourceOffsets,
    required this.status,
    this.reason,
    this.recognition,
    this.digest,
  }) : assert(
         status != PdfTextStatus.candidate || digest != null,
         'A candidate page text names its digest.',
       );
  final String source;
  final String text;
  final List<int> sourceOffsets;
  final PdfTextStatus status;
  final String? reason;
  final String? recognition;

  /// The [pdfTextDigest] of [source]. An address inside the page names its
  /// text by it, so every candidate text has one. Whoever builds the text
  /// computes it, so that [PdfBook.addressFor] answers without hashing.
  final String? digest;
}

/// The digest that names the page text [source] in an address: the SHA-256
/// of its UTF-8 bytes, as lowercase hex.
String pdfTextDigest(String source) =>
    sha256.convert(utf8.encode(source)).toString();

/// The longest extracted page text, in UTF-16 code units, that a source
/// page offers for reflow.
const _pageTextLimit = 2000000;

/// The page text that one source page offers the reader. [page] holds the
/// extracted text and its character boxes: left, top, right and bottom in
/// PDF points for each UTF-16 code unit of the text. It runs in a hop, so
/// it takes only data that crosses to another isolate as blocks.
///
/// The reflowed text joins each run of whitespace into one space and drops
/// whitespace at both ends. Each reflowed character records the source
/// character that it came from, and a joining space records the first
/// whitespace character of its run.
PdfText preparePdfPage(({String source, Float64List boxes}) page) {
  final source = page.source;
  final output = StringBuffer();
  final offsets = <int>[];
  var start = 0;
  for (var index = 0; index <= source.length; index++) {
    if (index < source.length && !_whitespace(source.codeUnitAt(index))) {
      continue;
    }
    if (start < index) {
      if (offsets.isNotEmpty) {
        output.write(' ');
        offsets.add(offsets.last + 1);
      }
      output.write(source.substring(start, index));
      for (var offset = start; offset < index; offset++) {
        offsets.add(offset);
      }
    }
    start = index + 1;
  }
  final unreliable = offsets.isEmpty ? null : _textWarning(source, page.boxes);
  final status = offsets.isEmpty
      ? PdfTextStatus.absent
      : unreliable != null
      ? PdfTextStatus.unreliable
      : PdfTextStatus.candidate;
  return PdfText(
    source: source,
    text: output.toString(),
    sourceOffsets: offsets,
    status: status,
    reason: offsets.isEmpty ? 'This page has no text to reflow.' : unreliable,
    digest: status == PdfTextStatus.candidate ? pdfTextDigest(source) : null,
  );
}

/// Whether [unit] is a UTF-16 code unit that `RegExp(r'\s')` matches.
/// Saved places count reflowed characters, so this set must not change.
bool _whitespace(int unit) =>
    unit >= 0x09 && unit <= 0x0D ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    unit >= 0x2000 && unit <= 0x200A ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

class PdfRaster {
  const PdfRaster(this.width, this.height, this.bgra);
  final int width;
  final int height;
  final Uint8List bgra;
}

abstract class PdfBook extends ReaderDocument {
  /// Recognizes the text of pages whose text layer cannot be read, or null
  /// when this book has no recognition.
  PdfTextSupply? get textSupply => null;
  int get pageCount;

  /// The text layer of [sourcePage]: the text that the page itself holds.
  /// It never runs recognition, so it answers quickly.
  Future<PdfText> textLayer(int sourcePage);

  /// The text of [sourcePage] for reading, which reflow and search use: its
  /// text layer when that is a candidate, and otherwise the text that
  /// [textSupply] gives for the page.
  Future<PdfText> text(int sourcePage) async {
    final layer = await textLayer(sourcePage);
    return textSupply?.text(this, sourcePage, layer) ?? layer;
  }

  Future<PdfRaster> render(int sourcePage, double width);

  PdfAddress addressFor(int sourcePage, PdfText text, int character) {
    if (text.status != PdfTextStatus.candidate ||
        character < 0 ||
        character > text.source.length) {
      throw ArgumentError('Choose a character in available PDF text.');
    }
    return PdfAddress(
      sourcePage,
      character,
      pageCount: pageCount,
      quote: text.source.substring(
        character,
        (character + 160).clamp(0, text.source.length),
      ),
      representation:
          '$policy/$engine/${text.recognition ?? 'extracted'}/${text.digest!}',
    );
  }

  PdfAddress? resolveAddress(PdfAddress address, PdfText text) {
    if (!accepts(address) ||
        text.status != PdfTextStatus.candidate ||
        address.character > text.source.length) {
      return null;
    }
    final resolved = addressFor(address.sourcePage, text, address.character);
    return address.character == 0 ||
            address.representation == resolved.representation
        ? resolved
        : null;
  }

  @override
  ReaderAddress? restore(Map<String, dynamic> value) {
    if (value['version'] != 1 || value['original'] != originalDigest) {
      return null;
    }
    final address = decodeAddress(value);
    return accepts(address) ? address : null;
  }
}

typedef PdfTextLease = Future<PdfText?> Function(
  Future<PdfText> Function(Uri original, bool Function() owned) read,
);

/// Gives the text of pages whose text layer cannot be read, by recognizing
/// the page. Recognition takes seconds, so only the reflow view and search
/// ask for it, through [PdfBook.text].
abstract class PdfTextSupply {
  /// Whether this reader waits for a page that is recognized.
  ValueListenable<bool> get recognizing;
  void bind(PdfTextLease lease);

  /// Stops every wait of this reader. A page that started still finishes.
  void cancel();

  /// The text of [page] of [book] for reading: [extracted], the page's text
  /// layer, when it is a candidate, and otherwise the recognized text, or a
  /// text without content whose reason says why there is none.
  Future<PdfText> text(PdfBook book, int page, PdfText extracted);
  Future<void> close();
}

String _digest(Uint8List bytes) => sha256.convert(bytes).toString();

class PdfRuntime {
  PdfRuntime._();
  static final PdfRuntime instance = PdfRuntime._();
  Future<void>? _initialization;
  Future<void> _admission = Future.value();
  final Set<_NativePdfBook> _books = {};

  Future<T> _admit<T>(Future<T> Function() action) {
    if (RootIsolateToken.instance == null) {
      throw StateError('Native PDF work must run on the application isolate.');
    }
    final operation = _admission.then((_) => action());
    _admission = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Opens the PDF [bytes]. Each page text is prepared through [hop].
  Future<PdfBook> open(
    Uint8List bytes, {
    PdfTextSupply? textSupply,
    IsolateHop hop = compute,
  }) => _admit(() async {
    await (_initialization ??= pdfrxFlutterInitialize());
    // Scanned PDFs can be large enough to freeze the UI while hashing.
    final digest = await compute(_digest, bytes);
    final document = await native.PdfDocument.openData(
      bytes,
      sourceName: digest,
    );
    if (document.isEncrypted || document.pages.isEmpty) {
      await document.dispose();
      throw const FormatException(
        'Encrypted or empty PDFs are not supported. The original download was kept.',
      );
    }
    final book = _NativePdfBook(this, document, digest, textSupply, hop);
    _books.add(book);
    return book;
  });

  Future<void> shutdown() => _admit(() async {
    await Future.wait(_books.toList().map((book) => book.dispose()));
    await native.PdfrxEntryFunctions.instance.stopBackgroundWorker();
    _initialization = null;
  });

  void _release(_NativePdfBook book) {
    assert(_books.contains(book));
    _books.remove(book);
  }

  void checkInvariants() {
    if (_books.isNotEmpty && _initialization == null ||
        _books.any((book) => !identical(book.owner, this) || book._disposed)) {
      throw StateError(
        'PDF documents must share one live application-isolate engine owner.',
      );
    }
  }
}

class _NativePdfBook extends PdfBook {
  _NativePdfBook(
    this.owner,
    this._document,
    this.originalDigest,
    this.textSupply,
    this._hop,
  );
  @override
  final PdfTextSupply? textSupply;
  final PdfRuntime owner;
  final native.PdfDocument _document;
  final IsolateHop _hop;
  final Set<Future<void>> _work = {};
  final Map<int, Future<PdfText>> _texts = {};
  Future<void>? _closing;
  bool _disposed = false;
  @override
  final String originalDigest;
  @override
  String get format => 'pdf';
  @override
  String get engine => 'pdfrx-0.9.0-pdfium-8125';
  @override
  String get policy => 'bookfin-pdf-source-pages-1';
  @override
  String get identity =>
      sha256.convert(utf8.encode('$policy/$engine/$originalDigest')).toString();
  @override
  int get pageCount => _document.pages.length;
  @override
  bool accepts(ReaderAddress address) =>
      address is PdfAddress && address.sourcePage <= pageCount;
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) {
    if (value['page'] is! int ||
        value['character'] is! int ||
        value['quote'] is! String ||
        value['representation'] != null && value['representation'] is! String) {
      throw const FormatException('Invalid saved PDF source page.');
    }
    return PdfAddress(
      value['page'] as int,
      value['character'] as int,
      quote: value['quote'] as String,
      pageCount: pageCount,
      representation: value['representation'] as String?,
    );
  }

  native.PdfPage _page(int number) {
    if (number < 1 || number > pageCount) {
      throw ArgumentError('Choose a source page in this PDF.');
    }
    return _document.pages[number - 1];
  }

  Future<T> _run<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future.error(StateError('This PDF is closed.'));
    }
    final operation = Future<T>.sync(action);
    late final Future<void> settled;
    settled = operation.then<void>(
      (_) {
        _work.remove(settled);
      },
      onError: (Object _, StackTrace _) {
        _work.remove(settled);
      },
    );
    _work.add(settled);
    return operation;
  }

  @override
  Future<PdfText> text(int sourcePage) => _run(() async {
    final extracted = await textLayer(sourcePage);
    if (_closing != null) return extracted;
    return textSupply?.text(this, sourcePage, extracted) ?? extracted;
  });

  @override
  Future<PdfText> textLayer(int sourcePage) {
    if (_closing != null) {
      return Future.error(StateError('This PDF is closed.'));
    }
    final page = _page(sourcePage);
    if (_texts.length >= 16 && !_texts.containsKey(sourcePage)) {
      _texts.remove(_texts.keys.first);
    }
    return _texts.putIfAbsent(
      sourcePage,
      () => _run(() async {
        final raw = await page.loadText();
        final source = raw?.fullText ?? '';
        if (source.length > _pageTextLimit) {
          return PdfText(
            source: '',
            text: '',
            sourceOffsets: [],
            status: PdfTextStatus.unreliable,
            reason: 'This page has too much text to reflow.',
          );
        }
        // The boxes cross to the worker as one typed list. Packing them
        // takes about 4 ns a character on an M-series Mac. Sending the
        // PdfRect objects themselves costs this isolate about 30 times as
        // much: about 450 ms for a page at the size limit.
        final rects = raw?.charRects ?? const <native.PdfRect>[];
        final boxes = Float64List(rects.length * 4);
        for (var index = 0; index < rects.length; index++) {
          final rect = rects[index];
          boxes
            ..[index * 4] = rect.left
            ..[index * 4 + 1] = rect.top
            ..[index * 4 + 2] = rect.right
            ..[index * 4 + 3] = rect.bottom;
        }
        return _hop(preparePdfPage, (source: source, boxes: boxes));
      }),
    );
  }

  @override
  Future<PdfRaster> render(int sourcePage, double width) => _run(() async {
    if (!width.isFinite || width <= 0) {
      throw ArgumentError('PDF render width must be positive.');
    }
    final page = _page(sourcePage);
    var fullWidth = width.clamp(120, 1600).toDouble();
    var fullHeight = page.height * fullWidth / page.width;
    if (fullHeight > 4000) {
      fullWidth *= 4000 / fullHeight;
      fullHeight = 4000;
    }
    final image = await page.render(
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );
    if (image == null) {
      throw Exception('The original PDF page could not be drawn.');
    }
    try {
      return PdfRaster(
        image.width,
        image.height,
        Uint8List.fromList(image.pixels),
      );
    } finally {
      image.dispose();
    }
  });

  @override
  Future<void> dispose() {
    textSupply?.cancel();
    return _closing ??= _dispose();
  }

  Future<void> _dispose() async {
    await Future.wait(_work.toList());
    try {
      await textSupply?.close();
    } finally {
      await _document.dispose();
      _disposed = true;
      owner._release(this);
    }
  }
}

/// Why the extracted page [text] with its character [boxes] (see
/// [preparePdfPage]) cannot be trusted to read in order, or null if it can.
String? _textWarning(String text, Float64List boxes) {
  const warning = 'The text of this page cannot be put in reading order.';
  if (boxes.length != text.length * 4 ||
      text.contains('\uFFFD') ||
      text.contains('\u0000')) {
    return warning;
  }
  double left(int index) => boxes[index * 4];
  double top(int index) => boxes[index * 4 + 1];
  double right(int index) => boxes[index * 4 + 2];
  double bottom(int index) => boxes[index * 4 + 3];
  final rows = <int, List<List<int>>>{};
  for (var index = 0; index < text.length; index++) {
    if (text[index].trim().isEmpty ||
        left(index) >= right(index) ||
        top(index) <= bottom(index)) {
      continue;
    }
    if (![
      left(index),
      right(index),
      top(index),
      bottom(index),
    ].every((value) => value.isFinite)) {
      return warning;
    }
    final bucket = (bottom(index) / 3).floor();
    final row =
        [for (var key = bucket - 1; key <= bucket + 1; key++) ...?rows[key]]
            .where((row) => (bottom(row.first) - bottom(index)).abs() <= 3)
            .firstOrNull;
    if (row == null) {
      rows.putIfAbsent(bucket, () => []).add([index]);
    } else {
      row.add(index);
    }
  }
  var groups = 0;
  var shortGroups = 0;
  var parallelRows = 0;
  for (final row in rows.values.expand((bucket) => bucket)) {
    row.sort((first, second) => left(first).compareTo(left(second)));
    final parts = <List<int>>[];
    for (final index in row) {
      if (parts.isEmpty || left(index) - right(parts.last.last) > 18) {
        parts.add([index]);
      } else {
        parts.last.add(index);
      }
    }
    if (parts.length > 1) parallelRows++;
    for (final part in parts) {
      groups++;
      final phrase = text.substring(
        part.reduce((first, second) => first < second ? first : second),
        part.reduce((first, second) => first > second ? first : second) + 1,
      );
      if (phrase.trim().split(RegExp(r'\s+')).length <= 2) shortGroups++;
      for (var index = 1; index < part.length; index++) {
        if ((part[index] - part[index - 1]).abs() > 5) return warning;
      }
    }
  }
  if (parallelRows >= 3 || groups >= 4 && shortGroups / groups >= .8) {
    return warning;
  }
  return null;
}
