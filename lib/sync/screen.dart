import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/model.dart';
import '../catalog/shelf.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart' show audioTime, dayAndTime;
import 'coordinator.dart';
import 'journal.dart';

/// The Personal records page. It runs Sync now and the choice between saved
/// versions on [sync], and names books from [library].
class RecordSyncPage extends StatelessWidget {
  const RecordSyncPage({super.key, required this.sync, required this.library});
  final RecordSync sync;
  final ValueListenable<CatalogLibrary> library;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personal records')),
    body: BookfinSurface(
      child: Material(
        type: MaterialType.transparency,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            RecordSyncView(
              status: sync.statusNotifier,
              lastSync: sync.lastSyncNotifier,
              conflicts: sync.conflictsNotifier,
              library: library,
              onSync: () => unawaited(sync.syncNow()),
              onResolve: (record, identity) =>
                  unawaited(sync.resolve(record, identity)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The state of personal-record sync, and the conflicts to choose from.
/// Each part follows only its own signal. It reports [onSync] for Sync now
/// and [onResolve] with the record address and the identity of the chosen
/// saved version.
class RecordSyncView extends StatelessWidget {
  const RecordSyncView({
    super.key,
    required this.status,
    required this.lastSync,
    required this.conflicts,
    required this.library,
    required this.onSync,
    required this.onResolve,
  });
  final ValueListenable<RecordSyncStatus> status;
  final ValueListenable<RecordSyncOutcome?> lastSync;
  final ValueListenable<RecordConflicts> conflicts;
  final ValueListenable<CatalogLibrary> library;
  final VoidCallback onSync;
  final void Function(String record, String identity) onResolve;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Personal-record sync',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      ValueListenableBuilder(
        valueListenable: status,
        builder: (context, status, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.message ?? 'Sync bookmarks, listening history, and saved places through the Bookfin Storage Jellyfin plugin. Local reading and listening work without the plugin.',
            ),
            TextButton.icon(
              onPressed: status.busy ? null : onSync,
              icon: const Icon(Icons.sync),
              label: Text(
                status.busy ? 'Syncing personal records…' : 'Sync now',
              ),
            ),
          ],
        ),
      ),
      ValueListenableBuilder(
        valueListenable: lastSync,
        builder: (context, outcome, _) => outcome == null
            ? const SizedBox.shrink()
            : Text(
                outcome.failed
                    ? 'Last sync failed. Tap Sync now to retry.'
                    : 'Last synced · ${dayAndTime(context, outcome.at)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
      ListenableBuilder(
        listenable: Listenable.merge([conflicts, library, status]),
        builder: (context, _) {
          final books = library.value.books;
          final busy = status.value.busy;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in conflicts.value.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_heading(books, entry.key, entry.value)),
                      for (final action in entry.value)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => onResolve(
                                  entry.key,
                                  RecordJournal.identity(action),
                                ),
                          child: Text(
                            _describe(
                              books,
                              action['value'] as Map<String, dynamic>?,
                            ),
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
          );
        },
      ),
    ],
  );

  String _describe(List<Book> books, Map<String, dynamic>? value) {
    if (value == null) return 'Keep deletion';
    final position = _position(value);
    final parts = <String>[_bookName(books, value)];
    final edition = _edition(books, position);
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

  Edition? _edition(List<Book> books, Map<String, dynamic> position) => books
      .expand((book) => book.editions)
      .where((edition) => edition.id == position['edition'])
      .firstOrNull;

  String _bookName(List<Book> books, Map<String, dynamic> value) {
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

  String _heading(
    List<Book> books,
    String record,
    List<Map<String, dynamic>> actions,
  ) {
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
    return '${value == null ? 'Book unavailable' : _bookName(books, value)} · ${address.first == 'audio' ? 'Listening' : 'Reading'} $kind · choose a saved version';
  }
}
