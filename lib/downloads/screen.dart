import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/library_view.dart' show BookRow;
import '../catalog/model.dart';
import '../foundation/theme.dart';
import 'downloads.dart';
import '../catalog/glass.dart';

/// An edition's download state in words, with a button for each of its
/// download actions. A tap reports the action through [onAction]; the page
/// performs it.
class DownloadControls extends StatelessWidget {
  const DownloadControls({
    super.key,
    required this.downloads,
    required this.edition,
    required this.onAction,
  });
  final Downloads? downloads;
  final Edition edition;
  final ValueChanged<DownloadAction> onAction;

  @override
  Widget build(BuildContext context) {
    final owner = downloads;
    final state = owner?.status(edition) ?? const EditionDownload();
    final active =
        state.phase == DownloadPhase.downloading ||
        state.phase == DownloadPhase.waiting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.label),
        if (state.bytes > 0 || active || state.phase == DownloadPhase.failed)
          Text(
            '${formatBytes(state.bytes)}${state.totalBytes == null ? '' : ' of ${formatBytes(state.totalBytes!)}'} · ${state.completeFiles} of ${state.totalFiles} files',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (state.unavailableBytes > 0)
          Text(
            '${formatBytes(state.unavailableBytes)} saved but unavailable for playback',
          ),
        if (state.phase == DownloadPhase.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ProgressLine(value: _share(state)),
          ),
        if (state.message != null) StatusMessage(state.message!),
        if (owner?.supported != true)
          const Text('Local downloads are available in the Android app.'),
        if (owner?.supported == true)
          Wrap(
            spacing: 8,
            children: [
              for (final action in state.actions)
                switch (action) {
                  DownloadAction.request ||
                  DownloadAction.retry => OutlinedButton(
                    onPressed: () => onAction(action),
                    child: Text(
                      action == DownloadAction.retry ? 'Retry' : 'Download',
                    ),
                  ),
                  DownloadAction.cancel || DownloadAction.remove => TextButton(
                    onPressed: () => onAction(action),
                    child: Text(
                      action == DownloadAction.cancel ? 'Cancel' : 'Remove',
                    ),
                  ),
                },
            ],
          ),
      ],
    );
  }
}

/// The book page's round download button. A tap reports the first of the
/// edition's download actions through [onAction]. Its icon shows a finished
/// or waiting download, and a ring shows a running transfer.
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.downloads,
    required this.edition,
    required this.onAction,
  });
  final Downloads downloads;
  final Edition edition;
  final ValueChanged<DownloadAction> onAction;

  @override
  Widget build(BuildContext context) {
    final state = downloads.status(edition);
    final action = state.actions.first;
    final icon = switch (state.phase) {
      DownloadPhase.downloaded => Icons.check_rounded,
      DownloadPhase.waiting => Icons.wifi_off_rounded,
      _ => _icon(action),
    };
    final tooltip = switch (state.phase) {
      DownloadPhase.downloaded ||
      DownloadPhase.waiting ||
      DownloadPhase.failed => '${state.label}. ${_tooltip(action)}',
      _ => _tooltip(action),
    };
    final downloading = state.phase == DownloadPhase.downloading;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (downloading)
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: _share(state),
            ),
          ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(52, 52),
          ),
          tooltip: tooltip,
          onPressed: () => onAction(action),
          icon: Icon(icon),
        ),
      ],
    );
  }
}

/// Every edition with local files or a transfer: a summary of the space they
/// use and of the network, then one library row per edition. Tapping a row
/// opens its book. The controls at the end of a row only change the download.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.books,
    this.onOpen,
    this.compact = false,
  });
  final Downloads? downloads;
  final List<Book> books;
  final void Function(BuildContext context, Book book)? onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final owner = downloads;
    if (owner?.supported != true) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Local downloads are available in the Android app.'),
        ),
      );
    }
    final entries = [
      for (final book in books)
        for (final edition in book.editions)
          if (owner!.status(edition) case final state
              when state.phase != DownloadPhase.none ||
                  state.bytes > 0 ||
                  state.unavailableBytes > 0)
            (book: book, edition: edition, state: state),
    ];
    final saved = entries
        .where((entry) => entry.state.phase == DownloadPhase.downloaded)
        .toList();
    final pending = entries
        .where((entry) => entry.state.phase != DownloadPhase.downloaded)
        .toList();
    final theme = Theme.of(context);
    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 2),
      child: SectionLabel(label),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 24 + floatingBarInset(context)),
      children: [
        _Summary(downloads: owner!, saved: saved),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                const Text('No downloads yet.'),
                Text(
                  'Download a book from its details page.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (pending.isNotEmpty) section('IN PROGRESS'),
        for (final (index, entry) in pending.indexed) ...[
          if (index > 0) const Divider(),
          _DownloadRow(
            onAction: (action) =>
                changeDownload(context, owner, entry.edition, action),
            book: entry.book,
            edition: entry.edition,
            state: entry.state,
            onOpen: onOpen,
            compact: compact,
          ),
        ],
        if (saved.isNotEmpty) section('ON THIS PHONE'),
        for (final (index, entry) in saved.indexed) ...[
          if (index > 0) const Divider(),
          _DownloadRow(
            onAction: (action) =>
                changeDownload(context, owner, entry.edition, action),
            book: entry.book,
            edition: entry.edition,
            state: entry.state,
            onOpen: onOpen,
            compact: compact,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.downloads, required this.saved});
  final Downloads downloads;
  final List<({Book book, Edition edition, EditionDownload state})> saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = downloads.policy;
    final audio = saved
        .where((entry) => entry.edition.kind == EditionKind.audio)
        .length;
    final text = saved.length - audio;
    final bytes = saved.fold<int>(
      0,
      (total, entry) => total + entry.state.bytes,
    );
    final audioBytes = saved
        .where((entry) => entry.edition.kind == EditionKind.audio)
        .fold<int>(0, (total, entry) => total + entry.state.bytes);
    final (icon, network) = switch (policy.network) {
      MediaNetwork.wifi => (
        Icons.wifi_rounded,
        'Connected to Wi-Fi · downloads run now',
      ),
      MediaNetwork.mobile when policy.mobileAllowed => (
        Icons.signal_cellular_alt_rounded,
        'On mobile data · allowed for this session',
      ),
      MediaNetwork.mobile => (
        Icons.signal_cellular_alt_rounded,
        'On mobile data · downloads wait for Wi-Fi',
      ),
      MediaNetwork.disconnected => (
        Icons.cloud_off_rounded,
        'Offline · downloaded books still play',
      ),
      MediaNetwork.unknown => (
        Icons.help_outline_rounded,
        'Network unknown · downloads wait for Wi-Fi',
      ),
    };
    return BookfinPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatBytes(bytes),
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            [
              'saved on this phone',
              if (audio > 0)
                '$audio ${audio == 1 ? 'audiobook' : 'audiobooks'}',
              if (text > 0) '$text ${text == 1 ? 'ebook' : 'ebooks'}',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (audio > 0 && text > 0)
            Text(
              'Audiobooks ${formatBytes(audioBytes)} · ebooks ${formatBytes(bytes - audioBytes)}',
              style: theme.textTheme.bodySmall,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(),
          ),
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(network)),
            ],
          ),
          if (policy.network == MediaNetwork.mobile && !policy.mobileAllowed)
            TextButton(
              onPressed: () async {
                final allow = await confirmAction(
                  context,
                  title: 'Allow mobile data?',
                  message: 'Allow media transfers for this account session. Your carrier may charge for mobile data. Signing out or restarting ends this permission.',
                  action: 'Allow this session',
                  cancel: 'Wait for Wi-Fi',
                );
                if (allow && context.mounted) {
                  policy.allowMobileForSession();
                }
              },
              child: const Text('Allow mobile data this session'),
            ),
          if (policy.mobileAllowed)
            TextButton(
              onPressed: policy.resetSession,
              child: const Text('Use Wi-Fi only'),
            ),
          // A stable key keeps one storage scan while the card rebuilds.
          _LeftoverSummary(
            key: const ValueKey('leftover files'),
            downloads: downloads,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.onAction,
    required this.book,
    required this.edition,
    required this.state,
    required this.onOpen,
    required this.compact,
  });
  final ValueChanged<DownloadAction> onAction;
  final Book book;
  final Edition edition;
  final EditionDownload state;
  final void Function(BuildContext context, Book book)? onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final kind = edition.kind == EditionKind.audio
        ? 'Audiobook'
        : edition.files.firstOrNull?.container.toUpperCase().nonEmpty ??
              'Ebook';
    final total = state.totalBytes;
    final detail = [
      switch (state.phase) {
        DownloadPhase.downloaded => '$kind · ${formatBytes(state.bytes)}',
        DownloadPhase.downloading =>
          '$kind · ${formatBytes(state.bytes)}${total == null ? '' : ' of ${formatBytes(total)}'} · ${state.completeFiles} of ${state.totalFiles} files',
        DownloadPhase.waiting => '$kind · Waiting for Wi-Fi',
        DownloadPhase.failed => '$kind · Download failed',
        DownloadPhase.partial =>
          '$kind · Partial · ${formatBytes(state.bytes)} saved',
        DownloadPhase.none => '$kind · Not downloaded',
      },
      if (state.unavailableBytes > 0)
        '${formatBytes(state.unavailableBytes)} saved but unavailable for playback',
      ?state.message,
    ].join(' · ');
    return BookRow(
      cover: BookCover.book(
        book,
        downloaded: state.phase == DownloadPhase.downloaded,
        showText: false,
      ),
      title: book.title,
      author: book.author,
      detail: detail,
      compact: compact,
      onTap: () => onOpen?.call(context, book),
      below: state.phase == DownloadPhase.downloading
          ? ProgressLine(value: _share(state))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in state.actions)
            IconButton(
              tooltip: _tooltip(action),
              onPressed: () => onAction(action),
              icon: Icon(_icon(action)),
            ),
        ],
      ),
    );
  }
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}

/// Asks before removing an edition's local files.
Future<bool> confirmRemoveDownload(BuildContext context) => confirmAction(
  context,
  title: 'Remove download?',
  message: 'Remove this edition’s local files and unfinished transfers. Your Jellyfin files will not change.',
  action: 'Remove download',
  cancel: 'Keep download',
);

/// How much of a transfer is saved, from 0 to 1, or null when its size is
/// unknown.
double? _share(EditionDownload state) => switch (state.totalBytes) {
  final total? when total > 0 => (state.bytes / total).clamp(0, 1),
  _ => null,
};

String _tooltip(DownloadAction action) => switch (action) {
  DownloadAction.request => 'Download',
  DownloadAction.retry => 'Retry download',
  DownloadAction.cancel => 'Cancel download',
  DownloadAction.remove => 'Remove download',
};

IconData _icon(DownloadAction action) => switch (action) {
  DownloadAction.request => Icons.download_rounded,
  DownloadAction.retry => Icons.refresh_rounded,
  DownloadAction.cancel => Icons.close_rounded,
  DownloadAction.remove => Icons.delete_outline_rounded,
};

/// Asks [downloads] for [action] on [edition], for a page or tab that acts on
/// a reported download action. Removal asks first. A failure shows a message
/// instead of an error.
void changeDownload(
  BuildContext context,
  Downloads downloads,
  Edition edition,
  DownloadAction action,
) => unawaited(() async {
  if (action == DownloadAction.remove &&
      !(await confirmRemoveDownload(context) && context.mounted)) {
    return;
  }
  try {
    await switch (action) {
      DownloadAction.request ||
      DownloadAction.retry => downloads.request(edition),
      DownloadAction.cancel => downloads.cancel(edition),
      DownloadAction.remove => downloads.remove(edition),
    };
  } catch (_) {
    if (context.mounted) {
      showGlassMessage(
        context,
        'The download could not be changed. Check your account and available storage.',
      );
    }
  }
}());

/// Reads the leftover files of the bound account, and reads them again when
/// [Downloads.phases] notifies, so byte progress never starts a new read.
/// [builder] gets the latest read and a way to repeat it.
class _LeftoverInventory extends StatefulWidget {
  const _LeftoverInventory({required this.downloads, required this.builder});
  final Downloads downloads;
  final Widget Function(
    BuildContext context,
    AsyncSnapshot<List<RetainedDownload>> inventory,
    VoidCallback reload,
  )
  builder;

  @override
  State<_LeftoverInventory> createState() => _LeftoverInventoryState();
}

class _LeftoverInventoryState extends State<_LeftoverInventory> {
  late Future<List<RetainedDownload>> _inventory;

  @override
  void initState() {
    super.initState();
    widget.downloads.phases.addListener(_reload);
    _inventory = _read();
  }

  @override
  void didUpdateWidget(_LeftoverInventory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloads != widget.downloads) {
      oldWidget.downloads.phases.removeListener(_reload);
      widget.downloads.phases.addListener(_reload);
      _inventory = _read();
    }
  }

  void _reload() {
    setState(() {
      _inventory = _read();
    });
  }

  Future<List<RetainedDownload>> _read() {
    final inventory = widget.downloads.retainedStorage();
    inventory.ignore();
    return inventory;
  }

  @override
  void dispose() {
    widget.downloads.phases.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RetainedDownload>>(
    future: _inventory,
    builder: (context, snapshot) => widget.builder(context, snapshot, _reload),
  );
}

/// The summary card's line about leftover files. It shows nothing while there
/// are none.
class _LeftoverSummary extends StatelessWidget {
  const _LeftoverSummary({super.key, required this.downloads});
  final Downloads downloads;

  @override
  Widget build(BuildContext context) => _LeftoverInventory(
    downloads: downloads,
    builder: (context, inventory, reload) {
      final theme = Theme.of(context);
      final entries = inventory.data ?? const <RetainedDownload>[];
      final failed = inventory.hasError;
      if (inventory.connectionState != ConnectionState.done ||
          !failed && entries.isEmpty) {
        return const SizedBox.shrink();
      }
      final bytes = entries.fold<int>(0, (total, entry) => total + entry.bytes);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.only(top: 8), child: Divider()),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: failed
                ? reload
                : () => unawaited(
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LeftoverFilesPage(downloads: downloads),
                      ),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : Icons.inventory_2_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: failed
                        ? const Text(
                            'Cannot check leftover files. Tap to try again.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Leftover files'),
                              Text(
                                '${formatBytes(bytes)} from books no longer in your library',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                  ),
                  if (!failed)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Files kept on the phone from books that are no longer in the library, for
/// example after a library was deselected. They stay until the user removes
/// them.
class LeftoverFilesPage extends StatelessWidget {
  const LeftoverFilesPage({super.key, required this.downloads});
  final Downloads downloads;

  Future<bool> _confirm(BuildContext context, String title, String body) =>
      confirmAction(
        context,
        title: title,
        message: body,
        action: 'Remove files',
        cancel: 'Keep files',
      );

  Future<void> _remove(
    BuildContext context,
    List<RetainedDownload> entries,
    VoidCallback reload,
  ) async {
    try {
      for (final entry in entries) {
        await downloads.removeRetained(entry);
      }
    } catch (_) {
      if (context.mounted) {
        showGlassMessage(
          context,
          'Some files could not be removed. Check your account and try again.',
        );
      }
    }
    if (context.mounted) reload();
  }

  @override
  Widget build(BuildContext context) => _LeftoverInventory(
    downloads: downloads,
    builder: (context, inventory, reload) {
      final theme = Theme.of(context);
      final entries = inventory.hasError
          ? const <RetainedDownload>[]
          : inventory.data ?? const <RetainedDownload>[];
      final removable = entries.where((entry) => entry.removable).toList();
      final total = removable.fold<int>(0, (sum, entry) => sum + entry.bytes);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Leftover files'),
          actions: [
            IconButton(
              tooltip: 'Check again',
              onPressed: reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (removable.isNotEmpty)
              TextButton(
                onPressed: () async {
                  if (await _confirm(
                        context,
                        'Remove all leftover files?',
                        'Remove ${formatBytes(total)} kept from books that are no longer in your library? Your Jellyfin files will not change.',
                      ) &&
                      context.mounted) {
                    await _remove(context, removable, reload);
                  }
                },
                child: const Text('Remove all'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: BookfinSurface(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
                child: Text(
                  'These files are from books that are no longer in your library, for example after you hide a library. They stay on this phone until you remove them.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (inventory.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (inventory.hasError)
                const Text(
                  'Cannot read leftover files. No files were removed. Check again to retry.',
                )
              else if (entries.isEmpty)
                const Text('No leftover files.')
              else
                SettingsGroup(
                  children: [
                    for (final entry in entries)
                      ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          entry.removable
                              ? 'Source ${entry.sourceKey}'
                              : 'Unidentified files',
                        ),
                        subtitle: Text(formatBytes(entry.bytes)),
                        trailing: entry.removable
                            ? IconButton(
                                tooltip: 'Remove leftover files',
                                onPressed: () async {
                                  if (await _confirm(
                                        context,
                                        'Remove leftover files?',
                                        'Remove ${formatBytes(entry.bytes)} kept from a book that is no longer in your library? Your Jellyfin files will not change.',
                                      ) &&
                                      context.mounted) {
                                    await _remove(context, [entry], reload);
                                  }
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              )
                            : const Tooltip(
                                message: 'These files cannot be identified, so they stay.',
                                child: Icon(Icons.lock_outline_rounded),
                              ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );
}

String bookAvailability(Book book, EditionKind kind, Downloads? downloads) {
  final editions = book.editions.where((edition) => edition.kind == kind);
  final states = editions
      .map((edition) => downloads?.status(edition) ?? const EditionDownload())
      .toList();
  final label = kind == EditionKind.audio ? 'Audio' : 'Ebook';
  for (final phase in [
    DownloadPhase.downloaded,
    DownloadPhase.downloading,
    DownloadPhase.waiting,
    DownloadPhase.failed,
    DownloadPhase.partial,
    DownloadPhase.none,
  ]) {
    if (states.any((state) => state.phase == phase)) {
      return '$label · ${states.firstWhere((state) => state.phase == phase).label}';
    }
  }
  return '$label · Not downloaded';
}

/// For example "412 MB", "2.4 MB", or "830 KB".
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  final megabytes = bytes / (1000 * 1000);
  if (megabytes < 10) return '${megabytes.toStringAsFixed(1)} MB';
  if (megabytes < 1000) return '${megabytes.round()} MB';
  return '${(megabytes / 1000).toStringAsFixed(1)} GB';
}
