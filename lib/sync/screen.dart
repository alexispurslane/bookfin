import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/model.dart';
import '../playback/records_screen.dart' show audioTime;
import 'coordinator.dart';
import 'journal.dart';

class RecordSyncView extends StatelessWidget {
  const RecordSyncView({super.key, required this.sync, this.books = const []});
  final RecordSync sync;
  final List<Book> books;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Personal-record sync',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          sync.message ?? 'Sync bookmarks, listening history, and saved places through the Bookfin Storage Jellyfin plugin. Local reading and listening work without the plugin.',
        ),
        TextButton.icon(
          onPressed: sync.busy ? null : sync.synchronize,
          icon: const Icon(Icons.sync),
          label: Text(sync.busy ? 'Syncing personal records…' : 'Sync now'),
        ),
        for (final entry in sync.conflicts.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_heading(entry.key, entry.value)),
                for (final action in entry.value)
                  TextButton(
                    onPressed: sync.busy
                        ? null
                        : () => sync.resolve(
                            entry.key,
                            RecordJournal.identity(action),
                          ),
                    child: Text(
                      _describe(action['value'] as Map<String, dynamic>?),
                    ),
                  ),
                if ((jsonDecode(entry.key) as List)[1] == 'resumes')
                  const Text(
                    'Choosing keeps both places as bookmarks. Your current page or audio does not jump.',
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  String _describe(Map<String, dynamic>? value) {
    if (value == null) return 'Keep deletion';
    final position = _position(value);
    final parts = <String>[_bookName(value)];
    final edition = _edition(position);
    final savedLabel = value['editionLabel'] as String?;
    parts.add(
      edition?.label ?? savedLabel ?? 'Edition not in the current library',
    );
    final source = edition?.files
        .where(
          (file) =>
              file.key == position['source'] &&
              file.revision == position['revision'],
        )
        .firstOrNull;
    parts.add(source?.displayName ?? 'Source unavailable or changed');
    if (position['milliseconds'] is int) {
      final milliseconds = position['milliseconds'] as int;
      final fraction = milliseconds % 1000;
      parts.add(
        '${audioTime(milliseconds)}${fraction == 0 ? '' : '.${fraction.toString().padLeft(3, '0')}'}',
      );
    } else if (position['anchor'] is String) {
      Map? address;
      try {
        final decoded = jsonDecode(position['anchor'] as String);
        if (decoded is Map) address = decoded;
      } on FormatException {
        address = null;
      }
      if (address?['page'] is int) parts.add('Source page ${address!['page']}');
      final quote = address?['quote'];
      parts.add(
        quote is String && quote.trim().isNotEmpty
            ? '“$quote”'
            : 'Saved reading place (preview unavailable)',
      );
    }
    for (final name in ['title', 'note']) {
      if (value[name] is String && (value[name] as String).isNotEmpty) {
        parts.add(value[name] as String);
      }
    }
    return parts.join(' · ');
  }

  Map<String, dynamic> _position(Map<String, dynamic> value) =>
      (value['position'] ?? value['after'] ?? value) as Map<String, dynamic>;

  Edition? _edition(Map<String, dynamic> position) => books
      .expand((book) => book.editions)
      .where((edition) => edition.id == position['edition'])
      .firstOrNull;

  String _bookName(Map<String, dynamic> value) {
    final position = _position(value);
    final book = books
        .where(
          (book) =>
              book.editions.any((edition) => edition.id == position['edition']),
        )
        .firstOrNull;
    return book?.title ??
        (value['bookTitle'] is String
            ? '${value['bookTitle']} (not in the current library)'
            : 'Book not in the current library');
  }

  String _heading(String record, List<Map<String, dynamic>> actions) {
    final address = jsonDecode(record) as List;
    final value = actions
        .map((action) => action['value'])
        .whereType<Map<String, dynamic>>()
        .firstOrNull;
    final kind = switch (address[1]) {
      'bookmarks' => 'bookmark',
      'history' => 'history entry',
      _ => 'saved place',
    };
    return '${value == null ? 'Book unavailable' : _bookName(value)} · ${address.first == 'audio' ? 'Listening' : 'Reading'} $kind · choose a saved version';
  }
}
