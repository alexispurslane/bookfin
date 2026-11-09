import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as raster;
import 'package:xml/xml.dart';

import '../document.dart';

class Publication {
  Publication._(
    this.resources,
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

  final Map<String, Uint8List> resources;
  final Map<String, String> mediaTypes;
  final String originalDigest;
  final String identity;
  final String packagePath;
  final List<String> spine;
  final List<String> warnings;

  // The fields below come beside the admitted files. They are outside the
  // identity, so they can grow without moving a saved place.

  /// The original text of each style sheet in the manifest, by path, as the
  /// book wrote it. Admission may have emptied or rewritten the sheet in
  /// [resources]. Each text is the sheet's UTF-8 text, at most
  /// [maxResourceBytes] long, because the archive limits every entry to that
  /// size and admission refuses a sheet that is not UTF-8.
  final Map<String, String> bookStyles;

  /// The pixel width and height of each admitted PNG and JPEG, by path, from
  /// the raster check that admission already runs.
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

  Uri get base => Uri(scheme: 'https', host: host, path: '/$identity/');

  static Publication admit(Uint8List bytes) {
    try {
      return _Admission(_unpack(bytes), sha256.convert(bytes).toString()).run();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'This EPUB is damaged or uses an unsupported resource.',
      );
    }
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
    return _canonical(path) && resources.containsKey(path) ? path : null;
  }

  bool permitsNavigation(Uri url) {
    final path = pathFor(url);
    return path != null && _documents.contains(mediaTypes[path]);
  }

  /// Throws when one of these invariants fails:
  /// - every resource is canonical, within the size limits and typed;
  /// - every spine path is an admitted document;
  /// - [bookStyles] holds exactly the admitted style sheets;
  /// - [imageSizes] holds exactly the admitted PNG and JPEG images;
  /// - every contents entry points into the spine at a depth of at most
  ///   [maxContentsDepth].
  void checkInvariants() {
    bool typed(Iterable<String> paths, Set<String> types) {
      final wanted = {
        for (final MapEntry(key: path, value: type) in mediaTypes.entries)
          if (types.contains(type)) path,
      };
      return paths.length == wanted.length && wanted.containsAll(paths);
    }

    final package = Uri(scheme: 'https', host: 'book', path: '/$packagePath');
    if (resources.values.any((bytes) => bytes.length > maxResourceBytes) ||
        resources.values.fold<int>(0, (total, bytes) => total + bytes.length) >
            maxExpandedBytes ||
        resources.keys.any((path) => !_canonical(path)) ||
        !resources.keys.toSet().containsAll(spine) ||
        spine.any((path) => !_documents.contains(mediaTypes[path])) ||
        resources.keys.toSet().difference(mediaTypes.keys.toSet()).isNotEmpty) {
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
  }
}

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

Map<String, Uint8List> _unpack(Uint8List bytes) {
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
  var cursor = integer(end + 16);
  if (count == 0 || count > 4096 || cursor + integer(end + 12) != end) {
    throw const FormatException('EPUB exceeds archive entry limits.');
  }
  final output = <String, Uint8List>{};
  final names = <String>{};
  final ranges = <(int, int)>[];
  var expanded = 0;
  for (var index = 0; index < count; index++) {
    if (cursor + 46 > end || integer(cursor) != 0x02014b50) {
      throw const FormatException('Invalid EPUB ZIP entry.');
    }
    final flags = word(cursor + 8);
    final method = word(cursor + 10);
    final compressed = integer(cursor + 20);
    final size = integer(cursor + 24);
    final nameLength = word(cursor + 28);
    final next =
        cursor + 46 + nameLength + word(cursor + 30) + word(cursor + 32);
    final local = integer(cursor + 42);
    if (next > end ||
        nameLength > 512 ||
        (flags & ~0x808) != 0 ||
        (method != 0 && method != 8) ||
        word(cursor + 34) != 0 ||
        ((integer(cursor + 38) >> 16) & 0xf000) == 0xa000 ||
        size > Publication.maxResourceBytes ||
        compressed > Publication.maxArchiveBytes ||
        (size > 1024 * 1024 && size > compressed * 250) ||
        (expanded += size) > Publication.maxExpandedBytes ||
        local + 30 > integer(end + 16) ||
        integer(local) != 0x04034b50 ||
        word(local + 6) != flags ||
        word(local + 8) != method) {
      throw const FormatException(
        'EPUB entry exceeds limits or uses unsupported ZIP features.',
      );
    }
    final name = utf8.decode(
      bytes.sublist(cursor + 46, cursor + 46 + nameLength),
    );
    final directory = name.endsWith('/');
    final path = directory ? name.substring(0, name.length - 1) : name;
    final start = local + 30 + word(local + 26) + word(local + 28);
    if (!_canonical(path) ||
        !names.add(path) ||
        start + compressed > integer(end + 16) ||
        utf8.decode(bytes.sublist(local + 30, local + 30 + word(local + 26))) !=
            name ||
        ranges.any(
          (range) => local < range.$2 && start + compressed > range.$1,
        )) {
      throw const FormatException(
        'EPUB contains unsafe, duplicate, or overlapping paths.',
      );
    }
    ranges.add((local, start + compressed));
    final sink = _BoundedOutput(size);
    final content = bytes.sublist(start, start + compressed);
    if (method == 0) {
      sink.writeBytes(content);
    } else {
      Inflate(content, output: sink);
    }
    final unpacked = sink.getBytes();
    if (unpacked.length != size || getCrc32(unpacked) != integer(cursor + 16)) {
      throw const FormatException(
        'EPUB resource checksum or length does not match.',
      );
    }
    if (!directory) output[name] = Uint8List.fromList(unpacked);
    cursor = next;
  }
  if (cursor != end) {
    throw const FormatException('EPUB ZIP directory length does not match.');
  }
  return output;
}

class _BoundedOutput extends OutputMemoryStream {
  _BoundedOutput(this.limit) : super(size: 1024);
  final int limit;
  void _room(int count) {
    if (length + count > limit) {
      throw const FormatException(
        'EPUB decompression exceeds the declared size.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }
}

class _Admission {
  _Admission(this.raw, this.digest);
  final Map<String, Uint8List> raw;
  final String digest;
  final output = <String, Uint8List>{};
  final types = <String, String>{};
  final warnings = <String>{};
  final wrappers = <String, String?>{};
  final styles = <String, String>{};
  final sizes = <String, (int, int)>{};
  int _processedBytes = 0;

  XmlDocument _xml(String path) {
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
    if (utf8.decode(raw['mimetype'] ?? []) != 'application/epub+zip') {
      throw const FormatException('This file is not an EPUB publication.');
    }
    if (raw.containsKey('META-INF/encryption.xml')) {
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
      if (id == null ||
          ids.containsKey(id) ||
          path == null ||
          !raw.containsKey(path)) {
        throw const FormatException(
          'EPUB manifest has missing or ambiguous local resources.',
        );
      }
      ids[id] = path;
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
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local == 'content') {
          final path = _resolve(entry.key, node.getAttribute('src') ?? '');
          if (!documents.contains(path)) {
            throw const FormatException(
              'EPUB contents points outside the reading order.',
            );
          }
        }
      }
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
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              Publication.policy,
              digest,
              for (final path in paths)
                [path, types[path], sha256.convert(output[path]!).toString()],
            ]),
          ),
        )
        .toString();
    return Publication._(
      Map.unmodifiable(output),
      Map.unmodifiable({for (final path in paths) path: types[path]!}),
      digest,
      identity,
      package,
      List.unmodifiable(reading),
      List.unmodifiable(warnings),
      // A later write over the same path, such as the package document, can
      // change a path's type, so only paths that keep the type stay.
      Map.unmodifiable({
        for (final path in paths)
          if (types[path] == 'text/css') path: styles[path]!,
      }),
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
    );
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

  (int, int)? _raster(String path, String mime) {
    try {
      final bytes = raw[path]!;
      final raster.Decoder decoder = mime == 'image/png'
          ? raster.PngDecoder()
          : raster.JpegDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null ||
          info.width < 1 ||
          info.height < 1 ||
          info.width * info.height > 16000000 ||
          info.numFrames != 1 ||
          decoder.decode(bytes) == null) {
        return null;
      }
      return (info.width, info.height);
    } catch (_) {
      return null;
    }
  }

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
