// The page maps that Bookfin keeps beside a book's download (t5-4lbx).
//
// A page map is the true page starts of each section of one book, for one
// value of the layout settings (docs/research/epub-layout-cache.md). It
// saves the whole-book layout at each later open of the book. It holds no
// reading place, so a map that is lost or set aside costs only layout work.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../downloads/derived_files.dart';
import 'layout.dart';
import 'prepare.dart';

/// What a page map depends on: the book, the page size and text size, and
/// the text engine that laid it out.
///
/// The theme is not in the key, because the night colors cut the same page
/// starts in every section of the corpus. The device pixel ratio is not an
/// input of layout.
class PageMapKey {
  /// [book] is the admitted book's identity. [width] and [height] are the
  /// page size and [textSize] is the text size after the system text scale,
  /// all in logical pixels, and compared as exact 64-bit values.
  /// [sizesMainText] says whether [textSize] sizes the book's main text or
  /// its body ([PageSettings.sizesMainText]). [engine]
  /// is the text-engine fingerprint (t5-9tbu): it changes with the app's
  /// install, the system's build and the platform's locales.
  PageMapKey({
    required this.book,
    required this.width,
    required this.height,
    required this.textSize,
    required this.sizesMainText,
    required this.engine,
  }) {
    for (final (name, value) in [
      ('width', width),
      ('height', height),
      ('textSize', textSize),
    ]) {
      if (!value.isFinite || value <= 0) {
        throw ArgumentError.value(value, name, 'must be a positive size');
      }
    }
  }

  final String book;
  final double width;
  final double height;
  final double textSize;
  final bool sizesMainText;
  final String engine;
}

/// The page maps of one downloaded book, for each value of the page
/// settings: the store that the page source of the open book reads, writes
/// and forgets its page maps through.
class BookPageMaps {
  /// The maps of the download [original], whose admitted book has the
  /// identity [book]. [engine] gives the text-engine fingerprint of this
  /// process (`textEngineFingerprint` in lib/sync/device.dart). When it
  /// gives null, as in a debug build, the book keeps no maps: every read
  /// gives null, and writes and forgets touch no file.
  BookPageMaps(this._original, {required this.book, required this.engine});

  final File _original;
  final String book;
  final Future<String?> engine;

  /// The kept map for pages of [settings], or null. See [PageMaps.read].
  Future<List<KeptSection>?> read(PageSettings settings) async {
    final key = await _key(settings);
    return key == null ? null : PageMaps.read(_original, key);
  }

  /// Keeps [sections] as the map for pages of [settings]. See
  /// [PageMaps.write].
  Future<void> write(PageSettings settings, List<KeptSection> sections) async {
    final key = await _key(settings);
    if (key != null) await PageMaps.write(_original, key, sections);
  }

  /// Removes the map for pages of [settings]. See [PageMaps.forget].
  Future<void> forget(PageSettings settings) async {
    final key = await _key(settings);
    if (key != null) await PageMaps.forget(_original, key);
  }

  /// The key of the map for pages of [settings]. The theme is not in it.
  Future<PageMapKey?> _key(PageSettings settings) async {
    final engine = await this.engine;
    return engine == null
        ? null
        : PageMapKey(
            book: book,
            width: settings.width,
            height: settings.height,
            textSize: settings.fontSize,
            sizesMainText: settings.sizesMainText,
            engine: engine,
          );
  }
}

/// The true page starts of one section, in order, and whether its main run
/// reached the section's end.
///
/// A section that no run reached has no starts and is not complete.
class KeptSection {
  const KeptSection(this.starts, {required this.complete});
  final List<PageStart> starts;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is KeptSection &&
      other.complete == complete &&
      listEquals(other.starts, starts);

  @override
  int get hashCode => Object.hash(complete, Object.hashAll(starts));

  @override
  String toString() => 'KeptSection($starts, complete: $complete)';
}

/// The page maps that Bookfin keeps for each download.
///
/// The maps of a download are files in its layout directory
/// ([DerivedBookFiles.layoutDirectory]), so removing the download removes
/// them. Each [PageMapKey] has one file. A book keeps the maps of at most
/// [limit] keys, the most recently read or written. A write removes the
/// maps of another engine fingerprint, which no later read can use.
///
/// A file is: the magic number `BKPM`, the format [version] and the whole
/// key (the book, the page size, the text size and whether it sizes the
/// main text, and the engine), then the section count, then for each section its complete flag,
/// its start count and its starts, then a CRC-32 of all bytes before it.
/// Counts and starts are unsigned variable-length integers (LEB128). A
/// start is the step of its item from the previous start's item, then its
/// line (the step from the previous start's line when the item is the
/// same), then its part.
///
/// The calling isolate encodes and decodes the map, and the file access
/// is asynchronous. On the host's debug build, a map of 11,393 pages
/// (34 KB, the Complete Shakespeare) decodes in 0.3 ms and encodes in
/// 0.6 ms. One of 23,000 pages (70 KB, the largest of the corpus at 360 x
/// 640 @ 26) takes 1.0 ms and 1.6 ms. A worker would not take this work
/// off the UI isolate: the sections are a graph of one object for each
/// page, and the copy of that graph to or from a worker runs in the
/// sending isolate at about the cost of the codec, plus the hop's own 1 to
/// 2 ms (boo-rw7u).
abstract final class PageMaps {
  /// The format of the file. It is part of the key, so a file of another
  /// format reads as another key's map. Version 2 added
  /// [PageMapKey.sizesMainText].
  static const version = 2;

  /// The most settings values that one book keeps maps for. A reader
  /// changes the text size or turns the phone now and then, so four values
  /// cover the usual set: two text sizes in two orientations. The largest
  /// map of the corpus is 70 KB.
  static const limit = 4;

  static const _magic = [0x42, 0x4b, 0x50, 0x4d]; // BKPM

  /// The name of the broken file that a book sets aside. A book keeps the
  /// last one only, for a look by hand.
  static const _bad = 'page-map.bad';

  /// The page map of the download [original] for [key], or null.
  ///
  /// A file of another key, which only a collision of the file names can
  /// give, is left in place. A file that cannot be read (short, a bad
  /// CRC-32, or a decode error) is renamed to `page-map.bad`, which
  /// replaces the one before it. A map that is read counts as used for
  /// [limit].
  static Future<List<KeptSection>?> read(File original, PageMapKey key) async {
    final file = _file(original, key);
    final Uint8List bytes;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    final List<KeptSection>? sections;
    try {
      sections = _decode(bytes, _header(key));
    } on FormatException {
      try {
        await file.rename('${file.parent.path}/$_bad');
      } on FileSystemException {
        // The next write for this key replaces the file.
      }
      return null;
    }
    if (sections == null) return null;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // The map stays usable. It only counts as older for the limit.
    }
    return sections;
  }

  /// Keeps [sections] as the page map of the download [original] for
  /// [key], in place of the map before it.
  ///
  /// The write goes to a partial file of its own, then a rename over the
  /// map's file. So a process that dies during the write leaves the old map
  /// whole, and two writes of one key that overlap leave one of them whole.
  /// A partial file of a process that died stays until the download is
  /// removed. A map that cannot be written costs layout work at the next
  /// open, so the write does not fail.
  ///
  /// Each section's starts must be in increasing order.
  static Future<void> write(
    File original,
    PageMapKey key,
    List<KeptSection> sections,
  ) async {
    final directory = DerivedBookFiles.layoutDirectory(original);
    final file = _file(original, key);
    final bytes = _encode(_header(key), sections);
    try {
      switch (await FileSystemEntity.type(directory.path, followLinks: false)) {
        case FileSystemEntityType.notFound:
          await directory.create();
        case FileSystemEntityType.directory:
          break;
        default:
          // Something else holds the name. It is not the store's to
          // replace.
          return;
      }
      final partial = File(
        '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.partial',
      );
      try {
        await partial.writeAsBytes(bytes, flush: true);
        await partial.rename(file.path);
      } finally {
        if (await partial.exists()) await partial.delete();
      }
      await _evict(directory, file, _engineName(key));
    } on FileSystemException {
      // The next open lays the book out and writes again.
    }
  }

  /// Removes the page map of the download [original] for [key], when a
  /// page that the reader viewed contradicts it.
  static Future<void> forget(File original, PageMapKey key) async {
    try {
      await _file(original, key).delete();
    } on FileSystemException {
      // No map, or one that the next write for this key replaces.
    }
  }

  /// Removes the maps in [directory] of an engine other than [engine], and
  /// the least recently used maps beyond [limit]. [kept] is the map that
  /// was just written, which stays.
  static Future<void> _evict(
    Directory directory,
    File kept,
    String engine,
  ) async {
    final others = <(File, DateTime)>[];
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (entry is! File || !name.endsWith('.map') || entry.path == kept.path) {
        continue;
      }
      if (!name.startsWith('$engine-')) {
        await entry.delete();
      } else {
        others.add((entry, (await entry.stat()).modified));
      }
    }
    others.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (file, _) in others.skip(limit - 1)) {
      await file.delete();
    }
  }

  /// The file of [key]'s map. Its name begins with the engine's name, so
  /// that a write finds the maps of another engine without reading them.
  /// Then comes a hash of the whole header.
  static File _file(File original, PageMapKey key) {
    final directory = DerivedBookFiles.layoutDirectory(original);
    // Hashing a key of a few hundred bytes costs far less than a hop to a
    // worker, so it stays in the calling isolate.
    final name = sha256.convert(_header(key)).toString().substring(0, 32);
    return File('${directory.path}/${_engineName(key)}-$name.map');
  }

  /// The first 16 hexadecimal digits of the SHA-256 of [key]'s engine
  /// fingerprint.
  static String _engineName(PageMapKey key) =>
      sha256.convert(utf8.encode(key.engine)).toString().substring(0, 16);

  /// The bytes that begin the file of [key]'s map.
  static Uint8List _header(PageMapKey key) {
    final out = _Writer()..addAll(_magic);
    out.unsigned(version);
    final book = utf8.encode(key.book);
    out
      ..unsigned(book.length)
      ..addAll(book)
      ..float64(key.width)
      ..float64(key.height)
      ..float64(key.textSize)
      ..unsigned(key.sizesMainText ? 1 : 0);
    final engine = utf8.encode(key.engine);
    out
      ..unsigned(engine.length)
      ..addAll(engine);
    return out.bytes;
  }

  static Uint8List _encode(Uint8List header, List<KeptSection> sections) {
    final out = _Writer()
      ..addAll(header)
      ..unsigned(sections.length);
    for (final section in sections) {
      out
        ..unsigned(section.complete ? 1 : 0)
        ..unsigned(section.starts.length);
      var previous = const PageStart(0, 0);
      for (final (index, start) in section.starts.indexed) {
        assert(
          start.compareTo(previous) > 0 ||
              (index == 0 && start == const PageStart(0, 0)),
          'Starts must increase: $previous, then $start.',
        );
        out
          ..unsigned(start.item - previous.item)
          ..unsigned(
            start.item == previous.item
                ? start.line - previous.line
                : start.line,
          )
          ..unsigned(start.part);
        previous = start;
      }
    }
    return (out..uint32(getCrc32(out.bytes))).bytes;
  }

  /// The sections of [bytes] when its header is [header], or null when it
  /// names another key. It throws a [FormatException] when [bytes] is not
  /// a whole page map.
  static List<KeptSection>? _decode(Uint8List bytes, Uint8List header) {
    if (bytes.length < header.length + 5) {
      throw const FormatException('The page map is too short.');
    }
    final end = bytes.length - 4;
    final crc = ByteData.sublistView(bytes, end).getUint32(0, Endian.little);
    if (getCrc32(Uint8List.sublistView(bytes, 0, end)) != crc) {
      throw const FormatException('The page map fails its CRC-32.');
    }
    if (!listEquals(Uint8List.sublistView(bytes, 0, header.length), header)) {
      return null;
    }
    final reader = _Reader(bytes, header.length, end);
    // Each section takes at least 2 bytes, and each start 3, so no count
    // can make a list larger than the file.
    final count = reader.count(2);
    final sections = <KeptSection>[];
    for (var index = 0; index < count; index++) {
      final complete = switch (reader.unsigned()) {
        0 => false,
        1 => true,
        _ => throw const FormatException('A complete flag is not 0 or 1.'),
      };
      final starts = <PageStart>[];
      var item = 0;
      var line = 0;
      for (var left = reader.count(3); left > 0; left--) {
        final step = reader.unsigned();
        item += step;
        line = step == 0 ? line + reader.unsigned() : reader.unsigned();
        starts.add(PageStart(item, line, reader.unsigned()));
      }
      sections.add(KeptSection(starts, complete: complete));
    }
    if (!reader.done) {
      throw const FormatException('The page map has bytes after its end.');
    }
    return sections;
  }
}

/// A cursor over the body of a page map, from [_at] to [_end].
class _Reader {
  _Reader(this._bytes, this._at, this._end);
  final Uint8List _bytes;
  int _at;
  final int _end;

  bool get done => _at == _end;

  /// An unsigned variable-length integer below 2^35.
  int unsigned() {
    var value = 0;
    for (var shift = 0; shift < 35; shift += 7) {
      if (_at >= _end) {
        throw const FormatException('The page map ends inside a number.');
      }
      final byte = _bytes[_at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
    }
    throw const FormatException('A number of the page map is too long.');
  }

  /// A count of things that take at least [size] bytes each.
  int count(int size) {
    final value = unsigned();
    if (value * size > _end - _at) {
      throw const FormatException('A count is larger than the page map.');
    }
    return value;
  }
}

/// A byte buffer that grows as a page map is written.
class _Writer {
  var _bytes = Uint8List(4096);
  var _length = 0;

  /// The bytes written so far.
  Uint8List get bytes => Uint8List.sublistView(_bytes, 0, _length);

  void _reserve(int count) {
    if (_length + count <= _bytes.length) return;
    var size = _bytes.length * 2;
    while (size < _length + count) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
  }

  void addAll(List<int> bytes) {
    _reserve(bytes.length);
    _bytes.setRange(_length, _length += bytes.length, bytes);
  }

  /// [value] as an unsigned variable-length integer (LEB128).
  void unsigned(int value) {
    assert(value >= 0, 'A page map holds no negative number: $value.');
    _reserve(10);
    while (value >= 0x80) {
      _bytes[_length++] = value & 0x7f | 0x80;
      value >>= 7;
    }
    _bytes[_length++] = value;
  }

  void float64(double value) {
    _reserve(8);
    ByteData.sublistView(_bytes).setFloat64(_length, value, Endian.little);
    _length += 8;
  }

  void uint32(int value) {
    _reserve(4);
    ByteData.sublistView(_bytes).setUint32(_length, value, Endian.little);
    _length += 4;
  }
}
