import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../document.dart';
import 'image_size.dart';
import 'places.dart';
import 'prepare.dart';
import 'zip.dart';

class Publication {
  Publication._(
    this.textFiles,
    this._files,
    this.mediaTypes,
    this.originalDigest,
    this.identity,
    this.packagePath,
    this.spine,
    this.warnings,
    this.bookStyles,
    this.imageSizes,
    this.contents,
    this.language,
    this.spineSteps,
    this.mainTextSize,
  );

  static const policy = 'bookfin-passive-epub-1';
  static const maxArchiveBytes = 64 * 1024 * 1024;
  static const maxResourceBytes = 16 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxContentsDepth = 16;
  static const host = 'bookfin-publication.invalid';
  static const documentPolicy =
      "default-src 'none'; script-src 'none'; "
      "style-src 'unsafe-inline' https://bookfin-publication.invalid; "
      "img-src https://bookfin-publication.invalid; "
      "font-src https://bookfin-publication.invalid https://bookfin-runtime.invalid; "
      "connect-src 'none'; frame-src 'none'; object-src 'none'; "
      "base-uri https://bookfin-publication.invalid; form-action 'none'";

  /// The admitted files that are not images or fonts, by path: the
  /// documents, the style sheets, the NCX, the package document and the
  /// container. Images and fonts come through [bytesOf].
  final Map<String, Uint8List> textFiles;

  /// The admitted images and fonts.
  final _Files _files;

  /// The media type of every admitted file, by path.
  final Map<String, String> mediaTypes;
  final String originalDigest;

  /// The SHA-256 of [policy], [revision] and [originalDigest]: the name of
  /// this admission of the file. The page maps of the book are keyed by it.
  final String identity;
  final String packagePath;
  final List<String> spine;
  final List<String> warnings;

  // The fields below come beside the admitted files. They are outside the
  // identity, so they can grow without moving a saved place.

  /// The original text of each style sheet in the manifest, by path, as the
  /// book wrote it. Admission may have emptied or rewritten the sheet in
  /// [textFiles]. Each text is the sheet's UTF-8 text, at most
  /// [maxResourceBytes] long, because the archive limits every entry to that
  /// size and admission refuses a sheet that is not UTF-8.
  final Map<String, String> bookStyles;

  /// The pixel width and height of each admitted PNG and JPEG, by path, from
  /// the image's header, which admission checks.
  final Map<String, (int, int)> imageSizes;

  /// The contents: the EPUB 3 navigation document's toc, else the NCX navMap,
  /// else empty. Each href is relative to the package document's directory
  /// (the convention that BookMap.of resolves) and points into the spine.
  /// Each depth is the entry's nesting, from 0, at most [maxContentsDepth].
  final List<ContentsEntry> contents;

  /// The package's first `dc:language` that is not blank, such as `en-GB`,
  /// without the white space around it: the language of text whose
  /// elements name none. Null when the package names none.
  final String? language;

  /// The spine step of each section's CFIs, in spine order, as
  /// [spineSteps] in places.dart reads it from the admitted package
  /// document.
  final List<String> spineSteps;

  /// The book's main text size in pixels, with its own type sizes, as
  /// [measureMainTextSize] gives it on the sections that [mainTextSamples]
  /// picks. The reader's text size sizes this text once the reader has used
  /// the size buttons (`PageSettings.sizesMainText`).
  final double mainTextSize;

  Uri get base => Uri(scheme: 'https', host: host, path: '/$identity/');

  /// The revision of admission's output and of [encode]'s format. A kept
  /// admitted book of another revision admits again. Raise it when either
  /// changes. It does not move a saved place, which [policy] and the
  /// original digest key. It is part of [identity], so a book lays out its
  /// page maps again after a new revision.
  ///
  /// [mainTextSize] makes the cascade part of admission's output: raise the
  /// revision when a change to the cascade changes the main text size of a
  /// book. Revision 2 added [mainTextSize]. Revision 3 named [identity] by
  /// the policy, the revision and the digest (boo-yjq6). Revision 4 put the
  /// images and fonts after the other files, so that a reopen reads them
  /// only when a page draws them (boo-yjq6).
  static const revision = 4;

  /// The publication of the EPUB [bytes], whose SHA-256 is [digest]: the
  /// digest that Downloads verified, so admission does not hash the bytes
  /// again. Without [digest], admission hashes them. Throws a
  /// [FormatException] that a person can read when the book cannot be
  /// admitted.
  ///
  /// A chapter of the reading order whose file the book file lacks, or
  /// holds damaged, keeps its place and shows a short note instead of its
  /// text (t5-gk30). This holds for the first chapter too: the book opens
  /// at the note, and the reader turns to the next chapter. A contents
  /// entry that names a file outside the reading order is left out. A book
  /// whose container or package document is missing or damaged is still
  /// refused, because it has no reading order to keep.
  static Publication admit(Uint8List bytes, [String? digest]) {
    try {
      final (:files, :damaged) = _unpack(bytes);
      return _Admission(
        files,
        damaged,
        digest ?? sha256.convert(bytes).toString(),
      ).run();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'This EPUB is damaged or uses an unsupported resource.',
      );
    }
  }

  /// The publication as bytes that [decode] reads back into an equal
  /// publication: every admitted file and every admitted fact. The bytes
  /// come as parts to put one after the other, so that a caller copies
  /// them once, into the buffer that it writes. Only a publication that
  /// [admit] gave holds its images and fonts to encode.
  ///
  /// The bytes are the length of a JSON header as a 32-bit little-endian
  /// number, that header in UTF-8, and then each file's bytes in the order
  /// that the header lists them: first [textFiles], then the images and
  /// fonts.
  List<Uint8List> encode() {
    final files = switch (_files) {
      _HeldFiles(:final bytes) => bytes,
      _KeptFiles() => throw StateError(
        'A reopened publication reads its images and fonts from its record.',
      ),
    };
    final header = utf8.encode(
      jsonEncode({
        'originalDigest': originalDigest,
        'identity': identity,
        'packagePath': packagePath,
        'spine': spine,
        'spineSteps': spineSteps,
        'warnings': warnings,
        'language': language,
        'mainTextSize': mainTextSize,
        'contents': [
          for (final entry in contents) [entry.title, entry.href, entry.depth],
        ],
        'bookStyles': bookStyles,
        'imageSizes': {
          for (final MapEntry(key: path, value: (width, height))
              in imageSizes.entries)
            path: [width, height],
        },
        'resources': [
          for (final MapEntry(key: path, value: bytes) in [
            ...textFiles.entries,
            ...files.entries,
          ])
            [path, mediaTypes[path], bytes.length],
        ],
      }),
    );
    return [
      Uint8List(4)
        ..buffer.asByteData().setUint32(0, header.length, Endian.little),
      header,
      ...textFiles.values,
      ...files.values,
    ];
  }

  /// The publication that [encode] wrote into the file at [path] after the
  /// bytes [head], from the position of [file], an open handle of it.
  ///
  /// It reads the header and [textFiles] now. Each image and font is read
  /// from the file when [bytesOf] asks for it, while the file still begins
  /// with [head]. Each resource gets bytes of its own, so a resource that
  /// goes to a worker does not take the others along. Throws a
  /// [FormatException] when the file does not hold such a publication, for
  /// example when it was cut short, and a [FileSystemException] when it
  /// cannot be read.
  static Future<Publication> decode(
    RandomAccessFile file, {
    required String path,
    required Uint8List head,
  }) async {
    try {
      final end = await file.length();
      Future<Uint8List> read(int count) async {
        // A damaged record can name any length, so the read never asks for
        // more bytes than the file has left.
        if (count > end - await file.position()) {
          throw const FormatException('The record was cut short.');
        }
        final bytes = await file.read(count);
        if (bytes.length != count) {
          throw const FormatException('The record was cut short.');
        }
        return bytes;
      }

      final length = ByteData.sublistView(await read(4))
          .getUint32(0, Endian.little);
      final header =
          jsonDecode(utf8.decode(await read(length))) as Map<String, dynamic>;
      List<String> strings(Object? value) =>
          List.unmodifiable((value as List).cast<String>());
      final entries = [
        for (final entry in header['resources'] as List)
          ((entry as List)[0] as String, entry[1] as String, entry[2] as int),
      ];
      final types = {for (final (path, type, _) in entries) path: type};
      final texts = entries.takeWhile((entry) => !_binary(entry.$2)).toList();
      final kept = entries.skip(texts.length).toList();
      if (types.length != entries.length ||
          entries.any((entry) => entry.$3 < 0) ||
          kept.any((entry) => !_binary(entry.$2))) {
        throw const FormatException('The record lists its files wrongly.');
      }
      final block = await read(
        texts.fold(0, (total, entry) => total + entry.$3),
      );
      final textFiles = <String, Uint8List>{};
      var offset = 0;
      for (final (name, _, size) in texts) {
        textFiles[name] = Uint8List.fromList(
          Uint8List.sublistView(block, offset, offset += size),
        ).asUnmodifiableView();
      }
      final ranges = <String, (int, int)>{};
      var position = await file.position();
      for (final (name, _, size) in kept) {
        ranges[name] = (position, size);
        position += size;
      }
      if (position != end) {
        throw const FormatException('The record has bytes left over.');
      }
      final spine = strings(header['spine']);
      final spineSteps = strings(header['spineSteps']);
      final mainTextSize = (header['mainTextSize'] as num).toDouble();
      if (!(mainTextSize > 0 && mainTextSize.isFinite)) {
        throw const FormatException('The record has no main text size.');
      }
      return Publication._(
        Map.unmodifiable(textFiles),
        _KeptFiles(path, head, Map.unmodifiable(ranges)),
        Map.unmodifiable({
          for (final path in types.keys.toList()..sort()) path: types[path]!,
        }),
        header['originalDigest'] as String,
        header['identity'] as String,
        header['packagePath'] as String,
        spine,
        strings(header['warnings']),
        Map.unmodifiable((header['bookStyles'] as Map).cast<String, String>()),
        Map.unmodifiable({
          for (final MapEntry(key: path as String, value: size as List)
              in (header['imageSizes'] as Map).entries)
            path: (size[0] as int, size[1] as int),
        }),
        List.unmodifiable([
          for (final entry in header['contents'] as List)
            ContentsEntry(
              (entry as List)[0] as String,
              entry[1] as String,
              depth: entry[2] as int,
            ),
        ]),
        header['language'] as String?,
        spineSteps,
        mainTextSize,
      );
    } on FormatException {
      rethrow;
    } on FileSystemException {
      rethrow;
    } catch (_) {
      throw const FormatException('The kept admitted book is unreadable.');
    }
  }

  /// The bytes of the admitted file at [path], or null when the book did
  /// not admit it.
  ///
  /// An image or a font of a reopened book comes from the book's kept
  /// record, so the reopen did not read it. It is null when the record
  /// changed since the reopen or cannot be read: the page then draws the
  /// image's alt text. The reader never asks for a font (boo-iv7q).
  Future<Uint8List?> bytesOf(String path) async {
    if (textFiles[path] case final bytes?) return bytes;
    return switch (_files) {
      _HeldFiles(:final bytes) => bytes[path],
      final _KeptFiles kept => kept.read(path),
    };
  }

  String? pathFor(Uri url) {
    if (url.scheme != 'https' ||
        url.host != host ||
        url.hasPort ||
        url.userInfo.isNotEmpty ||
        url.hasQuery) {
      return null;
    }
    final segments = url.pathSegments;
    if (segments.length < 2 || segments.first != identity) return null;
    final path = segments.skip(1).join('/');
    return _canonical(path) && mediaTypes.containsKey(path) ? path : null;
  }

  bool permitsNavigation(Uri url) {
    final path = pathFor(url);
    return path != null && _documents.contains(mediaTypes[path]);
  }

  /// Throws when one of these invariants fails:
  /// - every admitted file is canonical, within the size limits and typed;
  /// - [textFiles] holds every admitted file but the images and fonts;
  /// - every spine path is an admitted document;
  /// - [bookStyles] holds exactly the admitted style sheets;
  /// - [imageSizes] holds exactly the admitted PNG and JPEG images;
  /// - every contents entry points into the spine at a depth of at most
  ///   [maxContentsDepth];
  /// - [spineSteps] has one step for each spine item;
  /// - [mainTextSize] is finite and above 0;
  /// - [identity] names [policy], [revision] and [originalDigest].
  void checkInvariants() {
    bool typed(Iterable<String> paths, Set<String> types) {
      final wanted = {
        for (final MapEntry(key: path, value: type) in mediaTypes.entries)
          if (types.contains(type)) path,
      };
      return paths.length == wanted.length && wanted.containsAll(paths);
    }

    final package = Uri(scheme: 'https', host: 'book', path: '/$packagePath');
    final sizes = {
      for (final MapEntry(key: path, value: bytes) in textFiles.entries)
        path: bytes.length,
      ..._files.sizes,
    };
    if (sizes.values.any((size) => size > maxResourceBytes) ||
        sizes.values.fold<int>(0, (total, size) => total + size) >
            maxExpandedBytes ||
        sizes.keys.any((path) => !_canonical(path)) ||
        !textFiles.keys.toSet().containsAll(spine) ||
        spine.any((path) => !_documents.contains(mediaTypes[path])) ||
        sizes.length != textFiles.length + _files.sizes.length ||
        sizes.length != mediaTypes.length ||
        !mediaTypes.keys.every(sizes.containsKey) ||
        textFiles.keys.any((path) => _binary(mediaTypes[path]!)) ||
        _files.sizes.keys.any((path) => !_binary(mediaTypes[path]!))) {
      throw StateError(
        'Publication resources, reading order, and media types disagree.',
      );
    }
    if (!typed(bookStyles.keys, {'text/css'}) ||
        !typed(imageSizes.keys, {'image/png', 'image/jpeg'}) ||
        imageSizes.values.any((size) => size.$1 < 1 || size.$2 < 1) ||
        contents.any(
          (entry) =>
              entry.depth < 0 ||
              entry.depth > maxContentsDepth ||
              !spine.contains(
                package.resolve(entry.href).pathSegments.join('/'),
              ),
        )) {
      throw StateError(
        'Publication styles, image sizes, or contents disagree with its resources.',
      );
    }
    if (spineSteps.length != spine.length) {
      throw StateError('Publication spine steps disagree with its spine.');
    }
    if (!(mainTextSize > 0 && mainTextSize.isFinite)) {
      throw StateError('Publication main text size is not a type size.');
    }
    if (identity != _identityOf(originalDigest)) {
      throw StateError('Publication identity does not name its file.');
    }
  }
}

/// Whether a file of [mime] is an image or a font: a file that layout does
/// not read, which a reopened book reads only when a page draws it.
bool _binary(String mime) =>
    mime.startsWith('image/') || mime.startsWith('font/');

/// The admitted images and fonts of a publication: held in memory after
/// admission, or kept in the book's record after a reopen.
sealed class _Files {
  /// The size in bytes of each file, by path.
  Map<String, int> get sizes;
}

/// The images and fonts that admission holds in memory.
final class _HeldFiles extends _Files {
  _HeldFiles(this.bytes);
  final Map<String, Uint8List> bytes;

  @override
  Map<String, int> get sizes => {
    for (final MapEntry(key: path, value: file) in bytes.entries)
      path: file.length,
  };
}

/// The images and fonts of a reopened book: ranges of its record at [path],
/// which hold them while the file begins with [head].
final class _KeptFiles extends _Files {
  _KeptFiles(this.path, this.head, this.ranges);
  final String path;
  final Uint8List head;

  /// The start and the length of each file in the record, by path.
  final Map<String, (int, int)> ranges;

  @override
  Map<String, int> get sizes => {
    for (final MapEntry(key: name, value: (_, length)) in ranges.entries)
      name: length,
  };

  /// The file [name] from the record, or null when the book has no such
  /// file, or the record changed or cannot be read.
  Future<Uint8List?> read(String name) async {
    final (start, length) = ranges[name] ?? (-1, 0);
    if (start < 0) return null;
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final begins = await file.read(head.length);
      if (begins.length != head.length) return null;
      for (var index = 0; index < head.length; index++) {
        if (begins[index] != head[index]) return null;
      }
      await file.setPosition(start);
      final bytes = await file.read(length);
      return bytes.length == length ? bytes : null;
    } on FileSystemException {
      return null;
    } finally {
      await file?.close();
    }
  }
}

/// The document that stands in for a chapter that the book file lacks or
/// holds damaged (t5-gk30): [message] in one short centered line, as the
/// reader's other notices show.
String _note(String message) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title></title>'
    '</head><body><p style="text-align:center">$message</p></body></html>';

/// The identity of an admission of the file whose SHA-256 is [digest].
///
/// NOTE: It names the file, the policy and admission's revision, not the
/// admitted files, so admission hashes no admitted file (boo-yjq6). A saved
/// place does not match on it (see ReaderDocument.restore). The page maps
/// of a book are keyed by it, so a book lays them out again once after a
/// new revision.
String _identityOf(String digest) => sha256
    .convert(
      utf8.encode('${Publication.policy}/${Publication.revision}/$digest'),
    )
    .toString();

const _documents = {'application/xhtml+xml', 'text/html'};
const _types = {
  'application/xhtml+xml',
  'text/html',
  'text/css',
  'image/png',
  'image/jpeg',
  'image/svg+xml',
  'font/ttf',
  'font/otf',
  'font/woff',
  'font/woff2',
  'application/vnd.ms-opentype',
  'application/font-sfnt',
  'application/x-font-ttf',
  'application/x-font-opentype',
  'application/font-woff',
  'application/x-dtbncx+xml',
};

bool _canonical(String path) =>
    path.isNotEmpty &&
    path.length <= 512 &&
    !path.startsWith('/') &&
    !path.contains(RegExp(r'[\\%\x00-\x1f\x7f:?#]')) &&
    path
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

String? _resolve(String base, String reference) {
  try {
    final url = Uri.parse(reference);
    if (url.hasScheme ||
        url.hasAuthority ||
        url.hasQuery ||
        reference.contains('\\') ||
        reference.contains(RegExp(r'[\x00-\x20]')) ||
        RegExp(r'%2f|%5c', caseSensitive: false).hasMatch(reference)) {
      return null;
    }
    final decoded = Uri.decodeComponent(url.path);
    if (decoded.startsWith('/')) return null;
    final parts = base.split('/')..removeLast();
    if (decoded.isEmpty) {
      parts.add(base.split('/').last);
    } else {
      for (final part in decoded.split('/')) {
        if (part == '.') continue;
        if (part == '..') {
          if (parts.isEmpty) return null;
          parts.removeLast();
        } else {
          parts.add(part);
        }
      }
    }
    final path = parts.join('/');
    return _canonical(path) ? path : null;
  } catch (_) {
    return null;
  }
}

String _relative(String base, String target, [String fragment = '']) {
  final parent = base.split('/')..removeLast();
  final parts = target.split('/');
  while (parent.isNotEmpty && parts.isNotEmpty && parent.first == parts.first) {
    parent.removeAt(0);
    parts.removeAt(0);
  }
  return '${List.filled(parent.length, '..').followedBy(parts.map(Uri.encodeComponent)).join('/')}'
      '${fragment.isEmpty ? '' : '#${Uri.encodeComponent(fragment)}'}';
}

/// The files of the EPUB archive [bytes], by name, and the names of the
/// files that the archive holds but that cannot be read: a file that uses
/// a ZIP feature that admission does not support, exceeds a size limit,
/// has a local header that does not match its directory entry, or does not
/// expand to its size and CRC-32, each with the reason. Admission treats
/// such a file as damaged (t5-gk30). It does not expand a damaged file past
/// its declared size.
///
/// Throws a [FormatException] when the archive itself cannot be read
/// safely: its directory is broken, it has too many files or too many
/// expanded bytes, or a file name is unsafe or repeated, names another
/// file in its local header, or shares bytes with another file.
({Map<String, Uint8List> files, Map<String, String> damaged}) _unpack(
  Uint8List bytes,
) {
  if (bytes.length > Publication.maxArchiveBytes || bytes.length < 22) {
    throw const FormatException(
      'EPUB archive exceeds the 64 MiB limit or is incomplete.',
    );
  }
  final data = ByteData.sublistView(bytes);
  int word(int offset) => data.getUint16(offset, Endian.little);
  int integer(int offset) => data.getUint32(offset, Endian.little);
  var end = bytes.length - 22;
  final minimum = (bytes.length - 65557).clamp(0, bytes.length);
  while (end >= minimum && integer(end) != 0x06054b50) {
    end--;
  }
  if (end < minimum ||
      end + 22 + word(end + 20) != bytes.length ||
      word(end + 4) != 0 ||
      word(end + 6) != 0 ||
      word(end + 8) != word(end + 10)) {
    throw const FormatException('Unsupported EPUB ZIP directory.');
  }
  final count = word(end + 10);
  final directory = integer(end + 16);
  var cursor = directory;
  if (count == 0 || count > 4096 || cursor + integer(end + 12) != end) {
    throw const FormatException('EPUB exceeds archive entry limits.');
  }
  final output = <String, Uint8List>{};
  final damaged = <String, String>{};
  final names = <String>{};
  final ranges = <(int, int)>[];
  var expanded = 0;
  for (var index = 0; index < count; index++) {
    // The directory record of this file.
    final entry = cursor;
    if (entry + 46 > end || integer(entry) != 0x02014b50) {
      throw const FormatException('Invalid EPUB ZIP entry.');
    }
    final flags = word(entry + 8);
    final method = word(entry + 10);
    final compressed = integer(entry + 20);
    final size = integer(entry + 24);
    final nameLength = word(entry + 28);
    final next = entry + 46 + nameLength + word(entry + 30) + word(entry + 32);
    final local = integer(entry + 42);
    if (next > end || nameLength > 512) {
      throw const FormatException(
        'EPUB ZIP directory entry runs past the directory or has a name over '
        '512 bytes.',
      );
    }
    final name = utf8.decode(
      bytes.sublist(entry + 46, entry + 46 + nameLength),
    );
    final folder = name.endsWith('/');
    final path = folder ? name.substring(0, name.length - 1) : name;
    if (!_canonical(path) || !names.add(path)) {
      throw const FormatException(
        'EPUB contains unsafe, duplicate, or overlapping paths.',
      );
    }
    cursor = next;
    // Bits 1 and 2 name the DEFLATE level, bit 3 a data descriptor after
    // the data, and bit 11 a UTF-8 name. Any other flag, such as
    // encryption, makes the file unreadable here.
    final unreadable = (flags & ~0x80e) != 0
        ? 'uses the unsupported ZIP flags 0x${flags.toRadixString(16)}'
        : method != 0 && method != 8
        ? 'uses the unsupported ZIP compression method $method'
        : word(entry + 34) != 0
        ? 'is on another disk of a split archive'
        : ((integer(entry + 38) >> 16) & 0xf000) == 0xa000
        ? 'is a symbolic link'
        : size > Publication.maxResourceBytes ||
              compressed > Publication.maxArchiveBytes
        ? 'exceeds the 16 MiB resource limit'
        : size > 1024 * 1024 && size > compressed * 250
        ? 'expands more than 250 times'
        : local + 30 > directory ||
              integer(local) != 0x04034b50 ||
              word(local + 6) != flags ||
              word(local + 8) != method
        ? 'has a local header that does not match its directory entry'
        : local + 30 + word(local + 26) + word(local + 28) + compressed >
              directory
        ? 'runs into the ZIP directory'
        : null;
    if (unreadable != null) {
      damaged[path] = unreadable;
      continue;
    }
    final start = local + 30 + word(local + 26) + word(local + 28);
    if (utf8.decode(bytes.sublist(local + 30, local + 30 + word(local + 26))) !=
            name ||
        ranges.any(
          (range) => local < range.$2 && start + compressed > range.$1,
        )) {
      throw const FormatException(
        'EPUB contains unsafe, duplicate, or overlapping paths.',
      );
    }
    ranges.add((local, start + compressed));
    if ((expanded += size) > Publication.maxExpandedBytes) {
      throw const FormatException('EPUB expands past the 128 MiB limit.');
    }
    final content = Uint8List.sublistView(bytes, start, start + compressed);
    final Uint8List unpacked;
    try {
      unpacked = method == 0
          ? Uint8List.fromList(content)
          : inflateEntry(content, size);
    } on FormatException {
      damaged[path] = 'has DEFLATE data that does not expand to its size';
      continue;
    }
    if (unpacked.length != size || crc32(unpacked) != integer(entry + 16)) {
      damaged[path] = 'does not match its CRC-32 or its length';
      continue;
    }
    if (!folder) output[name] = unpacked;
  }
  if (cursor != end) {
    throw const FormatException('EPUB ZIP directory length does not match.');
  }
  return (files: output, damaged: damaged);
}

class _Admission {
  _Admission(this.raw, this.damaged, this.digest);

  /// The files of the archive, by name. A chapter that the archive lacks,
  /// or holds damaged, gets a note document here.
  final Map<String, Uint8List> raw;

  /// The files that the archive holds but that cannot be read, each with
  /// the reason.
  final Map<String, String> damaged;
  final String digest;
  final output = <String, Uint8List>{};
  final types = <String, String>{};
  final warnings = <String>{};
  final wrappers = <String, String?>{};
  final styles = <String, String>{};
  final sizes = <String, (int, int)>{};
  int _processedBytes = 0;

  /// Throws a [FormatException] that names the damage when admission has
  /// no file at [path] because the archive holds it damaged. Admission
  /// cannot do without it. A chapter's note stands in its place.
  void _whole(String path) {
    if (raw.containsKey(path)) return;
    if (damaged[path] case final reason?) {
      throw FormatException('The book file is damaged: $path $reason.');
    }
  }

  XmlDocument _xml(String path) {
    _whole(path);
    final bytes = raw[path];
    if (bytes == null || bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('EPUB document is missing or exceeds 4 MiB.');
    }
    final text = utf8.decode(bytes);
    if (RegExp(r'<!ENTITY', caseSensitive: false).hasMatch(text)) {
      throw const FormatException(
        'EPUB XML entity declarations are not supported.',
      );
    }
    final doc = XmlDocument.parse(text);
    var nodes = 0;
    void visit(XmlNode node, int depth) {
      if (++nodes > 200000 || depth > 128) {
        throw const FormatException('EPUB document is too complex.');
      }
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    visit(doc, 0);
    return doc;
  }

  void _put(String path, String mime, List<int> bytes) {
    final total = _processedBytes - (output[path]?.length ?? 0) + bytes.length;
    if (bytes.length > Publication.maxResourceBytes ||
        total > Publication.maxExpandedBytes) {
      throw const FormatException(
        'Processed EPUB content exceeds the 16 MiB resource or 128 MiB publication limit.',
      );
    }
    _processedBytes = total;
    output[path] = Uint8List.fromList(bytes).asUnmodifiableView();
    types[path] = mime;
  }

  Publication run() {
    _whole('mimetype');
    if (utf8.decode(raw['mimetype'] ?? []) != 'application/epub+zip') {
      throw const FormatException('This file is not an EPUB publication.');
    }
    // A damaged encryption.xml still says that the book is encrypted.
    if (raw.containsKey('META-INF/encryption.xml') ||
        damaged.containsKey('META-INF/encryption.xml')) {
      throw const FormatException(
        'Encrypted or obfuscated EPUB resources are not supported.',
      );
    }
    final container = _xml('META-INF/container.xml');
    final roots = container.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'rootfile')
        .toList();
    final package = roots.firstOrNull?.getAttribute('full-path');
    if (roots.length != 1 || package == null || !_canonical(package)) {
      throw const FormatException('EPUB requires one local package document.');
    }
    final opf = _xml(package);
    if (opf.descendants.whereType<XmlElement>().any(
      (element) =>
          element.getAttribute('property') == 'rendition:layout' &&
          element.innerText.trim() == 'pre-paginated',
    )) {
      throw const FormatException(
        'Fixed-layout EPUB is not supported. Choose a reflowable edition.',
      );
    }
    final manifest = opf.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'manifest')
        .single;
    final items = manifest.childElements
        .where((node) => node.name.local == 'item')
        .toList();
    final ids = <String, String>{};
    final documents = <String>[];
    String? navigation;
    for (final item in items) {
      final id = item.getAttribute('id');
      final path = _resolve(package, item.getAttribute('href') ?? '');
      final mime = item.getAttribute('media-type') ?? '';
      if (id == null || ids.containsKey(id) || path == null) {
        throw const FormatException(
          'EPUB manifest has missing or ambiguous local resources.',
        );
      }
      ids[id] = path;
      if (!raw.containsKey(path)) {
        // The book file lacks this file or holds it damaged (t5-gk30). A
        // chapter keeps its place in the reading order and shows a short
        // note, so the places in the other chapters stay where they were.
        // Any other file is left out.
        if (_documents.contains(mime) && !types.containsKey(path)) {
          raw[path] = utf8.encode(
            _note(
              damaged.containsKey(path)
                  ? 'This chapter could not be read from the book file.'
                  : 'This chapter is missing from the book file.',
            ),
          );
          warnings.add(
            'Some chapters are missing from the book file or damaged. Each '
            'shows a short note instead of its text.',
          );
        } else {
          item.parent?.children.remove(item);
          warnings.add(
            'Some publication resources are missing from the book file or '
            'damaged, and were left out.',
          );
          continue;
        }
      }
      if (!_types.contains(mime) || types.containsKey(path)) {
        item.parent?.children.remove(item);
        warnings.add(
          'Some publication resources are unsupported and were blocked.',
        );
        continue;
      }
      types[path] = mime;
      if (_documents.contains(mime)) {
        documents.add(path);
        if (navigation == null &&
            (item.getAttribute('properties') ?? '')
                .split(RegExp(r'\s+'))
                .contains('nav')) {
          navigation = path;
        }
      } else if (mime == 'image/svg+xml') {
        wrappers[path] = null;
      } else if (mime.startsWith('image/')) {
        final size = _raster(path, mime);
        if (size != null) {
          _put(path, mime, raw[path]!);
          sizes[path] = size;
        } else {
          warnings.add(
            'Some images are damaged or exceed the 16-million-pixel limit.',
          );
        }
      } else if (mime.contains('font') || mime.startsWith('font/')) {
        if (_font(raw[path]!)) _put(path, _fontMime(raw[path]!), raw[path]!);
      }
    }
    for (final svg in wrappers.keys.toList()) {
      wrappers[svg] = _wrapper(svg);
    }
    for (final path in types.keys.toList()) {
      if (types[path] == 'text/css') {
        final text = styles[path] = utf8.decode(raw[path]!);
        _put(path, 'text/css', utf8.encode(_css(path, text)));
      }
    }
    XmlDocument? nav;
    for (final path in documents) {
      final source = _xml(path);
      if (path == navigation) nav = source;
      final root = _clean(
        source.rootElement,
        path,
      ).whereType<XmlElement>().firstOrNull;
      if (root == null || root.name.local != 'html') {
        throw const FormatException('EPUB chapter requires XHTML.');
      }
      var head = root.childElements
          .where((node) => node.name.local == 'head')
          .firstOrNull;
      if (head == null) {
        head = XmlElement(XmlName('head'));
        root.children.insert(0, head);
      }
      head.children.insert(
        0,
        XmlElement(XmlName('meta'), [
          XmlAttribute(XmlName('http-equiv'), 'Content-Security-Policy'),
          XmlAttribute(XmlName('content'), Publication.documentPolicy),
        ]),
      );
      _put(path, 'application/xhtml+xml', utf8.encode(root.toXmlString()));
    }
    final spine = opf.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'itemref')
        .map((node) => ids[node.getAttribute('idref')])
        .toList();
    if (spine.isEmpty ||
        spine.any((path) => path == null || !documents.contains(path))) {
      throw const FormatException(
        'EPUB reading order contains an unsupported document.',
      );
    }
    final ncx = types.entries
        .where((entry) => entry.value == 'application/x-dtbncx+xml')
        .toList();
    XmlDocument? navMap;
    for (final entry in ncx) {
      final document = _xml(entry.key);
      navMap ??= document;
      _put(
        entry.key,
        entry.value,
        utf8.encode(document.rootElement.toXmlString()),
      );
    }
    for (final item in items) {
      final path = ids[item.getAttribute('id')];
      if (!output.containsKey(path)) item.parent?.children.remove(item);
    }
    _put(
      package,
      'application/oebps-package+xml',
      utf8.encode(opf.rootElement.toXmlString()),
    );
    final steps = spineStepsOf(opf.rootElement);
    _put(
      'META-INF/container.xml',
      'application/xml',
      utf8.encode(container.rootElement.toXmlString()),
    );
    final reading = spine.cast<String>();
    var contents = nav == null
        ? const <ContentsEntry>[]
        : _navContents(nav, navigation!, package, reading);
    if (contents.isEmpty && navMap != null) {
      contents = _ncxContents(navMap, ncx.first.key, package, reading);
    }
    final paths = output.keys.toList()..sort();
    // A later write over the same path, such as the package document, can
    // change a path's type, so only paths that keep the type stay.
    final styleSheets = Map<String, String>.unmodifiable({
      for (final path in paths)
        if (types[path] == 'text/css') path: styles[path]!,
    });
    return Publication._(
      Map.unmodifiable({
        for (final path in paths)
          if (!_binary(types[path]!)) path: output[path]!,
      }),
      _HeldFiles(
        Map.unmodifiable({
          for (final path in paths)
            if (_binary(types[path]!)) path: output[path]!,
        }),
      ),
      Map.unmodifiable({for (final path in paths) path: types[path]!}),
      digest,
      _identityOf(digest),
      package,
      List.unmodifiable(reading),
      List.unmodifiable(warnings),
      styleSheets,
      Map.unmodifiable({
        for (final path in paths)
          if (types[path] == 'image/png' || types[path] == 'image/jpeg')
            path: sizes[path]!,
      }),
      List.unmodifiable(contents),
      // The admitted package document keeps the metadata as the book wrote
      // it.
      opf.descendants
          .whereType<XmlElement>()
          .where(
            (node) =>
                node.name.local == 'language' &&
                (node.namespaceUri == 'http://purl.org/dc/elements/1.1/' ||
                    node.name.prefix == 'dc'),
          )
          .map((node) => node.innerText.trim())
          .where((language) => language.isNotEmpty)
          .firstOrNull,
      List.unmodifiable(steps),
      _mainTextSize(reading, styleSheets),
    );
  }

  /// The main text size of the admitted book whose spine is [spine] and
  /// whose original style sheets are [styleSheets]. It is measured here, in
  /// admission's isolate, so that no open of the book waits for it again.
  double _mainTextSize(List<String> spine, Map<String, String> styleSheets) {
    final samples = mainTextSamples([
      for (final path in spine) output[path]!.length,
    ]);
    try {
      return measureMainTextSize([
        for (final index in samples)
          SectionSource(
            index: index,
            path: spine[index],
            xhtml: utf8.decode(output[spine[index]]!, allowMalformed: true),
            styleSheets: styleSheets,
          ),
      ]);
    } on Exception {
      // NOTE: Preparing a section reports what it cannot read. A book is not
      // refused for its type sizes.
      return defaultMainTextSize;
    }
  }

  /// The entries of the toc nav of [document], the raw navigation document
  /// at [path], in the order that the nav lists them.
  List<ContentsEntry> _navContents(
    XmlDocument document,
    String path,
    String package,
    List<String> spine,
  ) {
    final toc = document.descendants
        .whereType<XmlElement>()
        .where(
          (node) =>
              node.name.local == 'nav' &&
              (node.getAttribute('epub:type') ?? '')
                  .split(RegExp(r'\s+'))
                  .contains('toc'),
        )
        .firstOrNull;
    final entries = <ContentsEntry>[];
    void list(XmlElement ol, int depth) {
      for (final item in ol.childElements.where(
        (node) => node.name.local == 'li',
      )) {
        final label = item.childElements
            .where(
              (node) => node.name.local == 'a' || node.name.local == 'span',
            )
            .firstOrNull;
        if (label != null) {
          final entry = _entry(
            label.innerText,
            label.name.local == 'a' ? label.getAttribute('href') : null,
            path,
            package,
            spine,
            depth,
          );
          if (entry != null) entries.add(entry);
        }
        for (final child in item.childElements.where(
          (node) => node.name.local == 'ol',
        )) {
          list(child, depth + 1);
        }
      }
    }

    for (final ol
        in toc?.childElements.where((node) => node.name.local == 'ol') ??
            const <XmlElement>[]) {
      list(ol, 0);
    }
    return entries;
  }

  /// The entries of the navMap of [document], the NCX at [path], in the
  /// order that the navMap lists them.
  List<ContentsEntry> _ncxContents(
    XmlDocument document,
    String path,
    String package,
    List<String> spine,
  ) {
    Iterable<XmlElement> children(XmlElement node, String name) =>
        node.childElements.where((child) => child.name.local == name);
    final entries = <ContentsEntry>[];
    void list(XmlElement parent, int depth) {
      for (final point in children(parent, 'navPoint')) {
        final label = children(point, 'navLabel').firstOrNull;
        final entry = _entry(
          label == null
              ? ''
              : children(label, 'text').firstOrNull?.innerText ?? '',
          children(point, 'content').firstOrNull?.getAttribute('src'),
          path,
          package,
          spine,
          depth,
        );
        if (entry != null) entries.add(entry);
        list(point, depth + 1);
      }
    }

    for (final map in document.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'navMap',
    )) {
      list(map, 0);
    }
    return entries;
  }

  /// The contents entry [text] that links to [href] from the document at
  /// [base], at [depth], or null when [href] does not point into [spine].
  ContentsEntry? _entry(
    String text,
    String? href,
    String base,
    String package,
    List<String> spine,
    int depth,
  ) {
    final target = href == null ? null : _resolve(base, href);
    if (target == null || !spine.contains(target)) return null;
    final String fragment;
    try {
      fragment = Uri.decodeComponent(Uri.parse(href!).fragment);
    } on FormatException {
      // A fragment that is not percent-encoded UTF-8 names no element.
      return null;
    }
    final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ContentsEntry(
      title.isEmpty ? 'Untitled chapter' : title,
      _relative(package, target, fragment),
      depth: depth < Publication.maxContentsDepth
          ? depth
          : Publication.maxContentsDepth,
    );
  }

  /// The width and height of the PNG or JPEG at [path], as [rasterSize]
  /// reads them from its header. Admission does not decode the pixels:
  /// layout needs only the size, and the page draws the image's alt text
  /// when its pixels do not decode.
  (int, int)? _raster(String path, String mime) => rasterSize(raw[path]!, mime);

  bool _font(Uint8List bytes) =>
      bytes.length >= 12 &&
      {
        'wOF2',
        'wOFF',
        'OTTO',
        '\u0000\u0001\u0000\u0000',
        'true',
      }.contains(latin1.decode(bytes.sublist(0, 4)));
  String _fontMime(Uint8List bytes) =>
      switch (latin1.decode(bytes.sublist(0, 4))) {
        'wOF2' => 'font/woff2',
        'wOFF' => 'font/woff',
        'OTTO' => 'font/otf',
        _ => 'font/ttf',
      };

  String? _wrapper(String path) {
    try {
      if (raw[path]!.length > 8192) return null;
      final doc = _xml(path);
      final root = doc.rootElement;
      if (doc.children.any(
            (node) => node is XmlDoctype || node is XmlProcessing,
          ) ||
          root.name.local != 'svg' ||
          root.namespaceUri != 'http://www.w3.org/2000/svg' ||
          root.childElements.length != 1 ||
          root.innerText.trim().isNotEmpty ||
          root.attributes.any(
            (attribute) => !{
              'xmlns',
              'xmlns:xlink',
              'height',
              'width',
              'viewBox',
              'version',
              'preserveAspectRatio',
              'class',
            }.contains(attribute.name.qualified),
          ) ||
          root.getAttribute('width') != '100%' ||
          root.getAttribute('height') != '100%' ||
          root.getAttribute('preserveAspectRatio') != 'xMidYMid meet') {
        return null;
      }
      final image = root.childElements.single;
      if (image.name.local != 'image' ||
          image.namespaceUri != root.namespaceUri ||
          image.childElements.isNotEmpty ||
          image.attributes.length != 3 ||
          image.attributes.any(
            (attribute) => !{
              'width',
              'height',
              'xlink:href',
            }.contains(attribute.name.qualified),
          )) {
        return null;
      }
      final href = image.getAttribute(
        'href',
        namespace: 'http://www.w3.org/1999/xlink',
      );
      if (href == null ||
          href.contains('%') ||
          href.split('/').contains('..') ||
          Uri.parse(href).hasFragment) {
        return null;
      }
      final target = _resolve(path, href);
      final width = int.tryParse(image.getAttribute('width') ?? '');
      final height = int.tryParse(image.getAttribute('height') ?? '');
      if (target == null ||
          types[target] != 'image/jpeg' ||
          !output.containsKey(target) ||
          root.getAttribute('viewBox') != '0 0 $width $height' ||
          _raster(target, 'image/jpeg') != (width, height)) {
        return null;
      }
      return target;
    } catch (_) {
      return null;
    }
  }

  String _css(String path, String css) {
    final plain = css
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAllMapped(
          RegExp(r'''@import\s+("[^"]*"|'[^']*')''', caseSensitive: false),
          (match) => '@import url(${match[1]})',
        );
    if (plain.contains('\\') ||
        plain.contains(RegExp(r'[\x00-\x08\x0b\x0e-\x1f]')) ||
        RegExp(
          r'expression|javascript|behavior|-moz-binding|@namespace|@document|</',
          caseSensitive: false,
        ).hasMatch(plain)) {
      warnings.add(
        'Some unsafe or unsupported publication styles were blocked.',
      );
      return '';
    }
    var invalid = false;
    final result = plain.replaceAllMapped(
      RegExp(
        r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s"'()]*))\s*\)''',
        caseSensitive: false,
      ),
      (match) {
        final reference = match[1] ?? match[2] ?? match[3]!;
        var target = _resolve(path, reference);
        if (target != null && wrappers.containsKey(target)) {
          target = wrappers[target];
        }
        if (target == null ||
            (!output.containsKey(target) && types[target] != 'text/css') ||
            !(types[target]!.startsWith('image/') ||
                types[target]!.startsWith('font/') ||
                types[target] == 'text/css')) {
          invalid = true;
          return '';
        }
        return 'url("${_relative(path, target)}")';
      },
    );
    if (invalid ||
        RegExp(r'url\s*\(', caseSensitive: false).allMatches(result).length !=
            RegExp(r'url\(', caseSensitive: false).allMatches(plain).length) {
      warnings.add(
        'Some external or unsupported publication styles were blocked.',
      );
      return '';
    }
    return result;
  }

  Iterable<XmlNode> _clean(XmlNode node, String path) sync* {
    if (node is XmlText || node is XmlCDATA) {
      yield XmlText(node.value!);
      return;
    }
    if (node is! XmlElement) return;
    final tag = node.name.local.toLowerCase();
    if (node.namespaceUri != null &&
            node.namespaceUri != 'http://www.w3.org/1999/xhtml' ||
        {
          'script',
          'svg',
          'iframe',
          'frame',
          'frameset',
          'object',
          'embed',
          'audio',
          'video',
          'source',
          'track',
          'canvas',
          'template',
          'input',
          'button',
          'textarea',
          'select',
          'base',
          'meta',
        }.contains(tag)) {
      if (tag == 'svg' || tag == 'object' || tag == 'embed') {
        yield _unsupported(
          node.getAttribute('aria-label') ?? node.getAttribute('title') ?? '',
        );
      }
      return;
    }
    if (!_tags.contains(tag)) {
      for (final child in node.children) {
        yield* _clean(child, path);
      }
      return;
    }
    if (tag == 'style') {
      yield XmlElement(XmlName('style'), [], [
        XmlText(_css(path, node.innerText)),
      ]);
      return;
    }
    final attributes = <XmlAttribute>[];
    for (final attribute in node.attributes) {
      final name = attribute.name.qualified;
      final value = attribute.value;
      if (name == 'xmlns' && tag == 'html') {
        attributes.add(
          XmlAttribute(XmlName('xmlns'), 'http://www.w3.org/1999/xhtml'),
        );
      } else if (name == 'xmlns:epub') {
        attributes.add(
          XmlAttribute(XmlName('xmlns:epub'), 'http://www.idpf.org/2007/ops'),
        );
      } else if (_attributes.contains(name) || name.startsWith('aria-')) {
        if (name == 'style') {
          attributes.add(XmlAttribute(XmlName(name), _css(path, value)));
        } else {
          attributes.add(XmlAttribute(XmlName(name), value));
        }
      } else if ((name == 'href' && (tag == 'a' || tag == 'link')) ||
          (name == 'src' && tag == 'img')) {
        var target = _resolve(path, value);
        if (target != null && wrappers.containsKey(target)) {
          target = wrappers[target];
        }
        final mime = types[target];
        final valid =
            target != null &&
            (tag == 'a'
                ? _documents.contains(mime)
                : tag == 'link'
                ? mime == 'text/css'
                : output.containsKey(target) &&
                      (mime == 'image/png' || mime == 'image/jpeg'));
        if (valid) {
          attributes.add(
            XmlAttribute(
              XmlName(name),
              _relative(
                path,
                target,
                tag == 'a'
                    ? Uri.decodeComponent(Uri.parse(value).fragment)
                    : '',
              ),
            ),
          );
        }
      } else if (name == 'rel' &&
          tag == 'link' &&
          value.toLowerCase() == 'stylesheet') {
        attributes.add(XmlAttribute(XmlName('rel'), 'stylesheet'));
      }
    }
    if (tag == 'img' &&
        !attributes.any((attribute) => attribute.name.local == 'src')) {
      yield _unsupported(node.getAttribute('alt') ?? '');
      return;
    }
    if (tag == 'link' &&
        !attributes.any((attribute) => attribute.name.local == 'href')) {
      return;
    }
    if (tag == 'html' &&
        !attributes.any((attribute) => attribute.name.qualified == 'xmlns')) {
      attributes.add(
        XmlAttribute(XmlName('xmlns'), 'http://www.w3.org/1999/xhtml'),
      );
    }
    yield XmlElement(XmlName(tag), attributes, [
      for (final child in node.children) ..._clean(child, path),
    ]);
  }

  XmlElement _unsupported(String alt) {
    warnings.add(
      'Some images are unsupported. Their descriptions remain in the text.',
    );
    return XmlElement(
      XmlName('span'),
      [
        XmlAttribute(XmlName('role'), 'img'),
        XmlAttribute(
          XmlName('aria-label'),
          'Unsupported image${alt.isEmpty ? '' : ': $alt'}',
        ),
      ],
      [XmlText('[Unsupported image${alt.isEmpty ? '' : ': $alt'}]')],
    );
  }
}

const _tags = {
  'html',
  'head',
  'title',
  'body',
  'style',
  'link',
  'a',
  'abbr',
  'address',
  'article',
  'aside',
  'b',
  'bdi',
  'bdo',
  'blockquote',
  'br',
  'caption',
  'cite',
  'code',
  'col',
  'colgroup',
  'dd',
  'del',
  'dfn',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'i',
  'img',
  'ins',
  'kbd',
  'li',
  'main',
  'mark',
  'nav',
  'ol',
  'p',
  'pre',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'section',
  'small',
  'span',
  'strong',
  'sub',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'u',
  'ul',
  'var',
  'wbr',
};
const _attributes = {
  'id',
  'class',
  'title',
  'lang',
  'xml:lang',
  'dir',
  'role',
  'epub:type',
  'alt',
  'width',
  'height',
  'colspan',
  'rowspan',
  'scope',
  'start',
  'reversed',
  'type',
  'style',
  'hidden',
};
