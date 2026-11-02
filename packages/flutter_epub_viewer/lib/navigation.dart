class ReadingLocation {
  const ReadingLocation(this.cfi, this.resource, this.quote);
  final String cfi;
  final String resource;
  final String quote;
  Map<String, dynamic> toJson() => {
    'cfi': cfi,
    'resource': resource,
    'quote': quote,
  };
  factory ReadingLocation.fromJson(Map<String, dynamic> value) {
    if (value['cfi'] is! String ||
        value['resource'] is! String ||
        value['quote'] is! String) {
      throw const FormatException('The reader returned an invalid location.');
    }
    final location = ReadingLocation(
      value['cfi'] as String,
      value['resource'] as String,
      value['quote'] as String,
    );
    if (!location.cfi.startsWith('epubcfi(') ||
        !location.cfi.endsWith(')') ||
        location.cfi.length > 4096 ||
        location.resource.length > 512 ||
        location.quote.length > 160) {
      throw const FormatException('The reader returned an invalid location.');
    }
    return location;
  }
}

class ContentsEntry {
  const ContentsEntry(this.title, this.href, {this.depth = 0});
  final String title;
  final String href;
  final int depth;
}

class SearchHit {
  const SearchHit(this.location, this.excerpt);
  final ReadingLocation location;
  final String excerpt;
}

class SearchReport {
  const SearchReport(this.hits, {this.error});
  final List<SearchHit> hits;
  final String? error;
}

abstract interface class NavigatorPort {
  Future<void> move(bool forward);
  Future<void> display(ReadingLocation location);
  Future<void> contents(String href);
  Future<void> configure({required double fontSize, required bool night});
  Future<SearchReport> search(String query, int request);
  Future<void> cancelSearch(int request);
}
