import 'dart:convert';

import 'package:bookfin/catalog/model.dart';

// Made-up books and saved versions to choose between, as
// RecordJournal.conflicts holds them.

const hour = 3600000;
const minute = 60000;

const frostFile = SourceFile(
  itemId: 'frost',
  displayName: 'First Frost.m4b',
  mediaSourceId: 'm1',
  revision: 'r1',
  durationMs: 10 * hour,
  container: 'm4b',
  sizeBytes: 42,
  chapters: [
    AudioChapter('Chapter 4 · The Grafting', 2 * hour),
    AudioChapter('Chapter 6 · Frostbite', 4 * hour),
  ],
);
const frostAudio = Edition(
  id: 'frost-audio',
  kind: EditionKind.audio,
  label: 'Tom Avery',
  narrator: 'Tom Avery',
  files: [frostFile],
  memberIds: ['frost:m1'],
);
const firstFrost = Book(
  id: 'frost',
  title: 'First Frost',
  author: 'Mara Ellison',
  editions: [frostAudio],
);

const northFile = SourceFile(
  itemId: 'north',
  displayName: 'Northbound.m4b',
  mediaSourceId: 'm1',
  revision: 'r1',
  durationMs: 6 * hour,
  container: 'm4b',
  sizeBytes: 42,
);
const northAudio = Edition(
  id: 'north-audio',
  kind: EditionKind.audio,
  label: 'Ana Ruiz',
  files: [northFile],
  memberIds: ['north:m1'],
);
const northbound = Book(
  id: 'north',
  title: 'Northbound',
  author: 'Teodor Halse',
  editions: [northAudio],
);

const books = [firstFrost, northbound];

/// The saved place of [file] in [edition].
String placeRecord(Edition edition, SourceFile file) => jsonEncode([
  'audio',
  'resumes',
  jsonEncode([edition.id, file.key, file.revision]),
]);

/// A listening place saved by [device] at [milliseconds] into [file].
Map<String, dynamic> place(
  String device,
  int milliseconds, {
  Edition edition = frostAudio,
  SourceFile file = frostFile,
}) => {
  'version': 1,
  'account': 'alice',
  'replica': device.replaceAll(' ', '-'),
  'sequence': 1,
  'context': <String, int>{},
  'record': placeRecord(edition, file),
  'value': {
    'edition': edition.id,
    'source': file.key,
    'revision': file.revision,
    'milliseconds': milliseconds,
  },
  'preserve': <String>[],
  'device': device,
};

/// First Frost: Pixel 8 at 4:12:47 and Pixel Tablet at 2:33:16.
final frostConflict = {
  placeRecord(frostAudio, frostFile): [
    place('Pixel 8', 4 * hour + 12 * minute + 47000),
    place('Pixel Tablet', 2 * hour + 33 * minute + 16000),
  ],
};

final markRecord = jsonEncode(['audio', 'bookmarks', 'ferry']);

/// Northbound: a bookmark that Pixel 8 renamed and Pixel Tablet deleted.
final northConflict = {
  markRecord: [
    {
      ...place('Pixel 8', 0, edition: northAudio, file: northFile),
      'record': markRecord,
      'value': {
        'id': 'ferry',
        'position': place(
          'Pixel 8',
          hour + 4 * minute + 22000,
          edition: northAudio,
          file: northFile,
        )['value'],
        'createdAt': '2026-11-07T21:12:00Z',
        'title': 'Ferry at dawn',
        'bookTitle': 'Northbound',
        'editionLabel': 'Ana Ruiz',
      },
    },
    {
      ...place('Pixel Tablet', 0, edition: northAudio, file: northFile),
      'record': markRecord,
      'value': null,
    },
  ],
};
