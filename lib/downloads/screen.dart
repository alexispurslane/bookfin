import 'dart:async';

import 'package:flutter/material.dart';

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
            '${state.bytes}${state.totalBytes == null ? '' : ' / ${state.totalBytes}'} bytes · ${state.completeFiles} / ${state.totalFiles} files',
            style: Theme.of(context).textTheme.bodySmall,
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
                  state.completeFiles > 0 ||
                  state.phase == DownloadPhase.failed)
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
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
                    );
                    if (confirmed == true && context.mounted) {
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

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    required this.downloads,
    required this.books,
  });
  final Downloads? downloads;
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final owner = downloads;
    final editions = [
      for (final book in books)
        for (final edition in book.editions)
          if ((owner?.status(edition).phase ?? DownloadPhase.none) !=
                  DownloadPhase.none ||
              (owner?.status(edition).bytes ?? 0) > 0)
            (book, edition),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text('Downloads', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        if (owner?.supported != true)
          const Text('Local downloads are available in the Android app.')
        else ...[
          Text(switch (owner!.policy.network) {
            MediaNetwork.wifi => 'Wi-Fi · Media transfers allowed',
            MediaNetwork.mobile =>
              owner.policy.mobileAllowed
                  ? 'Mobile data allowed for this session'
                  : 'Mobile data · Waiting for Wi-Fi',
            MediaNetwork.disconnected => 'Offline · Waiting for Wi-Fi',
            MediaNetwork.unknown => 'Network unknown · Waiting for Wi-Fi',
          }),
          if (owner.policy.network == MediaNetwork.mobile &&
              !owner.policy.mobileAllowed)
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
                  owner.policy.allowMobileForSession();
                }
              },
              child: const Text('Allow mobile data this session'),
            ),
          if (owner.policy.mobileAllowed)
            TextButton(
              onPressed: owner.policy.resetSession,
              child: const Text('Use Wi-Fi only'),
            ),
        ],
        const SizedBox(height: 16),
        if (editions.isEmpty) const Text('No downloads yet.'),
        for (final (book, edition) in editions)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BookfinPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${edition.kind == EditionKind.audio ? 'Audio' : 'Ebook'} · ${edition.label}',
                  ),
                  const SizedBox(height: 8),
                  DownloadControls(downloads: owner, edition: edition),
                ],
              ),
            ),
          ),
      ],
    );
  }
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
