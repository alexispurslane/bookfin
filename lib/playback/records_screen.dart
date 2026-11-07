import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/model.dart';
import '../foundation/time.dart';
import 'playback.dart';
import '../catalog/glass.dart';

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
          Text(
            'At ${audioTime(widget.playback.editionTime(widget.position) ?? widget.position.milliseconds)}',
          ),
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
