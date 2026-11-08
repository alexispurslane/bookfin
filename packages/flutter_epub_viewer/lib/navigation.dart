class ReadingLocation {
  const ReadingLocation(
    this.cfi,
    this.resource,
    this.quote, {
    this.chapter,
    this.page,
    this.pages,
    this.progress,
  });
  final String cfi;
  final String resource;
  final String quote;
  final String? chapter;
  final int? page;
  final int? pages;

  /// The text progress of the place through its section, from 0 to 1: the
  /// share of the section's visible characters, white space left out, that
  /// come before it. It places the location along the whole book, so it is
  /// saved with the place. A place saved before it existed has none.
  final double? progress;
  Map<String, dynamic> toJson() => {
    'cfi': cfi,
    'resource': resource,
    'quote': quote,
    if (progress != null) 'progress': progress,
  };
  factory ReadingLocation.fromJson(Map<String, dynamic> value) {
    if (value['cfi'] is! String ||
        value['resource'] is! String ||
        value['quote'] is! String) {
      throw const FormatException('The reader returned an invalid location.');
    }
    final progress = value['progress'];
    if (progress != null &&
        (progress is! num || !(progress >= 0 && progress <= 1))) {
      throw const FormatException('The reader returned an invalid location.');
    }
    final location = ReadingLocation(
      value['cfi'] as String,
      value['resource'] as String,
      value['quote'] as String,
      chapter: value['chapter'] is String ? value['chapter'] as String : null,
      page: value['page'] is int ? value['page'] as int : null,
      pages: value['pages'] is int ? value['pages'] as int : null,
      progress: (progress as num?)?.toDouble(),
    );
    if (!location.cfi.startsWith('epubcfi(') ||
        !location.cfi.endsWith(')') ||
        location.cfi.length > 4096 ||
        location.resource.length > 512 ||
        location.quote.length > 160 ||
        (location.chapter?.length ?? 0) > 512 ||
        (location.page != null &&
            (location.page! < 1 ||
                location.pages == null ||
                location.pages! < location.page!)) ||
        (location.pages != null && location.page == null)) {
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

  /// Shows the page that holds the place [progress] of the way through the
  /// text of spine section [section], from 0 at its start to 1 at its end.
  /// [ReadingLocation.progress] measures text progress.
  Future<void> seek(int section, double progress);
  Future<void> configure({required double fontSize, required bool night});
  Future<SearchReport> search(String query, int request);
  Future<void> cancelSearch(int request);
}
