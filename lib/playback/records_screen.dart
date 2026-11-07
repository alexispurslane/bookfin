import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../catalog/model.dart';
import '../foundation/theme.dart';
import 'playback.dart';
import '../catalog/glass.dart';

class PersonalRecordsView extends StatelessWidget {
  const PersonalRecordsView({super.key, required this.playback});
  final Playback playback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final bookmarks = playback.bookmarks;
      final history = playback.history;
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + floatingBarInset(context),
        ),
        itemCount: 4 + bookmarks.length + history.length,
        itemBuilder: (context, index) {
          if (index == 0) return RecordSaveStatus(playback: playback);
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                bookmarks.isEmpty ? 'No bookmarks yet' : 'Bookmarks',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            );
          }
          if (index < bookmarks.length + 2) {
            final bookmark = bookmarks[index - 2];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BookfinPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.title ?? 'Bookmark',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${bookmark.bookTitle} · ${bookmark.editionLabel}'),
                    Text(_place(playback, bookmark.position)),
                    if (bookmark.note != null) Text(bookmark.note!),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () =>
                              unawaited(playback.restoreBookmark(bookmark.id)),
                          child: const Text('Restore bookmark'),
                        ),
                        IconButton(
                          tooltip: 'Edit bookmark',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => editAudioBookmark(
                            context,
                            playback,
                            bookmark: bookmark,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete bookmark',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, bookmark),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
          if (index == bookmarks.length + 2) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Your listening history',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            );
          }
          if (index == bookmarks.length + 3) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                history.isEmpty ? 'No listening actions yet.' : 'Restore a previous place or the result of an action. Earlier actions stay in your history.',
              ),
            );
          }
          final event = history[index - bookmarks.length - 4];
          final date = MaterialLocalizations.of(context);
          final local = event.at.toLocal();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BookfinPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _actionName(event.kind),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${event.bookTitle} · ${event.editionLabel}'),
                  Text(
                    '${date.formatMediumDate(local)} · ${date.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
                  ),
                  if (event.changesPosition) ...[
                    Text('From ${_place(playback, event.before)}'),
                    Text('To ${_place(playback, event.after)}'),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () =>
                              unawaited(playback.restoreHistory(event.id)),
                          child: const Text('Restore previous place'),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            playback.restoreHistory(event.id, previous: false),
                          ),
                          child: const Text('Restore result'),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(_place(playback, event.after)),
                    TextButton(
                      onPressed: () => unawaited(
                        playback.restoreHistory(event.id, previous: false),
                      ),
                      child: const Text('Restore place'),
                    ),
                  ],
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete history action'),
                    onPressed: () => _deleteRecord(
                      context,
                      'Delete history action?',
                      'Remove this action from your history on synced devices. Bookmarks and other actions stay.',
                      () => playback.deleteHistory(event.id),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Future<void> _delete(BuildContext context, AudioBookmark bookmark) async {
    await _deleteRecord(
      context,
      'Delete bookmark?',
      bookmark.title ?? _place(playback, bookmark.position),
      () => playback.deleteBookmark(bookmark.id),
    );
  }

  Future<void> _deleteRecord(
    BuildContext context,
    String title,
    String explanation,
    Future<void> Function() remove,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => GlassDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await remove();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class RecordSaveStatus extends StatelessWidget {
  const RecordSaveStatus({super.key, required this.playback});
  final Playback playback;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (playback.message != null)
        Text(
          playback.message!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (playback.saveFailed) ...[
        const Text(
          'Personal records are not saved to this device. Keep Bookfin open and retry.',
        ),
        TextButton(
          onPressed: () => unawaited(playback.flush()),
          child: const Text('Retry saving'),
        ),
      ],
    ],
  );
}

Future<void> editAudioBookmark(
  BuildContext context,
  Playback playback, {
  AudioBookmark? bookmark,
}) async {
  final position = bookmark?.position ?? playback.position;
  if (position == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _BookmarkEditor(
      playback: playback,
      bookmark: bookmark,
      position: position,
    ),
  );
}

class _BookmarkEditor extends StatefulWidget {
  const _BookmarkEditor({
    required this.playback,
    required this.position,
    this.bookmark,
  });
  final Playback playback;
  final AudioPosition position;
  final AudioBookmark? bookmark;
  @override
  State<_BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends State<_BookmarkEditor> {
  late final _title = TextEditingController(text: widget.bookmark?.title);
  late final _note = TextEditingController(text: widget.bookmark?.note);
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    if (widget.bookmark == null) {
      await widget.playback.addBookmark(
        position: widget.position,
        title: _title.text,
        note: _note.text,
      );
    } else {
      await widget.playback.editBookmark(
        widget.bookmark!.id,
        title: _title.text,
        note: _note.text,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => GlassDialog(
    title: Text(widget.bookmark == null ? 'Add bookmark' : 'Edit bookmark'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_place(widget.playback, widget.position)),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title (optional)'),
          ),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save bookmark'),
      ),
    ],
  );
}

String _place(Playback playback, AudioPosition position) =>
    '${playback.sourceName(position)} · ${audioTime(position.milliseconds)} in file';

String audioTime(int milliseconds) {
  final seconds = max(0, milliseconds) ~/ 1000;
  final minutes = seconds ~/ 60;
  return '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}:' : ''}${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _actionName(ListeningAction kind) => switch (kind) {
  ListeningAction.seek => 'Seek',
  ListeningAction.jump => 'Short jump',
  ListeningAction.chapter => 'Chapter jump',
  ListeningAction.undo => 'Undo',
  ListeningAction.historyRestore => 'History restore',
  ListeningAction.bookmarkRestore => 'Bookmark restore',
  ListeningAction.pause => 'Paused',
  ListeningAction.resume => 'Resumed',
  ListeningAction.interruption => 'Interrupted',
  ListeningAction.stop => 'Stopped',
  ListeningAction.completion => 'Completed',
};
