// The book's embedded fonts: the conversion of a font file to the bytes
// that Flutter reads, and the registration of each face.
//
// sfntOf uses no dart:ui, so a worker isolate can run it. BookFonts.load
// runs on the UI isolate, because Flutter registers fonts there.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'css.dart';

/// Registers books' embedded faces with Flutter.
///
/// Flutter keeps a registered font for the whole process and cannot unload
/// it. So the record of what is registered is process-wide too: a book that
/// opens again reuses its faces instead of registering copies.
abstract final class BookFonts {
  /// Each face's registration, by its family and path. A face is in it from
  /// the start of its load, so a second load of it waits for the first.
  static final _loads = <(String, String), Future<void>>{};

  /// Registers each of [faces] once, under its family in the book whose
  /// faces carry [prefix] (`FontFaceRule.familyIn`), from the bytes that
  /// [bytes] gives for its path. A face that fails to load is skipped, so
  /// its runs draw in a fallback font. When the future completes, every one
  /// of [faces] that can load is registered.
  static Future<void> load(
    Iterable<FontFaceRule> faces,
    Uint8List? Function(String path) bytes,
    String prefix,
  ) {
    final waits = <Future<void>>[];
    final fresh = <(String, String), Uint8List>{};
    for (final face in faces) {
      final key = (face.familyIn(prefix), face.path);
      if (_loads[key] case final pending?) {
        waits.add(pending);
      } else if (bytes(face.path) case final file?) {
        fresh[key] = file;
      } else {
        _loads[key] = Future.value();
      }
    }
    if (fresh.isNotEmpty) {
      final registration = _register([
        for (final MapEntry(key: (family, _), value: file) in fresh.entries)
          (family, file),
      ]);
      for (final key in fresh.keys) {
        _loads[key] = registration;
      }
      waits.add(registration);
    }
    return Future.wait(waits);
  }

  /// Converts every file of [fresh] in one worker isolate, then registers
  /// each font that converts under its family.
  static Future<void> _register(List<(String, Uint8List)> fresh) async {
    final files = [for (final (_, file) in fresh) file];
    final fonts = await Isolate.run(
      () => [for (final file in files) sfntOf(file)],
    );
    await Future.wait([
      for (final (index, (family, _)) in fresh.indexed)
        if (fonts[index] case final font?)
          ui.loadFontFromList(font, fontFamily: family).catchError((_) {}),
    ]);
  }
}

/// The largest font that [sfntOf] writes, in bytes.
const maxFontBytes = 32 * 1024 * 1024;

const _woff = 0x774f4646; // 'wOFF'

/// The SFNT bytes of a TTF, OTF or WOFF 1 font, or null (WOFF 2 and
/// anything else). Pure Dart, safe in a worker.
Uint8List? sfntOf(Uint8List font) {
  if (font.length < 12) return null;
  final data = ByteData.sublistView(font);
  return switch (data.getUint32(0)) {
    // TrueType outlines, 'true' (old Apple TrueType), 'OTTO' (CFF outlines).
    0x00010000 || 0x74727565 || 0x4f54544f => font,
    _woff => _unwrapWoff(font, data),
    _ => null,
  };
}

/// The SFNT font inside WOFF 1 [font]: each table inflated with zlib or
/// copied, behind a new table directory. Null when a part of the file is
/// out of bounds or does not inflate to its stated length.
Uint8List? _unwrapWoff(Uint8List font, ByteData data) {
  const header = 44;
  const entry = 20;
  if (font.length < header) return null;
  final flavor = data.getUint32(4);
  final count = data.getUint16(12);
  if (count == 0 || header + count * entry > font.length) return null;
  final tables = <({int tag, int offset, int stored, int length, int sum})>[];
  var size = 12 + 16 * count;
  for (var index = 0; index < count; index++) {
    final at = header + index * entry;
    final table = (
      tag: data.getUint32(at),
      offset: data.getUint32(at + 4),
      stored: data.getUint32(at + 8),
      length: data.getUint32(at + 12),
      sum: data.getUint32(at + 16),
    );
    if (table.stored > table.length ||
        table.offset + table.stored > font.length) {
      return null;
    }
    tables.add(table);
    size += (table.length + 3) & ~3;
    if (size > maxFontBytes) return null;
  }
  final output = Uint8List(size);
  final out = ByteData.sublistView(output);
  var power = 1;
  var log = 0;
  while (power * 2 <= count) {
    power *= 2;
    log++;
  }
  out
    ..setUint32(0, flavor)
    ..setUint16(4, count)
    ..setUint16(6, power * 16)
    ..setUint16(8, log)
    ..setUint16(10, count * 16 - power * 16);
  var offset = 12 + 16 * count;
  for (final (index, table) in tables.indexed) {
    final stored = Uint8List.sublistView(
      font,
      table.offset,
      table.offset + table.stored,
    );
    final bytes = table.stored == table.length
        ? stored
        : _inflate(stored, table.length);
    if (bytes == null) return null;
    output.setRange(offset, offset + table.length, bytes);
    out
      ..setUint32(12 + 16 * index, table.tag)
      ..setUint32(16 + 16 * index, table.sum)
      ..setUint32(20 + 16 * index, offset)
      ..setUint32(24 + 16 * index, table.length);
    offset += (table.length + 3) & ~3;
  }
  return output;
}

/// [data] inflated with zlib, or null when it does not inflate to exactly
/// [length] bytes. It stops early when the output passes [length], so a
/// small table cannot inflate to a huge one.
Uint8List? _inflate(Uint8List data, int length) {
  final sink = _Collect();
  final input = ZLibDecoder().startChunkedConversion(sink);
  const step = 4096;
  try {
    for (var start = 0; start < data.length; start += step) {
      final end = start + step < data.length ? start + step : data.length;
      input.add(Uint8List.sublistView(data, start, end));
      if (sink.bytes.length > length) return null;
    }
    input.close();
  } on Exception {
    return null;
  }
  return sink.bytes.length == length ? sink.bytes.takeBytes() : null;
}

class _Collect implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) => bytes.add(chunk);

  @override
  void close() {}
}
