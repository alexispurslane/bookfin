import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/model.dart' show AudioPosition, TextPosition, Book, Edition;
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../catalog/glass.dart';
import '../reader/session.dart';
import 'playback.dart';

/// Playback notices for [book] or [edition], plus account-wide record notices
/// and a retry for failed listening or reading saves. Without a book or edition,
/// shows only record notices. Retry saving asks both owners to save again.
class RecordSaveStatus extends StatelessWidget {
  const RecordSaveStatus({
    super.key,
    this.playback,
    this.reader,
    this.book,
    this.edition,
    this.padding = EdgeInsets.zero,
  });
  final Playback? playback;
  final ReaderSession? reader;
  final Book? book;
  final Edition? edition;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ?playback?.statusNotifier,
      ?reader?.saveStatusChanges,
    ]),
    builder: (context, _) {
      final listening = playback?.statusNotifier.value;
      return RecordSaveNotice(
        status: (
          actionNotice: listening?.actionNotice,
          recoveryMessage: listening?.recoveryMessage,
          saveFailed:
              (listening?.saveFailed ?? false) || (reader?.saveFailed ?? false),
        ),
        book: book,
        edition: edition,
        padding: padding,
        onRetrySave: () {
          if (playback case final playback?) unawaited(playback.flush());
          if (reader case final reader?) unawaited(reader.flush());
        },
      );
    },
  );
}

/// Draws the notices of [status] for the supplied book or edition and reports
/// a retry while records failed to save. It causes no side effects.
class RecordSaveNotice extends StatelessWidget {
  const RecordSaveNotice({
    super.key,
    required this.status,
    required this.onRetrySave,
    this.book,
    this.edition,
    this.padding = EdgeInsets.zero,
  });
  final PlaybackStatus status;
  final Book? book;
  final Edition? edition;
  final EdgeInsetsGeometry padding;

  /// Reports a tap on Retry saving.
  final VoidCallback onRetrySave;
  @override
  Widget build(BuildContext context) {
    final messages = status.messagesFor(book: book, edition: edition).toList();
    if (messages.isEmpty && !status.saveFailed) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages) StatusMessage(message),
          if (status.saveFailed) ...[
            const Text(
              'Personal records are not saved to this device. Keep Bookfin open and retry.',
            ),
            TextButton(
              onPressed: onRetrySave,
              child: const Text('Retry saving'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One action error beside its edition or History entry. The owner supplies
/// the narrow status signal; this view holds no notice state or callbacks.
class PlaybackActionStatus extends StatelessWidget {
  const PlaybackActionStatus({
    super.key,
    required this.status,
    this.edition,
    this.recordId,
  });
  final ValueListenable<PlaybackStatus> status;
  final Edition? edition;
  final String? recordId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: status,
    builder: (context, value, _) =>
        switch (value.actionMessageFor(edition: edition, recordId: recordId)) {
          final message? => Semantics(
            liveRegion: true,
            child: StatusMessage(message),
          ),
          null => const SizedBox.shrink(),
        },
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

/// Asks for a title and a note for the reading bookmark [bookmark] in the
/// shared bookmark editor, then saves them in [reader].
Future<void> editReadingBookmark(
  BuildContext context,
  ReaderSession reader,
  Bookmark<TextPosition> bookmark,
) async {
  final edited = await showBookmarkEditor(
    context,
    heading: 'Edit bookmark',
    title: bookmark.title,
    note: bookmark.note,
    place: readingPlaceLine(reader.describe(bookmark.position)),
  );
  if (edited == null) return;
  await reader.editBookmark(
    bookmark.id,
    title: edited.title,
    note: edited.note,
  );
}

/// The place line of the bookmark editor for a reading place: its page and
/// chapter in the open book, such as "On p. 134 · Chapter 4", and else the
/// first words of its quote.
String readingPlaceLine(PlaceWords words) => switch (words.along) {
  null => words.short,
  _ => ['On ${words.short}', ?words.chapter].join(' · '),
};

/// Shows a dialog that edits the [title] and [note] of a bookmark under
/// [heading]. [place] says where the bookmark is, such as "At 1:15".
/// Returns the edited title and note when the listener saves, or null when
/// they cancel. The caller saves the bookmark.
Future<({String title, String note})?> showBookmarkEditor(
  BuildContext context, {
  required String heading,
  String? title,
  String? note,
  required String place,
}) => showDialog<({String title, String note})>(
  context: context,
  builder: (context) =>
      _BookmarkEditor(heading: heading, title: title, note: note, place: place),
);

class _BookmarkEditor extends StatefulWidget {
  const _BookmarkEditor({
    required this.heading,
    required this.title,
    required this.note,
    required this.place,
  });
  final String heading;
  final String? title;
  final String? note;
  final String place;
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
          // The outlined field's floating label rises above the field by
          // about half a line, so the gap grows with the text size.
          SizedBox(height: MediaQuery.textScalerOf(context).scale(16)),
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
    return GlassDialog(title: title, content: content, actions: actions);
  }
}
