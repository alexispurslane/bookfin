// The text outlines that Crossings measured stay on the phone between
// launches, one file for each outline, written atomically.
import 'dart:io';

import 'package:bookfin/crossings/outlines_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp());
  tearDown(() => root.delete(recursive: true));

  test('a kept outline reads back at a later launch', () async {
    await DiskOutlines(root).write('["ebook","r1"]', '{"outline":1}');

    expect(await DiskOutlines(root).read('["ebook","r1"]'), '{"outline":1}');
  });

  test('a later write replaces the kept outline of the same key', () async {
    final store = DiskOutlines(root);
    await store.write('key', 'old');

    await store.write('key', 'new');

    expect(await store.read('key'), 'new');
  });

  test('another key keeps nothing', () async {
    await DiskOutlines(root).write('key', 'value');

    expect(await DiskOutlines(root).read('other'), isNull);
  });

  test(
    'a write that stopped before its rename leaves the old outline',
    () async {
      final store = DiskOutlines(root);
      await store.write('key', 'old');
      // A kill between the write of the new bytes and the rename leaves the
      // partial file beside the kept one.
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        File('${file.path}.partial').writeAsStringSync('ne');
      }

      expect(await DiskOutlines(root).read('key'), 'old');
    },
  );
}
