import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/glass.dart';
import '../catalog/model.dart';
import '../foundation/listenable_selector.dart';
import '../foundation/time.dart' show timeOfDay;
import 'choice.dart';
import 'coordinator.dart';
import 'labels.dart';

/// Gives every page below it the record sync of the app, so that the book
/// page and the player can show a choice that waits for their book. The app
/// places it above its navigator, so pushed pages and sheets see it too.
class RecordSyncScope extends InheritedWidget {
  const RecordSyncScope({super.key, required this.sync, required super.child});

  /// The app's record sync, or null in an app without one.
  final RecordSync? sync;

  static RecordSync? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecordSyncScope>()?.sync;

  @override
  bool updateShouldNotify(RecordSyncScope oldWidget) => oldWidget.sync != sync;
}

/// Opens the choice between the saved versions of [record] of [book] in a
/// glass sheet tinted by the book's cover. When the user keeps a version,
/// [sync] resolves it. A choice that was not saved says why.
///
/// The book page and the player are the controllers that call it.
Future<void> chooseConflict(
  BuildContext context,
  RecordSync sync, {
  required Book book,
  required String record,
}) async {
  final versions = sync.conflicts[record];
  if (versions == null) return;
  final labels = labelConflict(
    record,
    versions,
    books: [book],
    now: DateTime.now(),
    clock: (at) => timeOfDay(context, at),
  );
  final chosen = await showGlassSheet<(String, Map<String, String>)>(
    context,
    book: book,
    title: labels.places ? 'Choose a saved place' : 'Choose a saved version',
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${labels.title} · ${labels.kind}',
            style: Theme.of(sheet).textTheme.bodySmall,
          ),
          ValueListenableBuilder(
            valueListenable: sync.statusNotifier,
            builder: (sheet, status, _) => ConflictChoice(
              record: record,
              labels: labels,
              enabled: !status.busy,
              onResolve: (_, identity, bookmarkTitles) =>
                  Navigator.pop(sheet, (identity, bookmarkTitles)),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(sheet),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  final (identity, bookmarkTitles) = chosen;
  await sync.resolve(record, identity, bookmarkTitles: bookmarkTitles);
  final message = sync.message;
  if (context.mounted && message != null) showGlassMessage(context, message);
}

/// The alert of the first choice that waits for [book] in [conflicts], or
/// nothing while none waits. It follows only the choices of [book], and
/// reports the record of the choice through [onChoose].
class BookConflictAlert extends StatelessWidget {
  const BookConflictAlert({
    super.key,
    required this.conflicts,
    required this.book,
    required this.onChoose,
    this.compact = false,
    this.padding = EdgeInsets.zero,
  });
  final ValueListenable<RecordConflicts> conflicts;
  final Book book;
  final ValueChanged<String> onChoose;

  /// A pill, as in the player, instead of a notice.
  final bool compact;

  /// The space around the alert while it shows.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: conflicts,
    // The versions of one record stay the same list until they change.
    select: () => switch (bookConflicts(conflicts.value, book).entries) {
      final entries when entries.isEmpty => null,
      final entries => (entries.first.key, entries.first.value),
    },
    builder: (context, waiting, _) {
      if (waiting == null) return const SizedBox.shrink();
      final (record, versions) = waiting;
      return Padding(
        padding: padding,
        child: ConflictAlert(
          labels: labelConflict(
            record,
            versions,
            books: [book],
            now: DateTime.now(),
            clock: (at) => timeOfDay(context, at),
          ),
          compact: compact,
          onChoose: () => onChoose(record),
        ),
      );
    },
  );
}

/// Says on glass that a choice between saved versions waits, with a Choose
/// button that reports [onChoose]. As a notice it names each version and
/// its place. As a [compact] pill it says only what differs.
class ConflictAlert extends StatelessWidget {
  const ConflictAlert({
    super.key,
    required this.labels,
    required this.onChoose,
    this.compact = false,
  });
  final ConflictLabels labels;
  final VoidCallback onChoose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = labels.kind.split(' ').last;
    final icon = Icon(
      Icons.call_split_rounded,
      size: compact ? 16 : 20,
      color: scheme.primary,
    );
    if (compact) {
      return Center(
        child: CoverGlass(
          radius: 99,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 7),
                Text(
                  switch (kind) {
                    'bookmark' => 'Bookmarks differ',
                    'entry' => 'History differs',
                    _ => 'Saved places differ',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onChoose,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.primary,
                    backgroundColor: scheme.surfaceContainerLowest.withValues(
                      alpha: 0.7,
                    ),
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Choose'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final devices = labels.choices.length == 2
        ? 'Two devices'
        : '${labels.choices.length} devices';
    return CoverGlass(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    switch (kind) {
                      'bookmark' => '$devices changed a bookmark',
                      'entry' => '$devices changed the history',
                      _ => '$devices saved different places',
                    },
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    [
                      for (final choice in labels.choices)
                        choice.time == null
                            ? choice.source
                            : '${choice.source} at ${choice.time}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onChoose,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Choose'),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], usually the Settings tab icon, with a copper badge that counts
/// the choices that wait in [conflicts]. It follows only their count.
class ChoicesBadge extends StatelessWidget {
  const ChoicesBadge({super.key, required this.conflicts, required this.child});
  final ValueListenable<RecordConflicts> conflicts;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: conflicts,
    select: () => conflicts.value.length,
    builder: (context, waiting, child) {
      final scheme = Theme.of(context).colorScheme;
      return Badge(
        isLabelVisible: waiting > 0,
        backgroundColor: scheme.tertiary,
        textColor: scheme.onTertiary,
        label: Text('$waiting'),
        child: child,
      );
    },
    child: child,
  );
}
