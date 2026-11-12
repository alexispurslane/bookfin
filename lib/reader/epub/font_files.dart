// A book's font files: the characters that each one covers, and the SFNT
// bytes that Flutter registers.
//
// Nothing here uses dart:ui, so admission's worker, the prepare worker and
// the repo tool that writes reader_coverage.dart can all run it.
import 'dart:io';
import 'dart:typed_data';

/// The characters that a font has a glyph for: its coverage.
final class Coverage {
  const Coverage(this.ranges);

  /// The covered code points as closed ranges, the first and the last code
  /// point of each, in ascending order and apart from each other:
  /// `[first, last, first, last, ...]`.
  final List<int> ranges;

  /// Whether the font has a glyph for [codePoint].
  bool has(int codePoint) {
    var low = 0;
    var high = ranges.length ~/ 2 - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (codePoint < ranges[2 * middle]) {
        high = middle - 1;
      } else if (codePoint > ranges[2 * middle + 1]) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  /// The characters of this coverage that [other] lacks.
  Coverage without(Coverage other) {
    final left = <int>[];
    final cut = other.ranges;
    var next = 0;
    for (var at = 0; at < ranges.length; at += 2) {
      var first = ranges[at];
      final last = ranges[at + 1];
      // The ranges of [other] that end before this range cannot cut a later
      // one either.
      while (next < cut.length && cut[next + 1] < first) {
        next += 2;
      }
      for (var at = next; first <= last; at += 2) {
        if (at >= cut.length || cut[at] > last) {
          left
            ..add(first)
            ..add(last);
          break;
        }
        if (cut[at] > first) {
          left
            ..add(first)
            ..add(cut[at] - 1);
        }
        first = cut[at + 1] + 1;
      }
    }
    return Coverage(List.unmodifiable(left));
  }

  /// The coverage of [font], a TTF, OTF or WOFF 1 file, from its character
  /// map (its `cmap` table). Null when the file is of another kind, such
  /// as WOFF 2, or when its character map cannot be read.
  ///
  /// Of a WOFF file it inflates only the character map.
  static Coverage? of(Uint8List font) {
    try {
      final cmap = _table(font, _cmapTag);
      return cmap == null ? null : _coverageOf(ByteData.sublistView(cmap));
    } on RangeError {
      return null;
    }
  }
}

const _cmapTag = 0x636d6170; // 'cmap'
const _woff = 0x774f4646; // 'wOFF'

/// The bytes of the table [tag] of [font], a TTF, OTF or WOFF 1 file, or
/// null when the font has no such table or is of another kind.
Uint8List? _table(Uint8List font, int tag) {
  if (font.length < 12) return null;
  final data = ByteData.sublistView(font);
  final kind = data.getUint32(0);
  if (kind == _woff) {
    for (final table in _woffTables(font, data) ?? const <_WoffTable>[]) {
      if (table.tag == tag) return _woffBytes(font, table);
    }
    return null;
  }
  if (!_sfntKinds.contains(kind)) return null;
  final count = data.getUint16(4);
  for (var index = 0; index < count; index++) {
    final at = 12 + 16 * index;
    if (data.getUint32(at) != tag) continue;
    final offset = data.getUint32(at + 8);
    final length = data.getUint32(at + 12);
    if (offset + length > font.length) return null;
    return Uint8List.sublistView(font, offset, offset + length);
  }
  return null;
}

/// TrueType outlines, 'true' (old Apple TrueType) and 'OTTO' (CFF
/// outlines).
const _sfntKinds = {0x00010000, 0x74727565, 0x4f54544f};

/// The coverage that the character map [cmap] gives: the code points of its
/// best Unicode subtable that map to a glyph other than glyph 0. It reads a
/// format 12 subtable (all of Unicode) when the font has one, else a format
/// 4 subtable (the Basic Multilingual Plane).
Coverage? _coverageOf(ByteData cmap) {
  final count = cmap.getUint16(2);
  int? full;
  int? basic;
  for (var index = 0; index < count; index++) {
    final at = 4 + 8 * index;
    final platform = cmap.getUint16(at);
    final encoding = cmap.getUint16(at + 2);
    final offset = cmap.getUint32(at + 4);
    final unicode = platform == 0 || (platform == 3 && encoding == 10);
    final bmp = platform == 0 || (platform == 3 && encoding == 1);
    final format = cmap.getUint16(offset);
    if (format == 12 && unicode) full ??= offset;
    if (format == 4 && bmp) basic ??= offset;
  }
  final points = switch ((full, basic)) {
    (final int offset, _) => _format12(cmap, offset),
    (null, final int offset) => _format4(cmap, offset),
    _ => null,
  };
  if (points == null) return null;
  return Coverage(_rangesOf(points));
}

/// The code points that the format 12 subtable at [offset] maps to a glyph.
Iterable<(int, int)> _format12(ByteData cmap, int offset) sync* {
  final groups = cmap.getUint32(offset + 12);
  for (var index = 0; index < groups; index++) {
    final at = offset + 16 + 12 * index;
    var first = cmap.getUint32(at);
    final last = cmap.getUint32(at + 4);
    // A group that starts at glyph 0 maps its first code point to no glyph.
    if (cmap.getUint32(at + 8) == 0) first++;
    if (first <= last && last <= 0x10ffff) yield (first, last);
  }
}

/// The code points that the format 4 subtable at [offset] maps to a glyph.
Iterable<(int, int)> _format4(ByteData cmap, int offset) sync* {
  final segments = cmap.getUint16(offset + 6) ~/ 2;
  final ends = offset + 14;
  final starts = ends + 2 * segments + 2;
  final deltas = starts + 2 * segments;
  final rangeOffsets = deltas + 2 * segments;
  for (var segment = 0; segment < segments; segment++) {
    final first = cmap.getUint16(starts + 2 * segment);
    final last = cmap.getUint16(ends + 2 * segment);
    final delta = cmap.getUint16(deltas + 2 * segment);
    final rangeAt = rangeOffsets + 2 * segment;
    final rangeOffset = cmap.getUint16(rangeAt);
    for (var code = first; code <= last && code != 0xffff; code++) {
      final glyph = rangeOffset == 0
          ? (code + delta) & 0xffff
          : switch (cmap.getUint16(
              rangeAt + rangeOffset + 2 * (code - first),
            )) {
              0 => 0,
              final index => (index + delta) & 0xffff,
            };
      if (glyph != 0) yield (code, code);
    }
  }
}

/// [points], closed ranges of code points in any order, as the sorted and
/// joined ranges of a [Coverage].
List<int> _rangesOf(Iterable<(int, int)> points) {
  final sorted = points.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final ranges = <int>[];
  for (final (first, last) in sorted) {
    if (ranges.isNotEmpty && first <= ranges.last + 1) {
      if (last > ranges.last) ranges.last = last;
    } else {
      ranges
        ..add(first)
        ..add(last);
    }
  }
  return List.unmodifiable(ranges);
}

/// The largest font that [sfntOf] writes, in bytes.
const maxFontBytes = 32 * 1024 * 1024;

/// The SFNT bytes of a TTF, OTF or WOFF 1 font, which Flutter registers,
/// or null (WOFF 2 and anything else).
Uint8List? sfntOf(Uint8List font) {
  if (font.length < 12) return null;
  final data = ByteData.sublistView(font);
  final kind = data.getUint32(0);
  if (_sfntKinds.contains(kind)) return font;
  if (kind != _woff) return null;
  try {
    return _unwrapWoff(font, data);
  } on RangeError {
    return null;
  }
}

typedef _WoffTable = ({int tag, int offset, int stored, int length, int sum});

/// The table directory of the WOFF 1 file [font], or null when a table lies
/// out of bounds or the whole font would pass [maxFontBytes].
List<_WoffTable>? _woffTables(Uint8List font, ByteData data) {
  const header = 44;
  const entry = 20;
  if (font.length < header) return null;
  final count = data.getUint16(12);
  if (count == 0 || header + count * entry > font.length) return null;
  final tables = <_WoffTable>[];
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
  return tables;
}

/// The bytes of [table] of the WOFF 1 file [font], inflated when it is
/// stored compressed, or null when it does not inflate to its length.
Uint8List? _woffBytes(Uint8List font, _WoffTable table) {
  final stored = Uint8List.sublistView(
    font,
    table.offset,
    table.offset + table.stored,
  );
  return table.stored == table.length ? stored : _inflate(stored, table.length);
}

/// The SFNT font inside WOFF 1 [font]: each table inflated with zlib or
/// copied, behind a new table directory. Null when a part of the file is
/// out of bounds or does not inflate to its stated length.
Uint8List? _unwrapWoff(Uint8List font, ByteData data) {
  final tables = _woffTables(font, data);
  if (tables == null) return null;
  final count = tables.length;
  final size = tables.fold(
    12 + 16 * count,
    (total, table) => total + ((table.length + 3) & ~3),
  );
  final output = Uint8List(size);
  final out = ByteData.sublistView(output);
  var power = 1;
  var log = 0;
  while (power * 2 <= count) {
    power *= 2;
    log++;
  }
  out
    ..setUint32(0, data.getUint32(4))
    ..setUint16(4, count)
    ..setUint16(6, power * 16)
    ..setUint16(8, log)
    ..setUint16(10, count * 16 - power * 16);
  var offset = 12 + 16 * count;
  for (final (index, table) in tables.indexed) {
    final bytes = _woffBytes(font, table);
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
