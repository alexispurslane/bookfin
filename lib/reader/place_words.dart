import 'dart:convert';

import '../catalog/model.dart';
import '../playback/records.dart';
import 'book_map.dart';
import 'document.dart';

/// [place] in words, by the rules of "A reading place in words" in
/// docs/plans/reading-history.md:
///
/// - A PDF place reads as its source page, such as "p. 12", in any edition.
/// - A place in the open book, at [address] on its [map], reads as its page
///   among the book's pages, such as "p. 134", once the map knows every
///   page, else as its share of the book, such as "37%", as the scrub bar's
///   drag label does. Its chapter comes from the map.
/// - Any other place reads as the first words of its quote. Its [quote]
///   is null when those words are the whole quote.
///
/// [address] is null when [place] is not in the open book. Page numbers
/// depend on the text size and the screen, so a caller asks again when the
/// map changes, and no record keeps them.
PlaceWords describeTextPlace(
  TextPosition place, {
  ReaderAddress? address,
  BookMap? map,
}) {
  final anchor = _anchor(place);
  final quote = switch (anchor['quote']) {
    final String text when text.trim().isNotEmpty => text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    ),
    _ => null,
  };
  // A PDF anchor names its source page, and an EPUB anchor its CFI.
  if (anchor case {'page': final int page} when anchor['cfi'] == null) {
    return (
      short: 'p. $page',
      chapter: null,
      quote: quote,
      along: AlongText(page: page),
    );
  }
  final fraction = address == null ? null : map?.fractionOf(address);
  if (map != null && fraction != null) {
    final target = map.targetAt(fraction);
    return (
      short: switch (target.page) {
        final page? => 'p. $page',
        null => '${(fraction * 100).round()}%',
      },
      chapter: target.chapter,
      quote: quote,
      along: AlongText(page: target.page, fraction: fraction),
    );
  }
  final shown = quote == null ? null : _firstWords(quote);
  return (
    short: shown == null ? 'Saved place' : '“$shown”',
    chapter: null,
    // A short quote reads whole in the place text, so a separate quote
    // would only repeat it.
    quote: shown == quote ? null : quote,
    along: null,
  );
}

/// The saved anchor of [place], or an empty map when it is not a JSON
/// object, as in a place saved by an early build.
Map<String, dynamic> _anchor(TextPosition place) {
  try {
    return switch (jsonDecode(place.anchor)) {
      final Map<String, dynamic> anchor => anchor,
      _ => const {},
    };
  } on FormatException {
    return const {};
  }
}

/// The number of words of a quote that name a place in a timeline row.
const _wordsShown = 6;

/// The first [_wordsShown] words of [quote], with an ellipsis when more
/// follow.
String _firstWords(String quote) {
  final words = quote.split(' ');
  return words.length <= _wordsShown
      ? quote
      : '${words.take(_wordsShown).join(' ')}…';
}
