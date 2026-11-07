import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/book_cover.dart';
import '../catalog/library_view.dart' show BookRow, ProgressLine;
import '../catalog/model.dart';
import '../foundation/theme.dart';
import 'downloads.dart';

class DownloadControls extends StatelessWidget {
  const DownloadControls({
    super.key,
    required this.downloads,
    required this.edition,
  });
  final Downloads? downloads;
  final Edition edition;

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
            child: LinearProgressIndicator(
              value: state.totalBytes != null && state.totalBytes! > 0
                  ? (state.bytes / state.totalBytes!).clamp(0, 1)
                  : null,
            ),
          ),
        if (state.message != null)
          Text(
            state.message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (owner?.supported != true)
          const Text('Local downloads are available in the Android app.'),
        if (owner?.supported == true)
          Wrap(
            spacing: 8,
            children: [
              if (!active && state.phase != DownloadPhase.downloaded)
                OutlinedButton(
                  onPressed: () => _act(context, () => owner!.request(edition)),
                  child: Text(
                    state.phase == DownloadPhase.failed || state.bytes > 0
                        ? 'Retry'
                        : 'Download',
                  ),
                ),
              if (active)
                TextButton(
                  onPressed: () => _act(context, () => owner!.cancel(edition)),
                  child: const Text('Cancel'),
                ),
              if (state.bytes > 0 ||
                  state.unavailableBytes > 0 ||
                  state.completeFiles > 0 ||
                  state.phase == DownloadPhase.failed)
                TextButton(
                  onPressed: () async {
                    if (await confirmRemoveDownload(context) &&
                        context.mounted) {
                      _act(context, () => owner!.remove(edition));
                    }
                  },
                  child: const Text('Remove'),
                ),
            ],
          ),
      ],
    );
  }

  void _act(BuildContext context, Future<void> Function() operation) {
    unawaited(() async {
      try {
        await operation();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The download could not be changed. Check your account and available storage.',
              ),
            ),
          );
        }
      }
    }());
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
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
            downloads: owner,
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
            downloads: owner,
            book: entry.book,
            edition: entry.edition,
            state: entry.state,
            onOpen: onOpen,
            compact: compact,
          ),
        ],
        const SizedBox(height: 24),
        // A stable key keeps one storage scan while rows above it change.
        _RetainedStorageView(
          key: const ValueKey('retained storage'),
          downloads: owner,
        ),
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
    return Card(
      child: Padding(
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
                  final allow = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Allow mobile data?'),
                      content: const Text(
                        'Allow media transfers for this account session. Your carrier may charge for mobile data. Signing out or restarting ends this permission.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Wait for Wi-Fi'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Allow this session'),
                        ),
                      ],
                    ),
                  );
                  if (allow == true && context.mounted) {
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.downloads,
    required this.book,
    required this.edition,
    required this.state,
    required this.onOpen,
    required this.compact,
  });
  final Downloads downloads;
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
    final active =
        state.phase == DownloadPhase.downloading ||
        state.phase == DownloadPhase.waiting;
    final removable =
        state.bytes > 0 ||
        state.unavailableBytes > 0 ||
        state.completeFiles > 0 ||
        state.phase == DownloadPhase.failed;
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
          ? ProgressLine(
              value: total != null && total > 0 ? state.bytes / total : 0,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!active &&
              state.phase != DownloadPhase.downloaded &&
              (state.phase == DownloadPhase.failed || state.bytes > 0))
            IconButton(
              tooltip: 'Retry download',
              onPressed: () =>
                  _change(context, () => downloads.request(edition)),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (active)
            IconButton(
              tooltip: 'Cancel download',
              onPressed: () =>
                  _change(context, () => downloads.cancel(edition)),
              icon: const Icon(Icons.close_rounded),
            ),
          if (!active && removable)
            IconButton(
              tooltip: 'Remove download',
              onPressed: () async {
                if (await confirmRemoveDownload(context) && context.mounted) {
                  _change(context, () => downloads.remove(edition));
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
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
Future<bool> confirmRemoveDownload(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: const Text(
          'Remove this edition’s local files and unfinished transfers. Your Jellyfin files will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep download'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove download'),
          ),
        ],
      ),
    ) ??
    false;

void _change(BuildContext context, Future<void> Function() operation) {
  unawaited(() async {
    try {
      await operation();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The download could not be changed. Check your account and available storage.',
            ),
          ),
        );
      }
    }
  }());
}

class _RetainedStorageView extends StatefulWidget {
  const _RetainedStorageView({super.key, required this.downloads});
  final Downloads downloads;

  @override
  State<_RetainedStorageView> createState() => _RetainedStorageViewState();
}

class _RetainedStorageViewState extends State<_RetainedStorageView> {
  late Future<List<RetainedDownload>> _inventory;

  @override
  void initState() {
    super.initState();
    widget.downloads.addListener(_reload);
    _inventory = _readStorage();
  }

  @override
  void didUpdateWidget(_RetainedStorageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloads != widget.downloads) {
      oldWidget.downloads.removeListener(_reload);
      widget.downloads.addListener(_reload);
      _inventory = _readStorage();
    }
  }

  void _reload() {
    setState(() {
      _inventory = _readStorage();
    });
  }

  Future<List<RetainedDownload>> _readStorage() {
    final inventory = widget.downloads.retainedStorage();
    inventory.ignore();
    return inventory;
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_reload);
    super.dispose();
  }

  Future<void> _remove(RetainedDownload download) async {
    final owner = widget.downloads;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove retained files?'),
        content: Text(
          'Remove ${download.bytes} bytes stored for source ${download.sourceKey}? '
          'These files are outside your current catalog. '
          'Your Jellyfin files will not change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep files'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove files'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await owner.removeRetained(download);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'These files could not be removed. Check your account and refresh storage.',
            ),
          ),
        );
      }
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text('Retained storage', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Local files outside this account’s current catalog. '
        'They do not count as downloaded editions. '
        'Files stay here until you explicitly remove them.',
      ),
      TextButton(onPressed: _reload, child: const Text('Refresh storage')),
      FutureBuilder<List<RetainedDownload>>(
        future: _inventory,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text('Reading retained storage…');
          }
          if (snapshot.hasError) {
            return const Text(
              'Cannot read retained storage. No files were removed. Refresh storage to retry.',
            );
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) return const Text('No retained files.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: BookfinPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.removable
                              ? 'Source ${entry.sourceKey}'
                              : 'Unidentified stored files',
                        ),
                        if (entry.removable) Text('Revision ${entry.revision}'),
                        Text('${entry.bytes} bytes'),
                        if (entry.removable)
                          TextButton(
                            onPressed: () => _remove(entry),
                            child: const Text('Remove retained files'),
                          )
                        else
                          const Text(
                            'The saved identity is unreadable or does not match. '
                            'These files cannot be safely removed here.',
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
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
