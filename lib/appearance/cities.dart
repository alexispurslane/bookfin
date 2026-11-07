import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'appearance.dart';

/// The parsed city list and its matching rules. [CityFinder] keeps one in
/// its own isolate, because the bundled list is too large to parse or
/// search on the UI isolate without dropping frames.
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

/// Searches [catalog] for [query]. It runs in the finder's isolate.
typedef CitySearchWork = List<SelectedLocation> Function(
  CityCatalog catalog,
  String query,
);

List<SelectedLocation> searchCatalog(CityCatalog catalog, String query) =>
    catalog.search(query);

/// The city catalog of one search page, which lives in its own isolate
/// and answers each search there, so a keystroke does not filter the
/// catalog on the UI isolate.
///
/// Each search sends the query and receives at most 30 places, so a search
/// copies little. [close] ends the isolate.
class CityFinder {
  CityFinder._(this._isolate, this._replies, this._requests);
  final Isolate _isolate;
  final ReceivePort _replies;
  final SendPort _requests;
  final Map<int, Completer<List<SelectedLocation>>> _answers = {};
  int _asked = 0;

  /// Parses [source] in a new isolate, which then answers searches with
  /// [search]. Throws a [FormatException] when [source] is not a valid
  /// city list.
  static Future<CityFinder> start(
    String source, {
    CitySearchWork search = searchCatalog,
  }) async {
    final replies = ReceivePort();
    final ready = Completer<CityFinder>();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(_serve, (
        replies: replies.sendPort,
        source: source,
        search: search,
      ), debugName: 'city finder');
    } on Object {
      replies.close();
      rethrow;
    }
    replies.listen((message) {
      switch (message) {
        case SendPort requests:
          ready.complete(CityFinder._(isolate, replies, requests));
        case (int asked, List<SelectedLocation> places):
          ready.future.then((finder) => finder._answer(asked, places));
        case String failure:
          replies.close();
          isolate.kill();
          ready.completeError(FormatException(failure));
      }
    });
    return ready.future;
  }

  /// The places that match [query], best first. A blank query matches
  /// nothing and asks no isolate.
  Future<List<SelectedLocation>> search(String query) {
    // NOTE: Engine rule 1. This splits one query of at most 120 characters,
    // which costs less than a hop.
    if (_words(query).isEmpty) return Future.value(const []);
    final asked = _asked++;
    final answer = _answers[asked] = Completer();
    _requests.send((asked, query));
    return answer.future;
  }

  void _answer(int asked, List<SelectedLocation> places) =>
      _answers.remove(asked)?.complete(places);

  /// Ends the isolate. A search that waits for an answer gets none.
  void close() {
    _replies.close();
    _isolate.kill();
    _answers.clear();
  }
}

/// The finder isolate: parses the city list, then answers each search.
void _serve(({SendPort replies, String source, CitySearchWork search}) start) {
  final CityCatalog catalog;
  try {
    catalog = CityCatalog.fromTsv(start.source);
  } on FormatException catch (error) {
    start.replies.send(error.message);
    return;
  }
  final requests = ReceivePort();
  start.replies.send(requests.sendPort);
  requests.listen((message) {
    final (int asked, String query) = message as (int, String);
    start.replies.send((asked, start.search(catalog, query)));
  });
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
