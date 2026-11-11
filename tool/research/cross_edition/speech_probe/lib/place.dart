// Tool code for the boo-snng speech prototype, not part of Bookfin.
// The two directions of speech placement: a listening place into the
// ebook, and a reading place into the audiobook.
import 'dart:math' as math;

import 'search.dart';
import 'text.dart';

/// The words of [lengthMs] of the recording from [startMs], with the
/// window's real start (a window does not cross a file's start or end).
typedef Listen = Future<({Heard heard, int startMs})?> Function(
  int startMs,
  int lengthMs,
);

/// The visible characters of one page in the design doc.
const pageCharacters = 582;

/// One search of one window: the place it found and how long it took.
class Step {
  Step(this.windowMs, this.found, this.confident, this.radiusPages, this.searchUs);
  final int windowMs;
  final Found? found;
  final bool confident;

  /// The search radius that found the place, or the last one tried.
  final double radiusPages;
  final int searchUs;

  Map<String, Object?> toJson() => {
    'windowMs': windowMs,
    'matched': found?.matched,
    'runnerUp': found?.runnerUp,
    'heard': found?.heard,
    'confident': confident,
    // The whole book is -1, because JSON has no infinity.
    'radiusPages': radiusPages.isInfinite ? -1 : radiusPages,
    'searchUs': searchUs,
    'start': found?.pairs.first.$2,
    'end': found?.pairs.last.$2,
  };
}

/// Searches [heard] around book word [around] in growing radii (in pages),
/// and stops at the first confident place.
Step searchAround(
  BookText book,
  Heard heard,
  int windowMs,
  int around,
  List<double> radiiPages,
) {
  final watch = Stopwatch()..start();
  Found? found;
  var radius = radiiPages.first;
  for (radius in radiiPages) {
    final chars = book.offsets[around].toDouble();
    final lo = radius.isInfinite ? 0 : math.min(book.wordAt(chars - radius * pageCharacters), book.bodyEnd - 1);
    final hi = radius.isInfinite
        ? book.bodyEnd
        : math.max(lo + 1, math.min(book.bodyEnd, book.wordAt(chars + radius * pageCharacters)));
    found = search(book, heard.words, lo, hi);
    if (found != null && found.confident()) {
      return Step(windowMs, found, true, radius, watch.elapsedMicroseconds);
    }
  }
  return Step(windowMs, found, false, radius, watch.elapsedMicroseconds);
}

/// The radii of a whole-book estimate, in pages: about its median error
/// (5.2 pages), its 90th percentile (22.4), three times that, then the
/// whole book.
const wholeBookRadii = [8.0, 24.0, 72.0, double.infinity];

/// The radii of an estimate from matched chapters: about twice its 90th
/// percentile (1.39 pages), then wider.
const chapterRadii = [3.0, 24.0, double.infinity];

/// The ebook word where a listening place at [atMs] lands: transcribe a
/// window of [lengthMs] around it, search near [estimateWord], and land on
/// the heard word nearest to [atMs]. Null when no confident place exists.
Future<({int? word, Step? step})> audioToText({
  required BookText book,
  required Listen listen,
  required int atMs,
  required int estimateWord,
  required List<double> radiiPages,
  int lengthMs = 15000,
}) async {
  final window = await listen(math.max(0, atMs - lengthMs ~/ 2), lengthMs);
  if (window == null || window.heard.words.isEmpty) return (word: null, step: null);
  final step = searchAround(book, window.heard, window.startMs, estimateWord, radiiPages);
  if (!step.confident) return (word: null, step: step);
  final target = atMs - window.startMs;
  var j = 0;
  for (var k = 0; k < window.heard.ms.length; k++) {
    if ((window.heard.ms[k] - target).abs() < (window.heard.ms[j] - target).abs()) j = k;
  }
  return (word: step.found!.bookWordOf(j), step: step);
}

/// The result of a reading place placed in the audiobook.
class AudioPlace {
  AudioPlace(this.ms, this.steps, this.converged);

  /// The landing time, or the last estimate when the loop did not converge.
  final int ms;
  final List<Step> steps;

  /// Whether a transcribed window held the target word.
  final bool converged;
}

/// The range of narration rates, in ms per word: 1.85 to 3.7 words a
/// second. A recording's own rate (its length over the book's words) is
/// clamped to it, because a book can hold more than the recording reads,
/// as a collection of stories does.
const narrationMsPerWord = (min: 270.0, max: 540.0);

/// The longest run of [pairs] whose book words follow their heard words
/// closely: a stray match of a common word at either end is left out.
List<(int, int)> densePairs(List<(int, int)> pairs) {
  var best = <(int, int)>[], run = <(int, int)>[];
  for (final p in pairs) {
    if (run.isNotEmpty && p.$2 - run.last.$2 > (p.$1 - run.last.$1) + 4) {
      if (run.length > best.length) best = run;
      run = [];
    }
    run.add(p);
  }
  return run.length > best.length ? run : best;
}

/// The audiobook time where book word [target] is spoken. Starts at
/// [estimateMs], transcribes a window there, finds its words, and moves by
/// the words between them and the target at the local reading rate, until
/// a window holds the target. Gives up after [maxRounds] windows.
Future<AudioPlace> textToAudio({
  required BookText book,
  required Listen listen,
  required int target,
  required int estimateMs,
  required double msPerWord,
  required List<double> radiiPages,
  required int lengthMs,
  int maxRounds = 6,
}) async {
  final steps = <Step>[];
  final seen = <(int, int)>[]; // (ms, book word) of found windows
  var at = estimateMs;
  final prior = msPerWord.clamp(narrationMsPerWord.min, narrationMsPerWord.max);
  var rate = prior;
  var wasNear = false;
  for (var round = 0; round < maxRounds; round++) {
    final window = await listen(math.max(0, at - lengthMs ~/ 2), lengthMs);
    if (window == null) break;
    // Where the window should be in the book, from the last found window,
    // or from the estimate in the first round.
    final expected = seen.isEmpty
        ? target
        : (seen.last.$2 + (window.startMs - seen.last.$1) / rate).round().clamp(0, book.words.length - 1);
    final radii = seen.isEmpty ? radiiPages : const [3.0, 24.0, double.infinity];
    final step = searchAround(book, window.heard, window.startMs, expected, radii);
    steps.add(step);
    if (!step.confident) {
      // Music, credits or a passage that the ebook lacks: step past it.
      at += lengthMs;
      continue;
    }
    final pairs = densePairs(step.found!.pairs);
    final ms = window.heard.ms;
    // The target is in the window. Or it is within a dozen words of the
    // matched words for the second time in a row: a heading that the
    // narrator words differently, or the edge of a file.
    final inside = target >= pairs.first.$2 && target <= pairs.last.$2;
    final near = target >= pairs.first.$2 - 12 && target <= pairs.last.$2 + 12;
    if (inside || (near && wasNear)) {
      var best = pairs.first;
      for (final p in pairs) {
        if ((p.$2 - target).abs() < (best.$2 - target).abs()) best = p;
      }
      final landing = window.startMs + ms[best.$1] + ((target - best.$2) * rate).round();
      return AudioPlace(landing, steps, true);
    }
    // The pair nearest the window's middle stands for the window.
    final middle = ms.isEmpty ? 0 : ms.last ~/ 2;
    var reference = pairs.first;
    for (final p in pairs) {
      if ((ms[p.$1] - middle).abs() < (ms[reference.$1] - middle).abs()) reference = p;
    }
    final point = (window.startMs + ms[reference.$1], reference.$2);
    // Two found windows far enough apart give the local rate.
    for (final earlier in seen.reversed) {
      final dMs = point.$1 - earlier.$1, dWords = point.$2 - earlier.$2;
      if (dMs.abs() > 20000 && dWords != 0) {
        final local = dMs / dWords;
        if (local > prior / 2 && local < prior * 2) rate = local;
        break;
      }
    }
    seen.add(point);
    wasNear = near;
    at = point.$1 + ((target - point.$2) * rate).round();
  }
  return AudioPlace(at, steps, false);
}
