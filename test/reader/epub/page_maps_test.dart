// A book's page map is kept on disk beside its download (t5-4lbx). A page
// map is the true page starts of each section for one value of the layout
// settings. It holds no reading place, so a map that cannot be read only
// costs layout work: the store sets it aside and reports no map.
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/downloads/derived_files.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_maps.dart';
import 'package:flutter_test/flutter_test.dart';

/// A download in a folder of its own, as Downloads keeps it.
Future<File> _download() async {
  final folder = await Directory.systemTemp.createTemp('bookfin-page-maps-');
  addTearDown(() => folder.delete(recursive: true));
  return File('${folder.path}/complete').writeAsBytes([1, 2, 3]);
}

Directory _layout(File download) =>
    Directory('${download.parent.path}/.bookfin-layout');

/// The kept page map files of [download], by name.
Future<Map<String, File>> _mapFiles(File download) async {
  final directory = _layout(download);
  if (!await directory.exists()) return {};
  return {
    await for (final entry in directory.list())
      if (entry is File && entry.path.endsWith('.map'))
        entry.uri.pathSegments.last: entry,
  };
}

/// Writes [sections] under [key] and returns the file that holds them.
Future<File> _writeAndFind(
  File download,
  PageMapKey key,
  List<KeptSection> sections,
) async {
  final before = await _mapFiles(download);
  await PageMaps.write(download, key, sections);
  final after = await _mapFiles(download);
  final added = after.keys.where((name) => !before.containsKey(name));
  expect(added, hasLength(1));
  return after[added.single]!;
}

PageMapKey _key({
  String book = 'book-identity',
  double width = 412,
  double height = 671,
  double textSize = 20,
  String engine = 'install-1|build-1|en-US',
}) => PageMapKey(
  book: book,
  width: width,
  height: height,
  textSize: textSize,
  engine: engine,
);

/// A map of three sections: one whose main run ended, one whose main run
/// stopped midway, and one that no run reached.
final _sections = [
  KeptSection(const [
    PageStart(0, 0),
    PageStart(0, 31),
    PageStart(3, 2),
    PageStart(3, 2, 1),
    PageStart(3, 2, 2),
    PageStart(200, 0),
    PageStart(200, 40000),
  ], complete: true),
  KeptSection(const [PageStart(0, 0), PageStart(1, 0)], complete: false),
  const KeptSection([], complete: false),
];

void main() {
  test('a written page map reads back the same', () async {
    final download = await _download();

    await PageMaps.write(download, _key(), _sections);

    expect(await PageMaps.read(download, _key()), _sections);
  });

  test('a book with no kept page map reads as absent', () async {
    final download = await _download();

    expect(await PageMaps.read(download, _key()), isNull);
  });

  test('a later write for the same settings replaces the map', () async {
    final download = await _download();
    await PageMaps.write(download, _key(), _sections);
    final longer = [
      ..._sections.take(2),
      KeptSection(const [PageStart(0, 0), PageStart(5, 1)], complete: true),
    ];

    await PageMaps.write(download, _key(), longer);

    expect(await PageMaps.read(download, _key()), longer);
    expect(await _mapFiles(download), hasLength(1));
  });

  for (final (name, other) in [
    ('another page width', _key(width: 412.00000000000006)),
    ('another page height', _key(height: 640)),
    ('another text size', _key(textSize: 26)),
    ('another book', _key(book: 'other-identity')),
  ]) {
    test('a map for $name is not returned', () async {
      final download = await _download();
      await PageMaps.write(download, _key(), _sections);

      expect(await PageMaps.read(download, other), isNull);
      expect(await PageMaps.read(download, _key()), _sections);
    });
  }

  test('a map with another engine fingerprint is not returned', () async {
    final download = await _download();
    await PageMaps.write(download, _key(engine: 'install-1'), _sections);

    expect(await PageMaps.read(download, _key(engine: 'install-2')), isNull);
  });

  test('a file whose header names another key is ignored and left in '
      'place', () async {
    final download = await _download();
    final mine = await _writeAndFind(download, _key(), _sections);
    final theirs = await _writeAndFind(
      download,
      _key(textSize: 26),
      _sections.take(1).toList(),
    );
    // As if the names of the two keys' files collided.
    await theirs.copy(mine.path);

    expect(await PageMaps.read(download, _key()), isNull);
    expect(await mine.exists(), isTrue);
    expect(
      await File('${_layout(download).path}/page-map.bad').exists(),
      false,
    );
  });

  group('a page map file that cannot be read', () {
    for (final (name, damage) in [
      ('cut short', (Uint8List kept) => kept.sublist(0, kept.length - 9)),
      ('cut to nothing', (Uint8List kept) => Uint8List(0)),
      (
        'changed in one byte',
        (Uint8List kept) => Uint8List.fromList(kept)..[kept.length ~/ 2] ^= 1,
      ),
      ('garbage', (Uint8List kept) => Uint8List.fromList(List.filled(64, 7))),
    ]) {
      test('a map file that is $name is set aside and reads as '
          'absent', () async {
        final download = await _download();
        final file = await _writeAndFind(download, _key(), _sections);
        final broken = damage(await file.readAsBytes());
        await file.writeAsBytes(broken);

        expect(await PageMaps.read(download, _key()), isNull);
        expect(await file.exists(), isFalse);
        expect(
          await File('${_layout(download).path}/page-map.bad').readAsBytes(),
          broken,
        );
      });
    }

    test('a map written after a broken one reads back', () async {
      final download = await _download();
      final file = await _writeAndFind(download, _key(), _sections);
      await file.writeAsBytes([1, 2, 3]);
      await PageMaps.read(download, _key());

      await PageMaps.write(download, _key(), _sections);

      expect(await PageMaps.read(download, _key()), _sections);
    });

    test('a book keeps only the last broken file it set aside', () async {
      final download = await _download();
      final first = await _writeAndFind(download, _key(), _sections);
      final second = await _writeAndFind(
        download,
        _key(textSize: 26),
        _sections,
      );
      await first.writeAsBytes([1]);
      await second.writeAsBytes([2]);

      await PageMaps.read(download, _key());
      await PageMaps.read(download, _key(textSize: 26));

      final bad = [
        await for (final entry in _layout(download).list())
          if (entry.path.endsWith('.bad')) entry.path,
      ];
      expect(bad, ['${_layout(download).path}/page-map.bad']);
      expect(await File(bad.single).readAsBytes(), [2]);
    });
  });

  test('a write that stops midway leaves the old map readable', () async {
    final download = await _download();
    final file = await _writeAndFind(download, _key(), _sections);
    // A process that was killed between its write and its rename left its
    // partial file.
    final kept = await file.readAsBytes();
    await File('${file.path}.killed.partial')
        .writeAsBytes(kept.sublist(0, kept.length ~/ 2));

    expect(await PageMaps.read(download, _key()), _sections);
  });

  test('a map that cannot be kept does not fail the write', () async {
    final download = await _download();
    // A file where the page maps' folder belongs.
    await File(_layout(download).path).writeAsString('');

    await PageMaps.write(download, _key(), _sections);

    expect(await PageMaps.read(download, _key()), isNull);
  });

  test('a forgotten map reads as absent', () async {
    final download = await _download();
    await PageMaps.write(download, _key(), _sections);
    await PageMaps.write(download, _key(textSize: 26), _sections);

    await PageMaps.forget(download, _key());

    expect(await PageMaps.read(download, _key()), isNull);
    expect(await PageMaps.read(download, _key(textSize: 26)), _sections);
  });

  group('the limits of a book', () {
    /// Writes a map for each text size, each one minute after the one
    /// before, an hour ago.
    Future<Map<double, File>> writeAll(
      File download,
      List<double> textSizes,
    ) async {
      final start = DateTime.now().subtract(const Duration(hours: 1));
      final files = <double, File>{};
      for (final (index, size) in textSizes.indexed) {
        final file = await _writeAndFind(
          download,
          _key(textSize: size),
          _sections,
        );
        await file.setLastModified(start.add(Duration(minutes: index)));
        files[size] = file;
      }
      return files;
    }

    test('a fifth settings value evicts the least recently used one', () async {
      final download = await _download();
      await writeAll(download, [16, 18, 20, 22]);

      await PageMaps.write(download, _key(textSize: 24), _sections);

      expect(await PageMaps.read(download, _key(textSize: 16)), isNull);
      for (final size in [18.0, 20.0, 22.0, 24.0]) {
        expect(await PageMaps.read(download, _key(textSize: size)), _sections);
      }
    });

    test('a map that was read counts as recently used', () async {
      final download = await _download();
      await writeAll(download, [16, 18, 20, 22]);
      await PageMaps.read(download, _key(textSize: 16));

      await PageMaps.write(download, _key(textSize: 24), _sections);

      expect(await PageMaps.read(download, _key(textSize: 16)), _sections);
      expect(await PageMaps.read(download, _key(textSize: 18)), isNull);
    });

    test('a write removes the maps of another engine fingerprint', () async {
      final download = await _download();
      await PageMaps.write(download, _key(engine: 'install-1'), _sections);
      await PageMaps.write(
        download,
        _key(engine: 'install-1', textSize: 26),
        _sections,
      );

      await PageMaps.write(download, _key(engine: 'install-2'), _sections);

      expect(await _mapFiles(download), hasLength(1));
      expect(
        await PageMaps.read(download, _key(engine: 'install-2')),
        _sections,
      );
    });
  });

  group('the download', () {
    test('the download counts the bytes of its page maps', () async {
      final download = await _download();
      final file = await _writeAndFind(download, _key(), _sections);

      expect(
        await DerivedBookFiles.bytes(download.parent),
        await file.length(),
      );
    });

    test('removing a download removes its page maps', () async {
      final download = await _download();
      await PageMaps.write(download, _key(), _sections);

      await DerivedBookFiles.remove(download.parent);

      expect(await _layout(download).exists(), isFalse);
      expect(await PageMaps.read(download, _key()), isNull);
    });
  });

  test('a key with a size that is not a positive number is refused', () {
    for (final make in [
      () => _key(width: double.nan),
      () => _key(height: 0),
      () => _key(textSize: double.infinity),
      () => _key(width: -412),
    ]) {
      expect(make, throwsArgumentError);
    }
  });
}
