import 'dart:io';

import 'package:bookfin/downloads/derived_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory derived;
  late File kept;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-derived-');
    derived = Directory('${root.path}/.bookfin-derived');
    kept = File('${derived.path}/kept');
  });
  tearDown(() => root.delete(recursive: true));

  /// The names in the derived directory.
  Future<Set<String>> names() async => {
    await for (final entry in derived.list()) entry.uri.pathSegments.last,
  };

  test('a write makes the directory, replaces the kept file whole and leaves '
      'no partial file', () async {
    expect(await DerivedBookFiles.write(kept, [1, 2, 3]), isTrue);
    expect(await DerivedBookFiles.write(kept, [4, 5]), isTrue);
    expect(await kept.readAsBytes(), [4, 5]);
    expect(await names(), {'kept'});
  });

  test('a partial file that a killed process left goes away at a later '
      'write', () async {
    await derived.create();
    final killed = File('${kept.path}.${pid + 1}-1700000000000000.partial');
    await killed.writeAsBytes([9]);
    await killed.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );
    await DerivedBookFiles.write(kept, [1]);
    expect(await names(), {'kept'});
  });

  test('a partial file of a write in progress stays: in this process, or in '
      'another process within the last minute', () async {
    await derived.create();
    final own = File('${kept.path}.$pid-1700000000000000.partial');
    final recent = File('${derived.path}/other.${pid + 1}-17.partial');
    for (final file in [own, recent]) {
      await file.writeAsBytes([9]);
    }
    await own.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );
    await DerivedBookFiles.write(kept, [1]);
    expect(await names(), {
      'kept',
      own.uri.pathSegments.last,
      recent.uri.pathSegments.last,
    });
  });

  test('a write does not replace something other than a directory that holds '
      'the directory\'s name', () async {
    await File(derived.path).writeAsString('not a directory');
    expect(await DerivedBookFiles.write(kept, [1]), isFalse);
    expect(await File(derived.path).readAsString(), 'not a directory');
  });

  test('a download counts and removes the survey of its PDF with its other '
      'derived files', () async {
    final original = File('${root.path}/complete');
    final survey = File(
      '${DerivedBookFiles.surveyDirectory(original).path}/survey',
    );
    await DerivedBookFiles.write(survey, List.filled(100, 7));
    expect(await DerivedBookFiles.bytes(root), 100);
    await DerivedBookFiles.remove(root);
    expect(await survey.parent.exists(), isFalse);
  });
}
