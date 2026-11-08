import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// AVFoundation, which plays audio on iOS and macOS, chooses its decoder by
// the file extension. Downloads keeps each verified file under the fixed
// name `complete` on every platform, and Android's player reads the format
// from the bytes. So on Apple platforms the audio engine plays a download
// through a symbolic link whose extension names the format that the file's
// first bytes show. The download itself never changes.

/// The file extension that names the audio format of a file that starts
/// with [head], or null when [head] shows no format that AVFoundation plays.
String? audioExtension(Uint8List head) {
  bool at(int offset, String text) =>
      head.length >= offset + text.length &&
      String.fromCharCodes(head, offset, offset + text.length) == text;
  if (at(4, 'ftyp')) return 'm4a';
  if (at(0, 'ID3') ||
      head.length >= 2 && head[0] == 0xFF && head[1] & 0xE0 == 0xE0) {
    return 'mp3';
  }
  if (at(0, 'fLaC')) return 'flac';
  if (at(0, 'RIFF') && at(8, 'WAVE')) return 'wav';
  if (at(0, 'FORM') && (at(8, 'AIFF') || at(8, 'AIFC'))) return 'aiff';
  return null;
}

/// A file URI under which AVFoundation plays the audio [download]: a link
/// in [links] whose name ends in the extension of the download's format.
/// Each download has one link, which a later call replaces when the format
/// changes. A download that already has an extension, or whose format
/// [audioExtension] does not know, plays under its own URI.
Future<Uri> playableAudioFile(Uri download, {required Directory links}) async {
  final file = File.fromUri(download);
  final name = download.pathSegments.last;
  if (name.contains('.')) return download;
  final input = await file.open();
  final Uint8List head;
  try {
    head = await input.read(16);
  } finally {
    await input.close();
  }
  final extension = audioExtension(head);
  if (extension == null) return download;
  // NOTE: Engine rule 1. This hashes one file path of about 200 bytes,
  // which takes microseconds, less than a hop to another isolate.
  final key = sha256.convert(utf8.encode(file.path)).toString();
  await links.create(recursive: true);
  final link = Link('${links.path}/$key.$extension');
  await for (final old in links.list(followLinks: false)) {
    if (old.path != link.path &&
        old.uri.pathSegments.last.startsWith('$key.')) {
      await old.delete();
    }
  }
  if (await link.exists()) {
    if (await link.target() == file.path) return link.uri;
    await link.delete();
  }
  await link.create(file.path);
  return link.uri;
}
