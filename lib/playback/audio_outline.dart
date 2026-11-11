import '../catalog/model.dart';

/// The audio outline of an audio edition: its chapters in order, each with
/// its start from the edition's start, and the edition's length. The player,
/// the sync choice's track and the cross-edition matching read the same
/// outline (see docs/plans/cross-edition-places.md).
class AudioOutline {
  const AudioOutline._(this.chapters, this.fileStarts, this.length);

  /// The chapters of every file, in the order of the files. A file without
  /// a chapter at its start begins with a chapter named after the file.
  /// Chapters before a file's start or past its end are left out.
  final List<PlaybackChapter> chapters;

  /// Where each file starts in the edition, by [SourceFile.key], in
  /// milliseconds. A start is null when an earlier file has no known length.
  final Map<String, int?> fileStarts;

  /// The length of the edition in milliseconds, or null when a file has no
  /// known length.
  final int? length;

  /// Where [place] is in the edition, in milliseconds from its start, or
  /// null when its file is not in the edition or starts at an unknown time.
  int? editionTime(AudioPosition place) =>
      switch (fileStarts[place.sourceKey]) {
        final start? => start + place.milliseconds,
        null => null,
      };
}

/// The audio outline of [edition]. An edition never changes, so its outline
/// is found once for each edition object.
AudioOutline audioOutline(Edition edition) => _outlines[edition] ??= () {
  final starts = <String, int?>{};
  final chapters = <PlaybackChapter>[];
  int? offset = 0;
  for (final file in edition.files) {
    starts.putIfAbsent(file.key, () => offset);
    final start = starts[file.key];
    for (final chapter in file.playableChapters) {
      chapters.add(
        PlaybackChapter(
          chapter.name,
          file.key,
          chapter.startMs,
          start == null ? null : start + chapter.startMs,
        ),
      );
    }
    offset = offset == null || file.durationMs == null
        ? null
        : offset + file.durationMs!;
  }
  return AudioOutline._(
    List.unmodifiable(chapters),
    Map.unmodifiable(starts),
    offset,
  );
}();

final _outlines = Expando<AudioOutline>();

/// One chapter of an audio edition.
class PlaybackChapter {
  const PlaybackChapter(
    this.name,
    this.sourceKey,
    this.milliseconds, [
    this.editionMilliseconds,
  ]);
  final String name;
  final String sourceKey;

  /// Where the chapter starts within its source file.
  final int milliseconds;

  /// Where the chapter starts within the whole edition, or null when an
  /// earlier file has no known duration.
  final int? editionMilliseconds;
}
