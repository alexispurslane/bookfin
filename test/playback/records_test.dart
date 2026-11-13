// The record types that listening and reading share.
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:flutter_test/flutter_test.dart';

TextPosition place(String anchor) => TextPosition(
  editionId: 'edition',
  sourceKey: 'source',
  revision: '1',
  anchor: anchor,
);

void main() {
  test('a move with new ends keeps every other field that it saves', () {
    final move = HistoryEvent<TextPosition>(
      id: 'move',
      at: DateTime.utc(2026, 11, 12, 21),
      kind: HistoryAction.seek,
      before: place('a'),
      after: place('b'),
      bookTitle: 'The Decline and Fall',
      editionLabel: 'PDF',
      device: 'Tablet',
      counterpartOf: const AudioPosition(
        editionId: 'audio',
        sourceKey: 'track',
        revision: '1',
        milliseconds: 5000,
      ),
      matchedBy: MatchedBy.speech,
    );
    final renamed = move.withEnds(place('c'), place('d'));
    expect(renamed.toJson(), {
      ...move.toJson(),
      'before': encodePlace(place('c')),
      'after': encodePlace(place('d')),
    });
  });
}
