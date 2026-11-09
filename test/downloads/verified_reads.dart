import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:crypto/crypto.dart';

/// The reads of a test's Downloads, which keeps no digests: each read
/// hashes the file of [Downloads.localFile], or its address when no such
/// file exists.
mixin VerifiedReads on Downloads {
  @override
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(VerifiedFile original) read, {
    void Function(bool Function() live)? onOwnership,
  }) async {
    final uri = await localFile(source);
    onOwnership?.call(() => true);
    if (uri == null) return null;
    // Widget tests run under a fake clock, where real asynchronous file work
    // never ends, so the test reads the file synchronously.
    final file = File.fromUri(uri);
    final bytes = file.existsSync()
        ? file.readAsBytesSync()
        : utf8.encode('$uri');
    return read(VerifiedFile(uri, sha256.convert(bytes).toString()));
  }
}

/// [file] with the digest of its bytes, as Downloads gives a verified file
/// to the reader.
VerifiedFile verified(File file) =>
    VerifiedFile(file.uri, sha256.convert(file.readAsBytesSync()).toString());
