import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, compute, protected;
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

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
  });
  final String source;
  final String text;
  final List<int> sourceOffsets;
  final PdfTextStatus status;
  final String? reason;
  final String? recognition;
}

class PdfRaster {
  const PdfRaster(this.width, this.height, this.bgra);
  final int width;
  final int height;
  final Uint8List bgra;
}

abstract class PdfBook extends ReaderDocument {
  PdfTextSupply? get textSupply => null;
  int get pageCount;
  Future<PdfText> text(int sourcePage);
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
          '$policy/$engine/${text.recognition ?? 'extracted'}/${_digests[text] ??= digest(text.source)}',
    );
  }

  /// The digest of each page text that [addressFor] named, so each scroll
  /// step inside a page reuses its page's digest.
  final _digests = Expando<String>('PDF page text digest');

  /// The digest that names the page text [source] in an address. It hashes
  /// on the UI isolate because [addressFor] answers at once, and it runs
  /// once for each page text, which is usually a few kilobytes.
  @protected
  String digest(String source) =>
      sha256.convert(utf8.encode(source)).toString();

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

abstract class PdfTextSupply {
  ValueListenable<bool> get recognizing;
  bool get canRetry;
  void bind(PdfTextLease lease);
  void cancel();
  void retry(int page);
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

  Future<PdfBook> open(Uint8List bytes, {PdfTextSupply? textSupply}) =>
      _admit(() async {
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
        final book = _NativePdfBook(this, document, digest, textSupply);
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
  );
  @override
  final PdfTextSupply? textSupply;
  final PdfRuntime owner;
  final native.PdfDocument _document;
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
    final extracted = await _extractedText(sourcePage);
    if (_closing != null) return extracted;
    return textSupply?.text(this, sourcePage, extracted) ?? extracted;
  });

  Future<PdfText> _extractedText(int sourcePage) {
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
        if (source.length > 2000000) {
          return PdfText(
            source: '',
            text: '',
            sourceOffsets: [],
            status: PdfTextStatus.unreliable,
            reason: 'This source page has too much text to reflow safely.',
          );
        }
        final unreliable = raw == null ? null : _textWarning(raw);
        final output = StringBuffer();
        final whitespacePattern = RegExp(r'\s');
        final offsets = <int>[];
        int? whitespace;
        for (var index = 0; index < source.length; index++) {
          final character = source.substring(index, index + 1);
          if (whitespacePattern.hasMatch(character)) {
            whitespace ??= index;
          } else {
            if (whitespace != null && output.isNotEmpty) {
              output.write(' ');
              offsets.add(whitespace);
            }
            whitespace = null;
            output.write(character);
            offsets.add(index);
          }
        }
        return PdfText(
          source: source,
          text: output.toString(),
          sourceOffsets: offsets,
          status: offsets.isEmpty
              ? PdfTextStatus.absent
              : unreliable != null
              ? PdfTextStatus.unreliable
              : PdfTextStatus.candidate,
          reason: offsets.isEmpty
              ? 'This source page has no extracted text. The original page is available.'
              : unreliable,
        );
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

String? _textWarning(native.PdfPageRawText raw) {
  const warning =
      'Text order or character mapping is unreliable on this source page. Read the original page instead.';
  if (raw.charRects.length != raw.fullText.length ||
      raw.fullText.contains('\uFFFD') ||
      raw.fullText.contains('\u0000')) {
    return warning;
  }
  final rows = <int, List<List<int>>>{};
  for (var index = 0; index < raw.fullText.length; index++) {
    if (raw.fullText[index].trim().isEmpty || raw.charRects[index].isEmpty) {
      continue;
    }
    final rect = raw.charRects[index];
    if (![
      rect.left,
      rect.right,
      rect.top,
      rect.bottom,
    ].every((value) => value.isFinite)) {
      return warning;
    }
    final bucket = (rect.bottom / 3).floor();
    final row =
        [for (var key = bucket - 1; key <= bucket + 1; key++) ...?rows[key]]
            .where(
              (row) =>
                  (raw.charRects[row.first].bottom - rect.bottom).abs() <= 3,
            )
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
    row.sort(
      (first, second) =>
          raw.charRects[first].left.compareTo(raw.charRects[second].left),
    );
    final parts = <List<int>>[];
    for (final index in row) {
      if (parts.isEmpty ||
          raw.charRects[index].left - raw.charRects[parts.last.last].right >
              18) {
        parts.add([index]);
      } else {
        parts.last.add(index);
      }
    }
    if (parts.length > 1) parallelRows++;
    for (final part in parts) {
      groups++;
      final phrase = raw.fullText.substring(
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
