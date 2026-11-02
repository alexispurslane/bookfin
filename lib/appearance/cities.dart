import 'dart:convert';

import 'appearance.dart';

class CityCatalog {
  CityCatalog.fromTsv(String source) : _cities = _readCities(source);

  final List<_City> _cities;

  List<SelectedLocation> search(String query) {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final matches = _cities
        .where((city) => words.every(city.searchText.contains))
        .toList();
    final phrase = words.join(' ');
    matches.sort((first, second) {
      final firstPrefix = first.names.any((name) => name.startsWith(phrase));
      final secondPrefix = second.names.any((name) => name.startsWith(phrase));
      if (firstPrefix != secondPrefix) return firstPrefix ? -1 : 1;
      final populationOrder = second.population.compareTo(first.population);
      return populationOrder != 0
          ? populationOrder
          : first.location.name.compareTo(second.location.name);
    });
    return matches.take(30).map((city) => city.location).toList();
  }
}

class _City {
  _City(this.location, this.names, this.searchText, this.population);

  final SelectedLocation location;
  final List<String> names;
  final String searchText;
  final int population;
}

List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[\s,\.\-]+'))
    .where((word) => word.isNotEmpty)
    .toList();

List<_City> _readCities(String source) {
  final rows = const LineSplitter()
      .convert(source)
      .where((line) => line.isNotEmpty)
      .map((line) => line.split('\t'))
      .toList();
  if (rows.isEmpty) throw const FormatException('City catalog is empty');
  final identifiers = <int>{};
  final labels = <String, int>{};
  for (final row in rows) {
    if (row.length != 10) throw const FormatException('Invalid city fields');
    final identifier = int.tryParse(row[0]);
    final latitude = double.tryParse(row[7]);
    final longitude = double.tryParse(row[8]);
    final population = int.tryParse(row[9]);
    if (identifier == null ||
        identifier <= 0 ||
        !identifiers.add(identifier) ||
        row[1].trim().isEmpty ||
        row[5].trim().isEmpty ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(row[6]) ||
        latitude == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude == null ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        population == null ||
        population < 0) {
      throw FormatException('Invalid city record ${row[0]}');
    }
    final label = _label(row);
    labels.update(label, (count) => count + 1, ifAbsent: () => 1);
  }
  return [
    for (final row in rows)
      _City(
        SelectedLocation(
          _label(row) + (labels[_label(row)]! > 1 ? ' · ${row[0]}' : ''),
          double.parse(row[7]),
          double.parse(row[8]),
        ),
        [_words(row[1]).join(' '), _words(row[2]).join(' ')],
        _words(row.sublist(1, 7).join(' ')).join(' '),
        int.parse(row[9]),
      ),
  ];
}

String _label(List<String> row) =>
    [row[1], if (row[3].isNotEmpty) row[3], row[5]].join(', ');
