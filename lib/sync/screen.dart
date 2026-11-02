import 'dart:convert';

import 'package:flutter/material.dart';

import 'coordinator.dart';
import 'journal.dart';

class RecordSyncView extends StatelessWidget {
  const RecordSyncView({super.key, required this.sync});
  final RecordSync sync;

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
                Text(
                  '${(jsonDecode(entry.key) as List).first == 'audio' ? 'Listening' : 'Reading'} · choose a saved version',
                ),
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
    if (value['milliseconds'] is int) {
      final duration = Duration(milliseconds: value['milliseconds'] as int);
      return '${value['edition']} · ${value['source']} · ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    if (value['anchor'] is String) {
      return '${value['edition']} · ${value['source']} · ${value['anchor']}';
    }
    return '${value['title'] ?? value['kind'] ?? 'Saved record'} · ${value['note'] ?? value['createdAt'] ?? value['at'] ?? ''}';
  }
}
