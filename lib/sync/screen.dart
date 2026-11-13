import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/glass.dart' show confirmAction;
import '../catalog/shelf.dart';
import '../foundation/listenable_selector.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart' show dayAndTime, listenedWhen, timeOfDay;
import '../playback/store.dart' show KeptRecords;
import 'choice.dart';
import 'coordinator.dart';
import 'record_address.dart';
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
        child: RecordSyncView(
          status: sync.statusNotifier,
          lastSync: sync.lastSyncNotifier,
          conflicts: sync.conflictsNotifier,
          kept: sync.records.keptNotifier,
          unreadable: sync.unreadableNotifier,
          library: library,
          onSync: () => unawaited(sync.syncNow()),
          onResolve: (record, identity, bookmarkTitles) => unawaited(
            sync.resolve(record, identity, bookmarkTitles: bookmarkTitles),
          ),
          onDiscard: () => unawaited(_discard(context)),
        ),
      ),
    ),
  );

  /// Asks the user to confirm Discard, then deletes the kept copies of
  /// damaged records. A failure says so, and the copies that remain are
  /// still offered.
  Future<void> _discard(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Discard damaged records?',
      message: 'Bookfin deletes its copy of the damaged records. Records that were recovered stay. Records that Bookfin could not read are lost.',
      action: 'Discard',
    );
    if (!confirmed) return;
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

/// The state of personal-record sync, and the conflicts to choose from:
/// a one-line status strip with a round Sync button, the problems as
/// banners under it, and the waiting choices, one open and the rest as
/// collapsed rows.
///
/// Each part follows only its own signals. It reports [onSync] for Sync
/// now, Retry and Check again, [onResolve] for a Keep, and [onDiscard] for
/// Discard of the kept copies of damaged records.
class RecordSyncView extends StatelessWidget {
  const RecordSyncView({
    super.key,
    required this.status,
    required this.lastSync,
    required this.conflicts,
    required this.kept,
    required this.unreadable,
    required this.library,
    required this.onSync,
    required this.onResolve,
    required this.onDiscard,
  });
  final ValueListenable<RecordSyncStatus> status;
  final ValueListenable<RecordSyncOutcome?> lastSync;
  final ValueListenable<RecordConflicts> conflicts;
  final ValueListenable<KeptRecords> kept;
  final ValueListenable<int> unreadable;
  final ValueListenable<CatalogLibrary> library;
  final VoidCallback onSync;
  final ResolveChoice onResolve;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
    children: [
      SyncStatusStrip(
        status: status,
        lastSync: lastSync,
        conflicts: conflicts,
        onSync: onSync,
      ),
      ValueListenableBuilder(
        valueListenable: lastSync,
        builder: (context, outcome, _) => switch (outcome?.failure) {
          null => const SizedBox.shrink(),
          final failure => _failureBanner(failure),
        },
      ),
      ValueListenableBuilder(
        valueListenable: status,
        builder: (context, status, _) => switch (status.message) {
          null => const SizedBox.shrink(),
          final message => SyncBanner(
            icon: Icons.info_outline_rounded,
            title: 'The choice was not saved',
            text: message,
          ),
        },
      ),
      ValueListenableBuilder(
        valueListenable: unreadable,
        builder: (context, count, _) => count == 0
            ? const SizedBox.shrink()
            : SyncBanner(
                quiet: true,
                icon: Icons.description_outlined,
                title: count == 1
                    ? '1 record this version cannot read'
                    : '$count records this version cannot read',
                text: 'Kept on this phone for a later version. Other records still sync.',
              ),
      ),
      ValueListenableBuilder(
        valueListenable: kept,
        builder: (context, kept, _) => kept.kept
            ? SyncBanner(
                icon: Icons.description_outlined,
                title: 'Damaged records kept aside',
                text: [
                  'Some records on this phone could not be read. Bookfin kept a copy and tries it again at each launch.',
                  if (kept.recovered == 1) '1 record came back.',
                  if (kept.recovered > 1)
                    '${kept.recovered} records came back.',
                ].join(' '),
                action: 'Discard the copy…',
                onAction: onDiscard,
              )
            : kept.recovered > 0
            ? SyncBanner(
                quiet: true,
                icon: Icons.check_rounded,
                title: kept.recovered == 1
                    ? '1 damaged record was recovered'
                    : '${kept.recovered} damaged records were recovered',
              )
            : const SizedBox.shrink(),
      ),
      ListenableSelector(
        listenable: lastSync,
        select: () => lastSync.value?.replaced ?? 0,
        builder: (context, replaced, _) => replaced == 0
            ? const SizedBox.shrink()
            : SyncBanner(
                quiet: true,
                icon: Icons.check_rounded,
                title: replaced == 1
                    ? '1 record restored from Jellyfin'
                    : '$replaced records restored from Jellyfin',
                text: replaced == 1
                    ? 'Its copy on this phone was damaged. Bookfin kept the damaged copy too.'
                    : 'Their copies on this phone were damaged. Bookfin kept the damaged copies too.',
              ),
      ),
      ListenableSelector(
        listenable: Listenable.merge([conflicts, lastSync]),
        select: () => (
          waiting: conflicts.value.isNotEmpty,
          synced:
              lastSync.value != null &&
              (lastSync.value!.failure == null ||
                  lastSync.value!.failure ==
                      RecordSyncFailure.remoteUnreadable),
        ),
        builder: (context, page, _) =>
            page.waiting ? const SizedBox.shrink() : _Calm(synced: page.synced),
      ),
      _Choices(
        conflicts: conflicts,
        library: library,
        status: status,
        onResolve: onResolve,
      ),
    ],
  );

  Widget _failureBanner(RecordSyncFailure failure) => switch (failure) {
    RecordSyncFailure.remoteUnreadable => const SizedBox.shrink(),
    RecordSyncFailure.uploadRejected => SyncBanner(
      icon: Icons.sync_problem_rounded,
      title: 'Some records could not be uploaded',
      text: 'Jellyfin did not accept some saved records. They stay on this phone while other records keep arriving.',
      action: 'Retry',
      onAction: onSync,
    ),
    RecordSyncFailure.invalidResponse => SyncBanner(
      icon: Icons.sync_problem_rounded,
      title: 'The sync reply could not be read',
      text: 'Saved records stay on this phone. Retry after checking the Bookfin Storage plugin.',
      action: 'Retry',
      onAction: onSync,
    ),
    RecordSyncFailure.unreachable => SyncBanner(
      icon: Icons.cloud_off_rounded,
      title: 'Jellyfin cannot be reached',
      text: 'Every change stays on this phone and syncs when the connection returns.',
      action: 'Retry',
      onAction: onSync,
    ),
    RecordSyncFailure.pluginMissing => SyncBanner(
      icon: Icons.power_off_outlined,
      title: 'Bookfin Storage plugin missing',
      text: 'Your Jellyfin server has no Bookfin Storage plugin, or its version does not match this app. Reading and listening still work.',
      action: 'Check again',
      onAction: onSync,
    ),
    RecordSyncFailure.unreadable => const SyncBanner(
      icon: Icons.report_outlined,
      title: 'Personal records could not be read',
      text: 'Existing records were kept. Restart Bookfin before syncing again.',
    ),
    RecordSyncFailure.refreshFailed => const SyncBanner(
      icon: Icons.sync_problem_rounded,
      title: 'Synced records could not be shown',
      text: 'The sync finished. Bookfin shows the new records after the next sync.',
    ),
    RecordSyncFailure.other => SyncBanner(
      icon: Icons.sync_problem_rounded,
      title: 'Sync did not finish',
      text: 'Every change stays on this phone. Retry after checking device storage and your sign-in.',
      action: 'Retry',
      onAction: onSync,
    ),
  };
}

/// When a sync ended: its time of day today, else its day and time.
String _when(BuildContext context, DateTime at) =>
    listenedWhen(at, DateTime.now()) == 'Today'
    ? timeOfDay(context, at)
    : dayAndTime(context, at);

/// One line that says how sync stands, with a round button that syncs now.
/// A sync that the user started shows Syncing and turns the button off. A
/// background sync shows only its outcome.
class SyncStatusStrip extends StatelessWidget {
  const SyncStatusStrip({
    super.key,
    required this.status,
    required this.lastSync,
    required this.conflicts,
    required this.onSync,
  });
  final ValueListenable<RecordSyncStatus> status;
  final ValueListenable<RecordSyncOutcome?> lastSync;
  final ValueListenable<RecordConflicts> conflicts;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: Listenable.merge([status, lastSync, conflicts]),
    select: () => (
      busy: status.value.busy,
      outcome: lastSync.value,
      waiting: conflicts.value.length,
    ),
    builder: (context, line, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final outcome = line.outcome;
      final synced = outcome?.synced;
      final failure = outcome?.failure;
      final (title, detail, button) = line.busy
          ? (
              'Syncing…',
              synced == null
                  ? 'Sending this phone’s changes'
                  : 'Last synced ${_when(context, synced)}',
              'Sync now',
            )
          : switch (failure) {
              RecordSyncFailure.pluginMissing => (
                'Sync is off',
                'Records stay on this phone',
                'Check again',
              ),
              RecordSyncFailure.uploadRejected ||
              RecordSyncFailure.invalidResponse ||
              RecordSyncFailure.unreachable ||
              RecordSyncFailure.unreadable ||
              RecordSyncFailure.other => (
                'Not syncing',
                [
                  if (synced != null) 'Last synced ${_when(context, synced)}',
                  '${synced == null ? 'Tried' : 'tried'} ${_when(context, outcome!.at)}',
                ].join(' · '),
                'Retry',
              ),
              null ||
              RecordSyncFailure.refreshFailed ||
              RecordSyncFailure.remoteUnreadable when line.waiting > 0 => (
                line.waiting == 1
                    ? '1 choice waits'
                    : '${line.waiting} choices wait',
                synced == null
                    ? 'Not synced yet'
                    : 'Synced ${_when(context, synced)}',
                'Sync now',
              ),
              null ||
              RecordSyncFailure.refreshFailed ||
              RecordSyncFailure.remoteUnreadable when synced != null => (
                'Synced',
                '${_when(context, synced)} · Jellyfin',
                'Sync now',
              ),
              null ||
              RecordSyncFailure.refreshFailed ||
              RecordSyncFailure.remoteUnreadable => (
                'Not synced yet',
                'Records stay on this phone',
                'Sync now',
              ),
            };
      final warn =
          !line.busy &&
          ((failure != null && failure != RecordSyncFailure.remoteUnreadable) ||
              line.waiting > 0);
      return Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.fromLTRB(18, 5, 5, 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 10,
              child: line.busy
                  ? CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.primary,
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: warn || synced == null ? null : scheme.primary,
                        border: warn
                            ? Border.all(color: scheme.tertiary, width: 2.5)
                            : synced == null
                            ? Border.all(color: scheme.outline, width: 2.5)
                            : null,
                      ),
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: button,
              onPressed: line.busy ? null : onSync,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerLowest,
                foregroundColor: scheme.primary,
                disabledBackgroundColor: scheme.surfaceContainerLowest
                    .withValues(alpha: 0.55),
                fixedSize: const Size(44, 44),
                minimumSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.sync_rounded),
            ),
          ],
        ),
      );
    },
  );
}

/// A problem or a fact about personal records, under the status strip. A
/// problem is copper, and a fact that needs nothing from the user is
/// [quiet]. An [action] reports through [onAction].
class SyncBanner extends StatelessWidget {
  const SyncBanner({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
    this.onAction,
    this.quiet = false,
  });
  final IconData icon;
  final String title;
  final String? text;
  final String? action;
  final VoidCallback? onAction;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = quiet ? scheme.primary : scheme.tertiary;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: EdgeInsets.fromLTRB(14, 14, 14, action == null ? 14 : 2),
      decoration: BoxDecoration(
        color: quiet ? scheme.surfaceContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: scheme.onSurface,
                  ),
                ),
                if (text case final text?)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                if (action case final action?)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 44),
                      textStyle: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(action),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the page says while no choice waits: that nothing waits after a
/// sync that [synced], and where sync keeps the records.
class _Calm extends StatelessWidget {
  const _Calm({required this.synced});
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        if (synced) ...[
          const SizedBox(height: 48),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(Icons.check_rounded, size: 32, color: scheme.primary),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing to choose',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              'Saved places, bookmarks, and history on this phone match your Jellyfin server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 48),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sync uses the Bookfin Storage plugin on Jellyfin. Reading and listening work without it.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The waiting choices: one open card with its choice, and the others as
/// collapsed rows. A tap on a row opens it and collapses the open one.
class _Choices extends StatefulWidget {
  const _Choices({
    required this.conflicts,
    required this.library,
    required this.status,
    required this.onResolve,
  });
  final ValueListenable<RecordConflicts> conflicts;
  final ValueListenable<CatalogLibrary> library;
  final ValueListenable<RecordSyncStatus> status;
  final ResolveChoice onResolve;

  @override
  State<_Choices> createState() => _ChoicesState();
}

class _ChoicesState extends State<_Choices> {
  /// The record whose choice is open, or null for the first one.
  RecordAddress? _open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.conflicts,
      widget.library,
      widget.status,
    ]),
    builder: (context, _) {
      final conflicts = widget.conflicts.value;
      if (conflicts.isEmpty) return const SizedBox.shrink();
      final books = widget.library.value.books;
      final enabled = !widget.status.value.busy;
      final now = DateTime.now();
      final labels = {
        for (final MapEntry(key: record, value: versions) in conflicts.entries)
          record: labelConflict(
            record,
            versions,
            books: books,
            now: now,
            clock: (at) => timeOfDay(context, at),
          ),
      };
      final open = conflicts.containsKey(_open) ? _open! : conflicts.keys.first;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
            child: Text(
              labels.values.every((labels) => labels.places)
                  ? 'Choose a saved place'
                  : 'Choose a saved version',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final MapEntry(key: record, value: labels) in labels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: record == open
                  ? _ConflictCard(
                      outlined: conflicts.length > 1,
                      header: _ConflictHeading(labels: labels),
                      child: ConflictChoice(
                        record: record,
                        labels: labels,
                        enabled: enabled,
                        onResolve: widget.onResolve,
                      ),
                    )
                  : _ConflictCard(
                      onTap: () => setState(() => _open = record),
                      header: _ConflictHeading(labels: labels, closed: true),
                    ),
            ),
        ],
      );
    },
  );
}

/// A card of the waiting choices: its [header], and the open choice below
/// it, or a row that reports [onTap] when collapsed.
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.header,
    this.child,
    this.onTap,
    this.outlined = false,
  });
  final Widget header;
  final Widget? child;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: outlined
          ? BorderSide(color: scheme.primary, width: 2)
          : BorderSide(color: scheme.outlineVariant),
    );
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: child == null
              ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
              : const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, ?child],
          ),
        ),
      ),
    );
  }
}

/// The book of a choice: its cover, its title, and the kind of record. A
/// [closed] row ends in an arrow that opens it.
class _ConflictHeading extends StatelessWidget {
  const _ConflictHeading({required this.labels, this.closed = false});
  final ConflictLabels labels;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = labels.book;
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: book == null
              ? BookCover(title: labels.title, showText: false)
              : BookCover.book(book, showText: false),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels.title,
                style: TextStyle(
                  fontFamily: 'Source Serif 4',
                  fontFamilyFallback: const ['Noto Serif'],
                  fontSize: closed ? 16.5 : 19,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(labels.kind, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (closed)
          Icon(
            Icons.expand_more_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}
