import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/model.dart' show AudioPosition;
import '../foundation/theme.dart';
import '../foundation/time.dart';
import 'playback.dart';
import '../catalog/glass.dart';

/// The listening message, and an offer to retry when the personal records
/// failed to save. A tap on Retry saving asks [playback] to save again.
class RecordSaveStatus extends StatelessWidget {
  const RecordSaveStatus({super.key, required this.playback});
  final Playback playback;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: playback.statusNotifier,
    builder: (context, status, _) => RecordSaveNotice(
      status: status,
      onRetrySave: () => unawaited(playback.flush()),
    ),
  );
}

/// Shows the message of [status], and offers a retry while the records
/// failed to save.
class RecordSaveNotice extends StatelessWidget {
  const RecordSaveNotice({
    super.key,
    required this.status,
    required this.onRetrySave,
  });
  final PlaybackStatus status;

  /// Reports a tap on Retry saving.
  final VoidCallback onRetrySave;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (status.message case final message?) StatusMessage(message),
      if (status.saveFailed) ...[
        const Text(
          'Personal records are not saved to this device. Keep Bookfin open and retry.',
        ),
        TextButton(onPressed: onRetrySave, child: const Text('Retry saving')),
      ],
    ],
  );
}

/// Asks for a title and a note for the audio bookmark [bookmark], or for a
/// new bookmark at the open place when it is null, then saves them.
Future<void> editAudioBookmark(
  BuildContext context,
  Playback playback, {
  Bookmark<AudioPosition>? bookmark,
}) async {
  final position = bookmark?.position ?? playback.position;
  if (position == null) return;
  final edited = await showBookmarkEditor(
    context,
    heading: bookmark == null ? 'Add bookmark' : 'Edit bookmark',
    title: bookmark?.title,
    note: bookmark?.note,
    place:
        'At ${audioTime(playback.editionTime(position) ?? position.milliseconds)}',
  );
  if (edited == null) return;
  if (bookmark == null) {
    await playback.addBookmark(
      position: position,
      title: edited.title,
      note: edited.note,
    );
  } else {
    await playback.editBookmark(
      bookmark.id,
      title: edited.title,
      note: edited.note,
    );
  }
}

/// Shows a dialog that edits the [title] and [note] of a bookmark under
/// [heading]. [place] says where the bookmark is, such as "At 01:15".
/// Returns the edited title and note when the listener saves, or null when
/// they cancel. The caller saves the bookmark.
Future<({String title, String note})?> showBookmarkEditor(
  BuildContext context, {
  required String heading,
  String? title,
  String? note,
  required String place,
  bool glass = true,
}) => showDialog<({String title, String note})>(
  context: context,
  builder: (context) => _BookmarkEditor(
    heading: heading,
    title: title,
    note: note,
    place: place,
    glass: glass,
  ),
);

class _BookmarkEditor extends StatefulWidget {
  const _BookmarkEditor({
    required this.heading,
    required this.title,
    required this.note,
    required this.place,
    required this.glass,
  });
  final String heading;
  final String? title;
  final String? note;
  final String place;

  /// False for a screen that keeps its own plain look, such as the reader.
  final bool glass;
  @override
  State<_BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends State<_BookmarkEditor> {
  late final _title = TextEditingController(text: widget.title);
  late final _note = TextEditingController(text: widget.note);
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = Text(widget.heading);
    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.place),
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
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (title: _title.text, note: _note.text)),
        child: const Text('Save bookmark'),
      ),
    ];
    return widget.glass
        ? GlassDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
