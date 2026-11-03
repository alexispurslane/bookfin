import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'ocr_storage.dart';
import 'pdf.dart';

class BundledEnglishText implements PdfTextSupply {
  static const version =
      'bookfin-ocr-1/tesseract4android-4.9.0/tesseract-5.5.1/leptonica-1.85.0/tessdata_fast-4.1.0-eng-7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2';
  static const _channel = MethodChannel('bookfin/ocr');
  PdfTextLease? _lease;
  int _generation = 0;
  bool _closed = false;
  Future<void> _draining = Future.value();
  final Map<({int page, int generation}), Future<PdfText>> _pending = {};
  final Set<int> _retry = {};
  final _recognizing = ValueNotifier(false);
  @override
  ValueListenable<bool> get recognizing => _recognizing;

  @override
  void bind(PdfTextLease lease) => _lease = lease;
  @override
  void retry(int page) => _retry.add(page);
  @override
  void cancel() {
    _generation++;
    if (!_closed) _recognizing.value = false;
  }

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) {
    final retry = _retry.remove(page);
    if (extracted.status == PdfTextStatus.candidate ||
        extracted.status == PdfTextStatus.unreliable && !retry ||
        _closed) {
      return Future.value(extracted);
    }
    final request = (page: page, generation: _generation);
    if (_pending.containsKey(request)) return _pending[request]!;
    if (_pending.length >= 2) {
      return Future.value(
        _fallback('Recognition is busy. Retry this source page.'),
      );
    }
    final generation = _generation;
    final previous = _draining;
    final operation = () async {
      await previous;
      bool requestLive() => !_closed && generation == _generation;
      if (!requestLive()) return _canceled;
      final lease = _lease;
      if (lease == null) {
        return _fallback(
          'English scan recognition requires an owned local download.',
        );
      }
      try {
        return await lease((original, owned) async {
              bool live() => requestLive() && owned();
              if (!live()) return _canceled;
              final key = sha256
                  .convert(utf8.encode('$version/${book.originalDigest}/$page'))
                  .toString();
              final cached = await readOcrCache(
                original,
                book.originalDigest,
                key,
              );
              if (!live()) return _canceled;
              final saved = _cachedPage(cached);
              if (saved != null) return saved;
              _recognizing.value = true;
              final raster = await book.render(page, 1600);
              if (!live()) return _canceled;
              final hocr = await _channel.invokeMethod<String>('recognize', {
                'width': raster.width,
                'height': raster.height,
                'bgra': raster.bgra,
              });
              if (!live()) return _canceled;
              final result = decodeRecognizedPage(hocr ?? '');
              if (result.status == PdfTextStatus.candidate) {
                try {
                  await writeOcrCache(
                    original,
                    book.originalDigest,
                    key,
                    hocr!,
                    live,
                  );
                } on Exception {
                  if (!live()) return _canceled;
                  return PdfText(
                    source: result.source,
                    text: result.text,
                    sourceOffsets: result.sourceOffsets,
                    status: result.status,
                    reason: 'English text is available, but could not be cached. Free storage to save recognition.',
                  );
                }
              }
              return live() ? result : _canceled;
            }) ??
            _fallback(
              'The download is no longer available. The original page remains open.',
            );
      } on Exception {
        return _fallback(
          'English recognition failed. Retry or read the original page.',
        );
      }
    }();
    _pending[request] = operation;
    _draining = operation.then<void>((_) {
      if (!_closed && generation == _generation) _recognizing.value = false;
      if (identical(_pending[request], operation)) _pending.remove(request);
    });
    return operation;
  }

  @override
  Future<void> close() async {
    cancel();
    _closed = true;
    await _draining;
    try {
      await _channel.invokeMethod<void>('close');
    } finally {
      _recognizing.dispose();
    }
  }

  void checkInvariants() {
    if (_pending.length > 2 || _closed && _recognizing.value) {
      throw StateError(
        'Recognition must have at most one active page and one waiting page.',
      );
    }
  }
}

const _canceled = PdfText(
  source: '',
  text: '',
  sourceOffsets: [],
  status: PdfTextStatus.absent,
  reason: 'Recognition canceled. The original page is available.',
);

PdfText? _cachedPage(String? hocr) {
  if (hocr == null) return null;
  try {
    return decodeRecognizedPage(hocr);
  } on Exception {
    return null;
  }
}

PdfText _fallback(String reason) => PdfText(
  source: '',
  text: '',
  sourceOffsets: const [],
  status: PdfTextStatus.absent,
  reason: reason,
);

PdfText decodeRecognizedPage(String hocr) {
  if (hocr.length > 8000000) {
    throw const FormatException('Recognition output is too large.');
  }
  final document = XmlDocument.parse(hocr);
  final lines = document.descendants
      .whereType<XmlElement>()
      .where(
        (element) => (element.getAttribute('class') ?? '')
            .split(' ')
            .contains('ocr_line'),
      )
      .toList();
  final source = StringBuffer();
  final boxes = <List<int>>[];
  var shortLines = 0;
  for (final line in lines) {
    final title = line.getAttribute('title') ?? '';
    final match = RegExp(r'(?:^|;)\s*bbox (\d+) (\d+) (\d+) (\d+)(?:;|$)')
        .firstMatch(title);
    if (match == null) {
      throw const FormatException('Missing recognized source-page geometry.');
    }
    final box = [
      for (var index = 1; index <= 4; index++) int.parse(match.group(index)!),
    ];
    if (box[2] <= box[0] || box[3] <= box[1]) {
      throw const FormatException('Invalid recognized source-page geometry.');
    }
    boxes.add(box);
    final words = line.descendants
        .whereType<XmlElement>()
        .where(
          (element) => (element.getAttribute('class') ?? '')
              .split(' ')
              .contains('ocrx_word'),
        )
        .map((element) => element.innerText.trim())
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length <= 2) shortLines++;
    if (source.isNotEmpty) source.write('\n');
    source.write(words.join(' '));
  }
  final raw = source.toString();
  if (raw.trim().isEmpty) {
    return _fallback('No English text was recognized. Read the original page.');
  }
  if (raw.length > 2000000 ||
      raw.contains('\uFFFD') ||
      raw.contains('\u0000')) {
    return _fallback('Recognized text is unreliable. Read the original page.');
  }
  var parallelRows = 0;
  final rows = <int, ({int minimumRight, int maximumLeft})>{};
  for (final box in boxes) {
    for (var bottom = box[3] - 3; bottom <= box[3] + 3; bottom++) {
      final previous = rows[bottom];
      if (previous != null &&
          (previous.minimumRight < box[0] || box[2] < previous.maximumLeft)) {
        parallelRows++;
        break;
      }
    }
    final previous = rows[box[3]];
    rows[box[3]] = (
      minimumRight: previous != null && previous.minimumRight < box[2]
          ? previous.minimumRight
          : box[2],
      maximumLeft: previous != null && previous.maximumLeft > box[0]
          ? previous.maximumLeft
          : box[0],
    );
  }
  final unreliable =
      parallelRows >= 3 || boxes.length >= 4 && shortLines / boxes.length >= .8;
  final text = StringBuffer();
  final offsets = <int>[];
  for (var index = 0; index < raw.length; index++) {
    text.write(raw[index] == '\n' ? ' ' : raw[index]);
    offsets.add(index);
  }
  return PdfText(
    source: raw,
    text: text.toString(),
    sourceOffsets: offsets,
    status: unreliable ? PdfTextStatus.unreliable : PdfTextStatus.candidate,
    reason: unreliable
        ? 'Recognized text order is unreliable. Read the original page.'
        : null,
  );
}
