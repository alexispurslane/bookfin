import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:bookfin/downloads/downloads.dart';
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

  test(
    'the first cache lookups of a scanned PDF do not hash the original',
    () async {
      final hop = CountingHop();

      expect(
        await readOcrCache(
          VerifiedFile(original.uri, digest),
          digest,
          'one',
          hop: hop.call,
        ),
        isNull,
      );
      expect(
        await readOcrCache(
          VerifiedFile(original.uri, digest),
          digest,
          'two',
          hop: hop.call,
        ),
        isNull,
      );

      expect(hop.hops, 0);
    },
  );

  test('the cache trusts the digest that Downloads gives', () async {
    const hocr = '<div class="ocr_page">River</div>';
    await writeOcrCache(
      VerifiedFile(original.uri, digest),
      digest,
      'one',
      hocr,
      () => true,
      hop: CountingHop().call,
    );

    // Downloads makes sure that the file has its digest. These bytes no
    // longer have it, so a cache that hashed the file again would refuse.
    await original.writeAsBytes([1, 2, 3]);

    expect(
      await readOcrCache(
        VerifiedFile(original.uri, digest),
        digest,
        'one',
        hop: CountingHop().call,
      ),
      hocr,
    );
  });

  test(
    'a download that holds another PDF than the open book is refused',
    () async {
      final other = sha256.convert([1, 2, 3]).toString();

      await expectLater(
        readOcrCache(
          VerifiedFile(original.uri, other),
          digest,
          'one',
          hop: CountingHop().call,
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        writeOcrCache(
          VerifiedFile(original.uri, other),
          digest,
          'one',
          '<div class="ocr_page">River</div>',
          () => true,
          hop: CountingHop().call,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await Directory('${root.path}/.bookfin-ocr').exists(), isFalse);
    },
  );

  test('a saved page encodes and decodes in hops and reads back', () async {
    final hop = CountingHop();
    const hocr = '<div class="ocr_page">River</div>';

    await writeOcrCache(
      VerifiedFile(original.uri, digest),
      digest,
      'one',
      hocr,
      () => true,
      hop: hop.call,
    );
    final saved = await readOcrCache(
      VerifiedFile(original.uri, digest),
      digest,
      'one',
      hop: hop.call,
    );

    expect(saved, hocr);
    expect(hop.hops, 2);
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
      VerifiedFile(original.uri, digest),
      digest,
      'one',
      'text',
      () => false,
      hop: CountingHop().call,
    );

    expect(
      await readOcrCache(
        VerifiedFile(original.uri, digest),
        digest,
        'one',
        hop: CountingHop().call,
      ),
      isNull,
    );
  });

  test(
    'a write that a killed process left before its rename keeps the saved page',
    () async {
      const earlier = '<div class="ocr_page">River</div>';
      const later = '<div class="ocr_page">Meadow</div>';
      await writeOcrCache(
        VerifiedFile(original.uri, digest),
        digest,
        'one',
        earlier,
        () => true,
        hop: CountingHop().call,
      );
      final pending = File('${root.path}/.bookfin-ocr/one.json.pending');
      await pending.writeAsString('{"key":"one","hocr":"<div');

      expect(
        await readOcrCache(
          VerifiedFile(original.uri, digest),
          digest,
          'one',
          hop: CountingHop().call,
        ),
        earlier,
      );
      await writeOcrCache(
        VerifiedFile(original.uri, digest),
        digest,
        'one',
        later,
        () => true,
        hop: CountingHop().call,
      );
      expect(
        await readOcrCache(
          VerifiedFile(original.uri, digest),
          digest,
          'one',
          hop: CountingHop().call,
        ),
        later,
      );
      expect(await pending.exists(), isFalse);
    },
  );

  test(
    'a process killed in the middle of a write keeps the saved page',
    () async {
      const earlier = '<div class="ocr_page">River</div>';
      await writeOcrCache(
        VerifiedFile(original.uri, digest),
        digest,
        'one',
        earlier,
        () => true,
        hop: CountingHop().call,
      );
      final parent = Zone.current;

      await expectLater(
        IOOverrides.runZoned(
          () => writeOcrCache(
            VerifiedFile(original.uri, digest),
            digest,
            'one',
            '<div class="ocr_page">Meadow</div>',
            () => true,
            hop: CountingHop().call,
          ),
          createFile: (path) => path.contains('/.bookfin-ocr/')
              ? _KilledWrite(parent.run(() => File(path)), parent)
              : parent.run(() => File(path)),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(
        await readOcrCache(
          VerifiedFile(original.uri, digest),
          digest,
          'one',
          hop: CountingHop().call,
        ),
        earlier,
      );
    },
  );
}

/// A cache file whose write stops halfway, as when Android kills the
/// process during the write.
class _KilledWrite extends Fake implements File {
  _KilledWrite(this._file, this._zone);
  final File _file;
  final Zone _zone;
  @override
  String get path => _file.path;
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await _zone.run(
      () => _file.writeAsString(contents.substring(0, contents.length ~/ 2)),
    );
    throw const FileSystemException('The process was killed.');
  }

  @override
  Future<File> rename(String newPath) => _zone.run(() => _file.rename(newPath));
  @override
  Future<bool> exists() => _zone.run(_file.exists);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _zone.run(() => _file.delete(recursive: recursive));
}
