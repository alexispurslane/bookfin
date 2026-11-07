import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:bookfin/reader/ocr_storage_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hop that runs each work item in a new isolate, as production does, and
/// counts the work items.
class CountingHop {
  int hops = 0;

  Future<R> call<M, R>(FutureOr<R> Function(M) work, M input) {
    hops++;
    return Isolate.run(() => work(input));
  }
}

void main() {
  late Directory root;
  late File original;
  late String digest;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-ocr-store-');
    addTearDown(() => root.delete(recursive: true));
    final random = Random(7);
    final bytes = List.generate(200000, (_) => random.nextInt(256));
    original = File('${root.path}/complete');
    await original.writeAsBytes(bytes);
    digest = sha256.convert(bytes).toString();
  });

  test('reading two pages of one PDF hashes the original once', () async {
    final hop = CountingHop();

    expect(
      await readOcrCache(original.uri, digest, 'one', hop: hop.call),
      isNull,
    );
    expect(
      await readOcrCache(original.uri, digest, 'two', hop: hop.call),
      isNull,
    );

    expect(hop.hops, 1);
  });

  test('a changed original is hashed again and refused', () async {
    final hop = CountingHop();
    await readOcrCache(original.uri, digest, 'one', hop: hop.call);

    await original.writeAsBytes([1, 2, 3]);

    await expectLater(
      readOcrCache(original.uri, digest, 'two', hop: hop.call),
      throwsA(isA<FormatException>()),
    );
    expect(hop.hops, 2);
  });

  test('a saved page encodes and decodes in hops and reads back', () async {
    final hop = CountingHop();
    const hocr = '<div class="ocr_page">River</div>';

    await writeOcrCache(
      original.uri,
      digest,
      'one',
      hocr,
      () => true,
      hop: hop.call,
    );
    final saved = await readOcrCache(
      original.uri,
      digest,
      'one',
      hop: hop.call,
    );

    expect(saved, hocr);
    expect(hop.hops, 3);
    expect(
      await Directory('${root.path}/.bookfin-ocr')
          .list()
          .map((entry) => entry.path.split('/').last)
          .toList(),
      ['one.json'],
    );
  });

  test('a page whose owner ended is not saved', () async {
    await writeOcrCache(
      original.uri,
      digest,
      'one',
      'text',
      () => false,
      hop: CountingHop().call,
    );

    expect(
      await readOcrCache(original.uri, digest, 'one', hop: CountingHop().call),
      isNull,
    );
  });
}
