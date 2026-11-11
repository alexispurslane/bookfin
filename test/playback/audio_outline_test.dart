// The audio outline of an audio edition: its chapters, each with its start
// from the edition's start, and the edition's length. The player's chapter
// list, the sync choice's track and the cross-edition matching all read it.
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/audio_outline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recording of two files. The first file is 60 s long and has two
/// chapters. The second is 40 s long and has no chapter at its start.
const _first = SourceFile(
  itemId: 'one',
  displayName: 'Disc one',
  mediaSourceId: 'm1',
  revision: 'r1',
  durationMs: 60000,
  container: 'mp3',
  sizeBytes: 1,
  chapters: [
    AudioChapter('Loomings', 0),
    AudioChapter('The Carpet-Bag', 30000),
  ],
);
const _second = SourceFile(
  itemId: 'two',
  displayName: 'Disc two',
  mediaSourceId: 'm2',
  revision: 'r2',
  durationMs: 40000,
  container: 'mp3',
  sizeBytes: 1,
  chapters: [AudioChapter('The Spouter-Inn', 10000)],
);

Edition _recording(List<SourceFile> files) => Edition(
  id: 'recording',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: files,
  memberIds: [for (final file in files) file.key],
);

void main() {
  test('an audio outline lists the chapters of every file at their times '
      'from the edition\'s start', () {
    final outline = audioOutline(_recording(const [_first, _second]));

    expect(
      [for (final chapter in outline.chapters) chapter.name],
      ['Loomings', 'The Carpet-Bag', 'Disc two', 'The Spouter-Inn'],
    );
    expect(
      [for (final chapter in outline.chapters) chapter.editionMilliseconds],
      [0, 30000, 60000, 70000],
    );
    expect(outline.length, 100000);
  });

  test('a file of unknown length leaves the edition\'s length and every '
      'later chapter time unknown', () {
    const unmeasured = SourceFile(
      itemId: 'one',
      displayName: 'Disc one',
      mediaSourceId: 'm1',
      revision: 'r1',
      durationMs: null,
      container: 'mp3',
      sizeBytes: 1,
      chapters: [AudioChapter('Loomings', 0)],
    );

    final outline = audioOutline(_recording(const [unmeasured, _second]));

    expect(
      [for (final chapter in outline.chapters) chapter.editionMilliseconds],
      [0, null, null],
    );
    expect(outline.length, isNull);
  });

  test('a place reads as its time from the edition\'s start', () {
    final edition = _recording(const [_first, _second]);
    const place = AudioPosition(
      editionId: 'recording',
      sourceKey: 'two:m2',
      revision: 'r2',
      milliseconds: 15000,
    );

    expect(audioOutline(edition).editionTime(place), 75000);
  });
}
