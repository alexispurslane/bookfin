import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/shelf.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart' show dayAndTime, timeOfDay;
import '../playback/store.dart' show KeptRecords;
import 'coordinator.dart';
import 'labels.dart';

/// The Personal records page. It runs Sync now and the choice between saved
/// versions on [sync], asks the user to confirm Discard before it deletes
/// the kept copies of damaged records, and names books from [library].
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
              kept: sync.records.keptNotifier,
              library: library,
              onSync: () => unawaited(sync.syncNow()),
              onResolve: (record, identity, bookmarkTitles) => unawaited(
                sync.resolve(record, identity, bookmarkTitles: bookmarkTitles),
              ),
              onDiscard: () => unawaited(_discard(context)),
            ),
          ],
        ),
      ),
    ),
  );

  /// Asks the user to confirm Discard, then deletes the kept copies of
  /// damaged records. A failure says so, and the copies that remain are
  /// still offered.
  Future<void> _discard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard damaged records?'),
        content: const Text(
          'Bookfin deletes its copy of the damaged records. Records that were recovered stay. Records that Bookfin could not read are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await sync.records.discardKept();
    } on Exception {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The damaged copies were not deleted. Retry after checking device storage.',
          ),
        ),
      );
    }
  }
}

/// The state of personal-record sync, and the conflicts to choose from.
/// Each part follows only its own signal. It reports [onSync] for Sync now,
/// [onResolve] with the record address, the identity of the chosen saved
/// version, and the bookmark title of each version as `labelConflict` names
/// it, and [onDiscard] for Discard of the kept copies of damaged records.
class RecordSyncView extends StatelessWidget {
  const RecordSyncView({
    super.key,
    required this.status,
    required this.lastSync,
    required this.conflicts,
    required this.kept,
    required this.library,
    required this.onSync,
    required this.onResolve,
    required this.onDiscard,
  });
  final ValueListenable<RecordSyncStatus> status;
  final ValueListenable<RecordSyncOutcome?> lastSync;
  final ValueListenable<RecordConflicts> conflicts;
  final ValueListenable<KeptRecords> kept;
  final ValueListenable<CatalogLibrary> library;
  final VoidCallback onSync;
  final void Function(
    String record,
    String identity,
    Map<String, String> bookmarkTitles,
  )
  onResolve;
  final VoidCallback onDiscard;

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
                    : [
                        'Last synced · ${dayAndTime(context, outcome.at)}',
                        if (outcome.replaced == 1) '1 damaged record was restored from Jellyfin. Bookfin kept the damaged copy.',
                        if (outcome.replaced > 1)
                          '${outcome.replaced} damaged records were restored from Jellyfin. Bookfin kept the damaged copies.',
                      ].join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
      ValueListenableBuilder(
        valueListenable: kept,
        builder: (context, kept, _) => !kept.kept && kept.recovered == 0
            ? const SizedBox.shrink()
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (kept.recovered == 1)
                          '1 damaged record was recovered.',
                        if (kept.recovered > 1)
                          '${kept.recovered} damaged records were recovered.',
                        if (kept.kept)
                          'Bookfin keeps a copy of the damaged records.',
                      ].join(' '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (kept.kept)
                    TextButton(
                      onPressed: onDiscard,
                      child: const Text('Discard'),
                    ),
                ],
              ),
      ),
      ListenableBuilder(
        listenable: Listenable.merge([conflicts, library, status]),
        builder: (context, _) {
          final books = library.value.books;
          final busy = status.value.busy;
          final now = DateTime.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final MapEntry(key: record, value: versions)
                  in conflicts.value.entries)
                _conflict(
                  record,
                  labelConflict(
                    record,
                    versions,
                    books: books,
                    now: now,
                    clock: (at) => timeOfDay(context, at),
                  ),
                  busy: busy,
                ),
            ],
          );
        },
      ),
    ],
  );

  /// The choice between the saved versions of [record], as [labels] name
  /// them. A choice reports the title of the bookmark of every version, so
  /// that each place that stays a bookmark says where it came from.
  Widget _conflict(
    String record,
    ConflictLabels labels, {
    required bool busy,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labels.heading),
        for (final choice in labels.choices)
          TextButton(
            onPressed: busy
                ? null
                : () => onResolve(record, choice.identity, {
                    for (final choice in labels.choices)
                      choice.identity: choice.bookmarkTitle,
                  }),
            child: Text(choice.text),
          ),
        if ((jsonDecode(record) as List)[1] == 'resumes')
          const Text(
            'Choosing keeps both places as bookmarks. Your current page or audio does not jump.',
          ),
      ],
    ),
  );
}
