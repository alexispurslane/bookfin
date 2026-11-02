import 'dart:math';

import '../catalog/model.dart';

enum ListeningAction {
  seek,
  jump,
  chapter,
  undo,
  historyRestore,
  bookmarkRestore,
  pause,
  resume,
  interruption,
  stop,
  completion,
}

String recordId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

Map<String, dynamic> encodePosition(AudioPosition position) => {
  'edition': position.editionId,
  'source': position.sourceKey,
  'revision': position.revision,
  'milliseconds': position.milliseconds,
};

AudioPosition decodePosition(dynamic value) {
  if (value is! Map ||
      value['edition'] is! String ||
      (value['edition'] as String).isEmpty ||
      value['source'] is! String ||
      (value['source'] as String).isEmpty ||
      value['revision'] is! String ||
      (value['revision'] as String).isEmpty ||
      value['milliseconds'] is! int ||
      (value['milliseconds'] as int) < 0) {
    throw const FormatException('Invalid saved audio position');
  }
  return AudioPosition(
    editionId: value['edition'] as String,
    sourceKey: value['source'] as String,
    revision: value['revision'] as String,
    milliseconds: value['milliseconds'] as int,
  );
}

class ListeningEvent {
  const ListeningEvent({
    required this.id,
    required this.at,
    required this.kind,
    required this.before,
    required this.after,
    required this.bookTitle,
    required this.editionLabel,
  });
  final String id;
  final DateTime at;
  final ListeningAction kind;
  final AudioPosition before;
  final AudioPosition after;
  final String bookTitle;
  final String editionLabel;

  bool get changesPosition => switch (kind) {
    ListeningAction.seek ||
    ListeningAction.jump ||
    ListeningAction.chapter ||
    ListeningAction.undo ||
    ListeningAction.historyRestore ||
    ListeningAction.bookmarkRestore => true,
    _ => false,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'before': encodePosition(before),
    'after': encodePosition(after),
    'bookTitle': bookTitle,
    'editionLabel': editionLabel,
  };

  factory ListeningEvent.fromJson(Map<String, dynamic> value) {
    final before = decodePosition(value['before']);
    final after = decodePosition(value['after']);
    final kind = ListeningAction.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        kind == null) {
      throw const FormatException('Invalid listening action');
    }
    return ListeningEvent(
      id: value['id'] as String,
      at: DateTime.parse(value['at'] as String),
      kind: kind,
      before: before,
      after: after,
      bookTitle: value['bookTitle'] as String,
      editionLabel: value['editionLabel'] as String,
    );
  }
}

class AudioBookmark {
  const AudioBookmark({
    required this.id,
    required this.position,
    required this.createdAt,
    required this.bookTitle,
    required this.editionLabel,
    this.title,
    this.note,
  });
  final String id;
  final AudioPosition position;
  final DateTime createdAt;
  final String bookTitle;
  final String editionLabel;
  final String? title;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': encodePosition(position),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'bookTitle': bookTitle,
    'editionLabel': editionLabel,
    'title': title,
    'note': note,
  };

  factory AudioBookmark.fromJson(Map<String, dynamic> value) {
    if (value['id'] is! String || (value['id'] as String).isEmpty) {
      throw const FormatException('Invalid bookmark');
    }
    return AudioBookmark(
      id: value['id'] as String,
      position: decodePosition(value['position']),
      createdAt: DateTime.parse(value['createdAt'] as String),
      bookTitle: value['bookTitle'] as String,
      editionLabel: value['editionLabel'] as String,
      title: value['title'] as String?,
      note: value['note'] as String?,
    );
  }
}
