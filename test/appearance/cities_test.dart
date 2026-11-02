import 'package:bookfin/appearance/cities.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sampleCities = '''1\tSão Paulo\tSao Paulo\tSão Paulo\tSao Paulo\tBrazil\tBR\t-23.5475\t-46.63611\t10000000
2\tSpringfield\t\tIllinois\t\tUnited States\tUS\t39.8\t-89.6\t110000
3\tSpringfield\t\tMissouri\t\tUnited States\tUS\t37.2\t-93.3\t160000
4\tCambridge\t\tEngland\t\tUnited Kingdom\tGB\t52.2\t0.1\t140000
5\tCambridge\t\tEngland\t\tUnited Kingdom\tGB\t52.3\t0.2\t10000
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'search finds city names and ASCII spellings with region or country',
    () {
      final catalog = CityCatalog.fromTsv(sampleCities);
      expect(
        catalog.search('SAO   PAULO').single.name,
        'São Paulo, São Paulo, Brazil',
      );
      expect(catalog.search('são paulo br').single.latitude, -23.5475);
      expect(catalog.search('Springfield, illinois').single.longitude, -89.6);
      expect(
        catalog.search('springfield missouri united states').single.latitude,
        37.2,
      );
      expect(catalog.search('  '), isEmpty);
      expect(catalog.search('zzzz'), isEmpty);
    },
  );

  test('same-name places remain distinct even within the same region', () {
    final cities = CityCatalog.fromTsv(sampleCities).search('cambridge');
    expect(cities.map((city) => city.name), [
      'Cambridge, England, United Kingdom · 4',
      'Cambridge, England, United Kingdom · 5',
    ]);
    expect(cities.map((city) => city.latitude), [52.2, 52.3]);
  });

  test(
    'search ranks name prefixes then larger cities and bounds the result list',
    () {
      final source = StringBuffer(
        '100\tNew Springfield\t\tRegion\t\tCountry\tUS\t0\t0\t999999\n',
      );
      for (var index = 1; index <= 40; index++) {
        source.writeln(
          '$index\tSpringfield $index\t\tRegion\t\tCountry\tUS\t0\t0\t$index',
        );
      }
      final cities = CityCatalog.fromTsv(source.toString())
          .search('springfield');
      expect(cities, hasLength(30));
      expect(cities.first.name, 'Springfield 40, Region, Country');
      expect(cities.last.name, 'Springfield 11, Region, Country');
    },
  );

  test(
    'invalid or ambiguous dataset records cannot offer selectable coordinates',
    () {
      final valid = sampleCities.split('\n').first;
      for (final source in [
        '',
        '$valid\n$valid',
        valid.replaceFirst('1\t', 'bad\t'),
        valid.replaceFirst('São Paulo\t', '\t'),
        valid.replaceFirst('Brazil\t', '\t'),
        valid.replaceFirst('BR\t', 'invalid\t'),
        valid.replaceFirst('-23.5475', '91'),
        valid.replaceFirst('-46.63611', '-181'),
        valid.replaceFirst('-23.5475', 'NaN'),
        valid.replaceFirst('10000000', '-1'),
        '$valid\textra',
        '1\tmissing fields',
      ]) {
        expect(
          () => CityCatalog.fromTsv(source),
          throwsFormatException,
          reason: source,
        );
      }
    },
  );

  test(
    'the complete bundled catalog loads and offers cities across continents',
    () async {
      final catalog = CityCatalog.fromTsv(
        await rootBundle.loadString('assets/cities/cities.tsv'),
      );
      for (final query in [
        'new york united states',
        'são paulo brazil',
        'tokyo japan',
        'nairobi kenya',
        'paris france',
        'sydney australia',
      ]) {
        expect(catalog.search(query), isNotEmpty, reason: query);
      }
    },
  );
}
