import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the directory containing the GeoNames extracts.');
  }
  final directory = arguments.single;
  final regions = <String, List<String>>{};
  for (final line in File(
    '$directory/admin1CodesASCII.txt',
  ).readAsLinesSync()) {
    final fields = line.split('\t');
    if (fields.length != 4) throw const FormatException('Invalid region row');
    regions[fields[0]] = fields;
  }
  final countries = <String, String>{};
  for (final line in File('$directory/countryInfo.txt').readAsLinesSync()) {
    if (line.startsWith('#') || line.isEmpty) continue;
    final fields = line.split('\t');
    if (fields.length < 5) throw const FormatException('Invalid country row');
    countries[fields[0]] = fields[4];
  }
  final rows = <List<String>>[];
  for (final line in File('$directory/cities15000.txt').readAsLinesSync()) {
    final fields = line.split('\t');
    if (fields.length != 19) throw const FormatException('Invalid city row');
    final country = countries[fields[8]];
    if (country == null) throw FormatException('Unknown country ${fields[8]}');
    final region = regions['${fields[8]}.${fields[10]}'];
    rows.add([
      fields[0],
      fields[1],
      fields[2] == fields[1] ? '' : fields[2],
      region?[1] ?? '',
      region == null || region[2] == region[1] ? '' : region[2],
      country,
      fields[8],
      fields[4],
      fields[5],
      fields[14],
    ]);
  }
  rows.sort(
    (first, second) => int.parse(first[0]).compareTo(int.parse(second[0])),
  );
  stdout.encoding = utf8;
  for (final row in rows) {
    stdout.writeln(row.join('\t'));
  }
}
