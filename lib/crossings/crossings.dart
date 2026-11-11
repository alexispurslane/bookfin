import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/model.dart';
import '../foundation/hop.dart';
import '../playback/audio_outline.dart';
import '../playback/records.dart' show MatchedBy;
import '../reader/document.dart';
import '../reader/text_outline.dart';
import 'alignment.dart';

export '../playback/records.dart' show MatchedBy;

/// Where [Crossings] keeps the text outlines that it measured, between
/// launches. The outlines are derived data: a lost or unreadable one costs
/// only a new measurement, while the ebook is downloaded.
abstract class OutlineStore {
  /// The kept value of [key], or null when none is kept.
  Future<String?> read(String key);

  /// Keeps [value] for [key], replacing any older value. A crash during the
  /// write leaves the old value or the new one, never a broken one.
  Future<void> write(String key, String value);
}

/// Where a place of one edition lands in the edition of the other medium
/// of the same book: a [Landing], or [NoLanding] with the reason why none
/// exists.
sealed class Crossing {
  const Crossing();
}

/// The counterpart of a place of the other edition in the open edition,
/// and how Bookfin found it.
sealed class Landing extends Crossing {
  const Landing();

  /// The place of the other edition that the choice named.
  Place get from;

  /// How Bookfin found the landing.
  MatchedBy get matchedBy => MatchedBy.chapters;
}

/// Where a listening place lands in an ebook edition.
final class TextLanding extends Landing {
  const TextLanding(this.from, this.place, {required this.into});

  @override
  final AudioPosition from;

  /// The landing: a section of the ebook's spine and the share of its
  /// visible characters before the landing, as the book map and the
  /// navigator's seek read a place.
  final BookPlace place;

  /// The ebook edition of the landing, at the file revision whose outline
  /// placed it.
  final ({String editionId, String sourceKey, String revision}) into;
}

/// Where a reading place lands in an audio edition.
final class AudioLanding extends Landing {
  const AudioLanding(this.from, this.place);

  @override
  final TextPosition from;

  /// The landing, a time in a file of the audio edition.
  final AudioPosition place;
}

/// No defensible counterpart exists, for [reason].
final class NoLanding extends Crossing {
  const NoLanding(this.reason);
  final Refusal reason;
}

/// The app's one owner of cross-edition landings (docs/plans/
/// cross-edition-places.md, "Owners"). It derives the text outline of each
/// ebook edition and the alignment of each pair of an audio and an ebook
/// edition, keeps them, and places a place of one edition in the other. It
/// reads files and catalog editions, and writes no personal record: only
/// the owner of the open edition moves its own place to a landing.
///
/// A text outline comes from memory, else from [OutlineStore], else from a
/// measurement of the downloaded ebook in a worker isolate, which is then
/// kept. Each outline is keyed by its edition and the revision of its file,
/// so a changed ebook is measured again, and a removed download keeps its
/// outline. The alignment of a pair runs once, in one hop to another
/// isolate. Work in flight is shared: two requests of one outline measure
/// it once, and two requests of one pair align it once. A pair whose ebook
/// this phone could not measure is tried again when downloads change. Work
/// that fails is not kept, so a later request tries again.
///
/// Invariants, which [checkInvariants] checks:
/// - Each finished pair is the result of the pair's current work.
/// - Each alignment of matched chapters comes from the outline that is
///   kept for its ebook, and keeps its own invariants: anchors increase
///   strictly, and every span reads in the rate band.
class Crossings {
  /// [measure] measures the text outline of a downloaded ebook edition, or
  /// gives null when this phone has no download of it. It throws an
  /// [UnsupportedError] when Bookfin cannot measure the outline of the
  /// ebook's format yet, and an [Exception] when it cannot read the file.
  /// [downloads] notifies when downloads change, so that an ebook that was
  /// not measured is tried again. [hop] runs the alignment in another
  /// isolate.
  Crossings({
    required this._store,
    required this._measure,
    this._downloads,
    this._hop = compute,
  }) {
    _downloads?.addListener(_retryMissing);
  }

  final OutlineStore _store;
  final Future<TextOutline?> Function(Edition text) _measure;
  final Listenable? _downloads;
  final IsolateHop _hop;

  /// The measurement version of the kept outlines. Raise it when the
  /// outline measures characters in another way, so that kept outlines are
  /// measured again.
  static const outlineVersion = 1;

  /// The text outlines read or measured so far, by outline key.
  final _outlines = <String, TextOutline>{};

  /// The outline work in flight, by outline key.
  final _outlineWork = <String, Future<TextOutline?>>{};

  /// The work in flight or done for each pair, by pair key.
  final _pairs = <String, Future<_Pair>>{};

  /// The finished work of each pair, by pair key.
  final _done = <String, _Pair>{};

  final _changes = _Changes();
  var _disposed = false;

  /// Notifies when the alignment of a pair arrives, or when a pair that had
  /// no outline may now have one, so [landingNow] can give a new answer.
  Listenable get changes => _changes;

  /// Where [place], a place of [from], lands in [into], the edition of the
  /// other medium of the same book, once the two editions are aligned.
  Future<Crossing> landing(
    Place place, {
    required Edition from,
    required Edition into,
  }) async {
    _guard(from, into);
    _guardPlace(place, from);
    return _land(place, from, into, await _pair(from, into));
  }

  /// What [landing] gives when the two editions are already aligned, else
  /// null. A null answer starts the alignment in the background, and
  /// [changes] notifies when it arrives.
  Crossing? landingNow(
    Place place, {
    required Edition from,
    required Edition into,
  }) {
    _guard(from, into);
    _guardPlace(place, from);
    if (_done[_pairKey(from, into)] case final pair?) {
      return _land(place, from, into, pair);
    }
    unawaited(_pair(from, into));
    return null;
  }

  /// Starts the alignment of [from] and [into], two editions of the two
  /// media, in the background, so that [landingNow] can soon answer.
  void prepare({required Edition from, required Edition into}) {
    _guard(from, into);
    unawaited(_pair(from, into));
  }

  static void _guard(Edition from, Edition into) {
    if (from.kind == into.kind) {
      throw ArgumentError('Give two editions of the two media.');
    }
  }

  static void _guardPlace(Place place, Edition from) {
    if (place.editionId != from.id) {
      throw ArgumentError('Give a place of [from].');
    }
  }

  /// The alignment work of the pair of [from] and [into], in flight or done.
  Future<_Pair> _pair(Edition from, Edition into) {
    final (audio, text) = from.kind == EditionKind.audio
        ? (from, into)
        : (into, from);
    final key = _pairKey(from, into);
    if (_pairs[key] case final work?) return work;
    late final Future<_Pair> work;
    work = () async {
      try {
        final pair = await _align(audio, text);
        // A change of downloads during the work forgets it, and a later
        // request's work counts.
        if (!_disposed && identical(_pairs[key], work)) {
          _done[key] = pair;
          _changes.notify();
        }
        return pair;
      } catch (_) {
        // A failure is a bug. It is not kept, so a later request tries
        // again.
        if (identical(_pairs[key], work)) _pairs.remove(key);
        rethrow;
      }
    }();
    return _pairs[key] = work;
  }

  /// The alignment of [audio] with [text], or why none exists.
  Future<_Pair> _align(Edition audio, Edition text) async {
    final TextOutline? outline;
    try {
      outline = await _outline(text);
    } on UnsupportedError {
      return const _Refused(Refusal.unsupportedFormat);
    } on Exception {
      return const _Refused(Refusal.unreadable);
    }
    if (outline == null) return const _Refused(Refusal.noOutline);
    return switch (await _hop(_alignPair, (audioOutline(audio), outline))) {
      final MatchedChapters matched => _Aligned(
        outline,
        _outlineKey(text),
        matched,
      ),
      UnmatchedChapters(:final reason) => _Refused(reason),
    };
  }

  /// The text outline of [text]: kept in memory, kept in the store, or
  /// measured from its download and then kept. Null when none is kept and
  /// this phone has no download of it. It throws what [_measure] throws.
  Future<TextOutline?> _outline(Edition text) {
    final key = _outlineKey(text);
    if (_outlines[key] case final outline?) return Future.value(outline);
    if (_outlineWork[key] case final work?) return work;
    late final Future<TextOutline?> work;
    work = _findOutline(text, key).whenComplete(() {
      if (identical(_outlineWork[key], work)) _outlineWork.remove(key);
    });
    return _outlineWork[key] = work;
  }

  /// The outline of [text] under [key] from the store, else from a
  /// measurement, which is then kept.
  Future<TextOutline?> _findOutline(Edition text, String key) async {
    final kept = await _readKept(key);
    if (kept != null) return _outlines[key] = kept;
    final measured = await _measure(text);
    if (measured == null) return null;
    _outlines[key] = measured;
    // NOTE: Engine rule 1. The JSON of an outline holds one short entry for
    // each contents entry and section, about 10 to 20 KB for a long novel.
    // Its encode costs less than a hop to another isolate.
    final value = jsonEncode({'key': key, 'outline': measured.toJson()});
    try {
      await _store.write(key, value);
    } on Exception {
      // A lost outline costs only a new measurement at a later launch.
    }
    return measured;
  }

  /// The outline that the store keeps for [key], or null when it keeps
  /// none, or keeps one that cannot be read, which is then measured again.
  /// A kept value names its key, so an outline is used only under the key
  /// of the edition revision that it was measured from.
  Future<TextOutline?> _readKept(String key) async {
    try {
      final value = await _store.read(key);
      if (value == null) return null;
      // NOTE: Engine rule 1. A kept outline is 10 to 20 KB of JSON, see
      // [_findOutline].
      final json = jsonDecode(value);
      if (json case {'key': final String kept, 'outline': final Map outline}
          when kept == key) {
        return TextOutline.fromJson(outline.cast());
      }
      return null;
    } on Exception {
      return null;
    }
  }

  /// Forgets the pairs whose ebook this phone could not measure, and the
  /// pairs in flight, so that the next request tries them again, now that
  /// downloads changed.
  void _retryMissing() {
    final stale = [
      for (final key in _pairs.keys)
        if (switch (_done[key]) {
          null => true,
          _Refused(:final reason) =>
            reason == Refusal.noOutline || reason == Refusal.unreadable,
          _Aligned() => false,
        })
          key,
    ];
    if (stale.isEmpty) return;
    for (final key in stale) {
      _done.remove(key);
      _pairs.remove(key);
    }
    _changes.notify();
  }

  /// Where [place] of [from] lands in [into], by [pair].
  Crossing _land(Place place, Edition from, Edition into, _Pair pair) {
    final TextOutline outline;
    final MatchedChapters matched;
    switch (pair) {
      case _Refused(:final reason):
        return NoLanding(reason);
      case _Aligned(outline: final kept, :final alignment):
        outline = kept;
        matched = alignment;
    }
    switch (place) {
      case AudioPosition():
        final at = place.fits(from)
            ? audioOutline(from).editionTime(place)
            : null;
        if (at == null) return const NoLanding(Refusal.unmeasured);
        final characters = matched.charactersAt(at);
        if (characters == null) return const NoLanding(Refusal.outsideMatches);
        final file = into.files.single;
        return TextLanding(
          place,
          outline.placeAt(characters),
          into: (
            editionId: into.id,
            sourceKey: file.key,
            revision: file.revision,
          ),
        );
      case TextPosition():
        final characters = place.fits(from)
            ? outline.charactersOf(place)
            : null;
        if (characters == null) return const NoLanding(Refusal.unmeasured);
        final at = matched.millisecondsAt(characters);
        if (at == null) return const NoLanding(Refusal.outsideMatches);
        final landed = _audioPlace(into, at);
        if (landed == null) return const NoLanding(Refusal.unmeasured);
        return AudioLanding(place, landed);
    }
  }

  /// The place of [edition] at [milliseconds] from its start, in the file
  /// that holds it, or null when a file length is unknown. A time past the
  /// end is the end of the last file.
  static AudioPosition? _audioPlace(Edition edition, int milliseconds) {
    final outline = audioOutline(edition);
    final length = outline.length;
    if (length == null) return null;
    final at = milliseconds.clamp(0, length);
    for (final (index, file) in edition.files.indexed) {
      final start = outline.fileStarts[file.key]!;
      final last = index == edition.files.length - 1;
      if (at < start + file.durationMs! || last) {
        return AudioPosition(
          editionId: edition.id,
          sourceKey: file.key,
          revision: file.revision,
          milliseconds: (at - start).clamp(0, file.durationMs!),
        );
      }
    }
    return null;
  }

  /// The key of the kept outline of [text]: its edition, its file and the
  /// file's revision, and the measurement version.
  static String _outlineKey(Edition text) => jsonEncode([
    outlineVersion,
    text.id,
    for (final file in text.files) [file.key, file.revision],
  ]);

  /// The key of the pair of [from] and [into], the audio edition first. It
  /// names every file and revision of both, in the order that they play or
  /// read, so a changed or reordered edition aligns again.
  static String _pairKey(Edition from, Edition into) {
    final (audio, text) = from.kind == EditionKind.audio
        ? (from, into)
        : (into, from);
    return jsonEncode([
      audio.id,
      for (final file in audio.files) [file.key, file.revision],
      _outlineKey(text),
    ]);
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    for (final MapEntry(:key, value: pair) in _done.entries) {
      if (!_pairs.containsKey(key)) {
        throw StateError('Each finished pair is its current work\'s result.');
      }
      if (pair case _Aligned(
        :final outline,
        key: final kept,
        :final alignment,
      )) {
        if (!identical(_outlines[kept], outline)) {
          throw StateError(
            'Each alignment comes from the kept outline of its pair.',
          );
        }
        alignment.checkInvariants();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _downloads?.removeListener(_retryMissing);
    _changes.dispose();
  }
}

/// The finished work of one pair of editions.
sealed class _Pair {
  const _Pair();
}

/// The chapters of the pair match: [alignment] was derived from [outline],
/// the ebook's outline, which is kept under [key].
final class _Aligned extends _Pair {
  const _Aligned(this.outline, this.key, this.alignment);
  final TextOutline outline;
  final String key;
  final MatchedChapters alignment;
}

/// No landing exists in the pair, for [reason].
final class _Refused extends _Pair {
  const _Refused(this.reason);
  final Refusal reason;
}

/// The alignment of the outlines of [pair], for a worker isolate.
EditionAlignment _alignPair((AudioOutline, TextOutline) pair) =>
    alignEditions(pair.$1, pair.$2);

/// The change signal of [Crossings.changes].
class _Changes extends ChangeNotifier {
  void notify() => notifyListeners();
}
