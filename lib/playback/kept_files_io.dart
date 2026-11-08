import 'dart:io';

/// The kept copies of the damaged record file at [path], as full paths: the
/// files beside it named `<name>.damaged-<milliseconds>`. Their `-wal` and
/// `-shm` companions do not count.
Future<List<String>> keptFiles(String path) async {
  final file = File(path);
  final directory = file.parent;
  if (!await directory.exists()) return const [];
  final name = RegExp.escape(file.uri.pathSegments.last);
  final kept = RegExp('^$name\\.damaged-\\d+\$');
  return [
    await for (final entry in directory.list())
      if (entry is File && kept.hasMatch(entry.uri.pathSegments.last))
        entry.path,
  ];
}
