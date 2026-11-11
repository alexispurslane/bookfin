// Tool code: writes lib/reader/epub/hyphenation_en_tables.dart, the const
// tables of the English hyphenation patterns and exceptions of
// lib/reader/epub/hyphenation_en.dart, which hyphenate.dart reads
// (boo-yjq6). It is not part of Bookfin.
//
// In the dev shell, from the repository root, after a change to
// hyphenation_en.dart or to the tables' form in hyphenate.dart:
//
//   dart run tool/reader/hyphenation_tables.dart
//
// hyphenate_test.dart checks that the tables hold the patterns.
import 'dart:io';

import 'package:bookfin/reader/epub/hyphenate.dart';
import 'package:bookfin/reader/epub/hyphenation_en.dart';

const _target = 'lib/reader/epub/hyphenation_en_tables.dart';

void main() {
  final source = File('lib/reader/epub/hyphenation_en.dart').readAsLinesSync();
  // The notices of the source, from its "Source:" line to the line that
  // names the notice file.
  final notices = source
      .skipWhile((line) => !line.startsWith('// Source:'))
      .takeWhile((line) => line.startsWith('//'))
      .where((line) => !line.contains('Each string holds'))
      .join('\n');
  final out = StringBuffer()
    ..writeln(
      '// The English hyphenation patterns and exceptions of '
      'hyphenation_en.dart, as',
    )
    ..writeln(
      '// the const tables that hyphenate.dart reads. Generated data: do '
      'not edit by',
    )
    ..writeln('// hand. tool/reader/hyphenation_tables.dart writes it.')
    ..writeln('//')
    ..writeln(notices)
    ..writeln();
  for (final (name, from, patterns, exceptions) in [
    ('enUs', 'hyph-en-us', enUsPatterns, enUsExceptions),
    ('enGb', 'hyph-en-gb', enGbPatterns, enGbExceptions),
  ]) {
    out
      ..writeln('/// The pattern table of $from.pat.txt.')
      ..writeln('const ${name}PatternTable = <int, List<int>>{');
    for (final MapEntry(:key, :value) in hyphenationPatterns(
      patterns,
    ).entries) {
      out.writeln('  $key: [${value.join(', ')}],');
    }
    out
      ..writeln('};')
      ..writeln()
      ..writeln('/// The exception table of $from.hyp.txt.')
      ..writeln('const ${name}ExceptionTable = <String, List<int>>{');
    for (final MapEntry(:key, :value) in hyphenationExceptions(
      exceptions,
    ).entries) {
      out.writeln("  '$key': [${value.join(', ')}],");
    }
    out
      ..writeln('};')
      ..writeln();
  }
  File(_target).writeAsStringSync(out.toString().trimRight() + '\n');
}
