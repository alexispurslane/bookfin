import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/model.dart';
import '../foundation/hop.dart';
import '../playback/audio_outline.dart';
import '../playback/records.dart' show editionSources;
import '../reader/document.dart';
import '../reader/text_outline.dart';
import 'alignment.dart';

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

/// How Bookfin found a landing. Design A finds every landing by chapters:
/// an estimate, which the words of the landing call "about".
enum MatchedBy { chapters }

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
/// isolate.
///
/// Invariants, which [checkInvariants] checks:
/// - Each kept outline is kept under the key of the edition revision that
///   it was measured from.
/// - Each kept alignment was derived from the kept outline of its pair.
/// - Each alignment of matched chapters keeps its own invariants: anchors
///   increase strictly, and every span reads in the rate band.
class Crossings {
  /// [measure] measures the text outline of a downloaded ebook edition, or
  /// gives null when this phone has no download of it. [downloads] notifies
  /// when downloads change, so that an ebook that was not downloaded is
  /// tried again. [hop] runs the alignment in another isolate.
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

  /// The text outlines measured or read so far, by outline key.
  final _outlines = <String, TextOutline>{};

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
    _guard(place, from, into);
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
    _guard(place, from, into);
    final key = _pairKey(from, into);
    if (_done[key] case final pair?) return _land(place, from, into, pair);
    unawaited(_pair(from, into));
    return null;
  }

  void _guard(Place place, Edition from, Edition into) {
    if (place.editionId != from.id || from.kind == into.kind) {
      throw ArgumentError(
        'Give a place of [from] and an edition of the other medium.',
      );
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
      final outline = await _outline(text);
      final alignment = outline == null
          ? null
          : await _hop(_alignPair, (audioOutline(audio), outline));
      final pair = (
        outline: outline,
        alignment: alignment,
        key: _outlineKey(text),
      );
      // A change of downloads during the work asks for it again, and that
      // later work's result counts.
      if (!_disposed && identical(_pairs[key], work)) {
        _done[key] = pair;
        _changes.notify();
      }
      return pair;
    }();
    return _pairs[key] = work;
  }

  /// The text outline of [text]: kept in memory, kept in the store, or
  /// measured from its download and then kept. Null when none is kept and
  /// this phone has no download of it.
  Future<TextOutline?> _outline(Edition text) async {
    final key = _outlineKey(text);
    if (_outlines[key] case final outline?) return outline;
    final kept = await _readKept(key);
    if (kept != null) return _outlines[key] = kept;
    final TextOutline? measured;
    try {
      measured = await _measure(text);
    } on Exception {
      return null;
    }
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
  Future<TextOutline?> _readKept(String key) async {
    try {
      final value = await _store.read(key);
      if (value == null) return null;
      // NOTE: Engine rule 1. A kept outline is 10 to 20 KB of JSON, see
      // [_outline].
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['key'] != key) return null;
      return TextOutline.fromJson(json['outline'] as Map<String, dynamic>);
    } on Exception {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Forgets the pairs that had no outline, so that the next request tries
  /// their ebooks again, now that downloads changed.
  void _retryMissing() {
    final missing = [
      for (final MapEntry(:key, :value) in _done.entries)
        if (value.outline == null) key,
    ];
    if (missing.isEmpty) return;
    for (final key in missing) {
      _done.remove(key);
      _pairs.remove(key);
    }
    _changes.notify();
  }

  /// Where [place] of [from] lands in [into], by [pair].
  Crossing _land(Place place, Edition from, Edition into, _Pair pair) {
    final (outline, alignment) = (pair.outline, pair.alignment);
    if (outline == null || alignment == null) {
      return const NoLanding(Refusal.noOutline);
    }
    if (alignment case UnmatchedChapters(:final reason)) {
      return NoLanding(reason);
    }
    final matched = alignment as MatchedChapters;
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
  /// names every file and revision, so a changed edition aligns again.
  static String _pairKey(Edition from, Edition into) {
    final (audio, text) = from.kind == EditionKind.audio
        ? (from, into)
        : (into, from);
    return jsonEncode([audio.id, editionSources(audio), _outlineKey(text)]);
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    for (final pair in _done.values) {
      final outline = pair.outline;
      if (outline != null && !identical(_outlines[pair.key], outline)) {
        throw StateError(
          'Each alignment comes from the kept outline of its pair.',
        );
      }
      if (pair.alignment case final MatchedChapters matched) {
        matched.checkInvariants();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _downloads?.removeListener(_retryMissing);
    _changes.dispose();
  }
}

/// The finished work of one pair: the ebook's outline and its key, and the
/// alignment, or null for both when this phone has no outline.
typedef _Pair = ({
  TextOutline? outline,
  EditionAlignment? alignment,
  String key,
});

/// The alignment of the outlines of [pair], for a worker isolate.
EditionAlignment _alignPair((AudioOutline, TextOutline) pair) =>
    alignEditions(pair.$1, pair.$2);

/// The change signal of [Crossings.changes].
class _Changes extends ChangeNotifier {
  void notify() => notifyListeners();
}
