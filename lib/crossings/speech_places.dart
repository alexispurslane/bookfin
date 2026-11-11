import 'dart:async';

import '../catalog/model.dart';
import '../playback/audio_outline.dart';
import '../reader/text_outline.dart';
import '../speech/book_search.dart';
import '../speech/book_words.dart';
import '../speech/heard_windows.dart';
import '../speech/place.dart';
import '../speech/search.dart';
import '../speech/words.dart';
import 'alignment.dart' show MatchedChapters;

/// One pair of an audio and an ebook edition, as the speech stage reads it.
/// [key] names the pair, and [textKey] the ebook's file revision, under
/// which the worker keeps its words. [outline] is the ebook's outline, and
/// [matched] the matched chapters of the pair, when they match, which give
/// the estimates.
typedef SpeechPair = ({
  Edition audio,
  Edition text,
  String key,
  String textKey,
  TextOutline outline,
  MatchedChapters? matched,
});

/// The speech stage of Crossings (docs/plans/cross-edition-places.md, "How
/// Crossings lands a place by speech"). Like matched chapters, it turns a
/// time of a recording into the characters of an ebook, and the reverse,
/// from the words that the narrator speaks there. It answers for one place
/// at a time, and it may hear a window first.
///
/// It owns the words of the latest ebooks, in a [BookSearch] worker, and
/// the anchor map of each pair: the heard windows that the ebook holds,
/// each with its time and its word. It reads the heard windows of
/// [heard], and asks it for a window when no kept window helps. Every
/// search runs in the worker, so the UI isolate never waits for it.
class SpeechPlaces {
  SpeechPlaces({required this.heard, required this.words});

  final HeardWindows heard;

  /// The reader of the words of a downloaded ebook edition, or null when
  /// speech cannot read them.
  final Future<ReadBook?> Function(Edition text) words;

  final _books = BookSearch();

  /// The anchor map of each pair, by pair key.
  final _maps = <String, _AnchorMap>{};

  /// The growth of each anchor map in flight, by pair key.
  final _growing = <String, Future<void>>{};

  /// Starts the anchor map of [pair] in the background, so that a later
  /// place lands without hearing a window.
  Future<void> prepare(SpeechPair pair) async {
    final read = await words(pair.text);
    if (read != null) await _anchors(pair, read);
  }

  /// The characters of the ebook before the word that the narrator speaks
  /// at [place], or null when speech cannot tell. A kept window that covers
  /// the place lands it on its heard word. Else two anchors around it place
  /// it between them. Else a window is heard at the place now.
  Future<double?> charactersAt(AudioPosition place, SpeechPair pair) async {
    final recording = audioOutline(pair.audio);
    final at = recording.editionTime(place);
    final length = recording.length;
    if (at == null || length == null || length == 0) return null;
    final read = await words(pair.text);
    if (read == null) return null;
    final windows = await heard.windowsOf(pair.audio);
    var window = windows.where((window) => window.covers(place)).firstOrNull;
    if (window == null) {
      final between = charactersBetween(await _anchors(pair, read), at);
      if (between != null) return between;
      window = await heard.hear(pair.audio, place);
      if (window == null) return null;
    }
    final chapters = pair.matched?.charactersAt(at);
    return _books.withBook<double?>(
      pair.textKey,
      read,
      _landing(
        window.heard,
        place.milliseconds - window.startMs,
        chapters ?? at / length * pair.outline.length,
        chapters == null ? wholeBookRadii : nearRadii,
      ),
    );
  }

  /// The time of the recording, from its start, when the narrator speaks
  /// the word after [characters] of the ebook, or null when speech cannot
  /// tell. It runs the reading-place loop ([ReadingSearch]) from an
  /// estimate: two anchors around the place, else matched chapters, else
  /// the share of the book. A kept window at the estimate needs no hearing.
  Future<int?> millisecondsAt(double characters, SpeechPair pair) async {
    final length = audioOutline(pair.audio).length;
    if (length == null || length == 0) return null;
    final read = await words(pair.text);
    if (read == null) return null;
    final book = await _books.withBook(pair.textKey, read, _target(characters));
    if (book == null || book.words == 0) return null;
    final between = millisecondsBetween(await _anchors(pair, read), characters);
    final chapters = between ?? pair.matched?.millisecondsAt(characters);
    final search = ReadingSearch(
      target: book.target,
      estimateMs:
          chapters ?? (characters / pair.outline.length * length).round(),
      msPerWord: length / book.words,
      radii: chapters == null ? wholeBookRadii : nearRadii,
    );
    final starts = audioOutline(pair.audio).fileStarts;
    while (!search.exhausted) {
      final place = audioPlaceAt(pair.audio, search.nextMs);
      if (place == null) return null;
      final window = await heard.hear(pair.audio, place);
      if (window == null) {
        // Silence, music, or a file that this phone streams.
        search.fold(
          search.nextMs - HeardWindows.windowMs ~/ 2,
          Heard(const [], const []),
          null,
        );
        continue;
      }
      final start = starts[window.sourceKey]! + window.startMs;
      final match = await _books.withBook<WordMatch?>(
        pair.textKey,
        read,
        _search(window.heard.words, search.expectedWord(start), search.radii),
      );
      final landed = search.fold(start, window.heard, match);
      if (landed != null) return landed;
    }
    return null;
  }

  /// The anchors of [pair], in the order of the recording, after the
  /// windows that arrived since the last growth are searched. One growth
  /// runs at a time for each pair.
  Future<List<Anchor>> _anchors(SpeechPair pair, ReadBook read) async {
    for (
      var growing = _growing[pair.key];
      growing != null;
      growing = _growing[pair.key]
    ) {
      await growing;
    }
    final growth = _grow(pair, read);
    _growing[pair.key] = growth;
    try {
      await growth;
    } finally {
      if (identical(_growing[pair.key], growth)) _growing.remove(pair.key);
    }
    return _maps[pair.key]?.anchors ?? const [];
  }

  /// Searches the windows of [pair] that its anchor map did not search yet,
  /// and adds the ones that the ebook holds.
  Future<void> _grow(SpeechPair pair, ReadBook read) async {
    final map = _maps[pair.key] ?? _AnchorMap(const {}, const []);
    final recording = audioOutline(pair.audio);
    final length = recording.length;
    if (length == null || length == 0) return;
    final fresh = [
      for (final window in await heard.windowsOf(pair.audio))
        if (!map.searched.contains(_windowKey(window))) window,
    ];
    if (fresh.isEmpty) return;
    double coarse(int at) =>
        pair.matched?.charactersAt(at) ?? at / length * pair.outline.length;
    final inputs = [
      for (final window in fresh)
        if (recording.fileStarts[window.sourceKey] case final start?)
          (
            startMs: start + window.startMs,
            heard: window.heard,
            coarse: coarse(start + window.startMs + window.lengthMs ~/ 2),
          ),
    ];
    final found = await _books.withBook(pair.textKey, read, _anchorsOf(inputs));
    if (found == null) return;
    _maps[pair.key] = _AnchorMap({
      ...map.searched,
      for (final window in fresh) _windowKey(window),
    }, [...map.anchors, ...found]..sort((a, b) => a.ms.compareTo(b.ms)));
  }

  static String _windowKey(HeardWindow window) =>
      '${window.sourceKey}\n${window.revision}\n${window.startMs}';

  Future<void> close() => _books.close();

  // NOTE: The jobs below travel to the worker of the book's words, so each
  // is made by a static function and captures only plain data.

  /// The characters before the book word of the heard word at [atMs] of
  /// [heard], searched near [estimate] characters in [radii].
  static double? Function(BookWords) _landing(
    Heard heard,
    int atMs,
    double estimate,
    List<double> radii,
  ) => (book) {
    final word = landHeard(
      book,
      heard,
      atMs: atMs,
      around: book.wordAt(estimate),
      radii: radii,
    );
    return word == null ? null : book.offsets[word].toDouble();
  };

  /// The book word at [characters], and the words that a narrator reads.
  static ({int target, int words}) Function(BookWords) _target(
    double characters,
  ) =>
      (book) => (target: book.wordAt(characters), words: book.bodyEnd);

  static WordMatch? Function(BookWords) _search(
    List<String> heard,
    int around,
    List<double> radii,
  ) =>
      (book) => searchAround(book, heard, around, radii);

  static List<Anchor> Function(BookWords) _anchorsOf(
    List<({int startMs, Heard heard, double coarse})> windows,
  ) =>
      (book) => findAnchors(book, windows);
}

/// The anchors of one pair, in the order of the recording, and the keys of
/// the windows that were searched for them.
class _AnchorMap {
  _AnchorMap(this.searched, this.anchors);
  final Set<String> searched;
  final List<Anchor> anchors;
}
