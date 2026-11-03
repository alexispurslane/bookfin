import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

import '../playback/playback.dart';
import '../playback/screen.dart';
import 'session.dart';
import 'document.dart';
import 'pdf.dart';
import 'pdf_viewport.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.reader,
    required this.onNightChanged,
    this.playback,
  });
  final ReaderSession reader;
  final ValueChanged<bool> onNightChanged;
  final Playback? playback;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  bool _controls = true;
  int? _viewToken;
  ReaderSession get reader => widget.reader;
  @override
  void dispose() {
    unawaited(reader.flush());
    if (_viewToken != null) reader.closeView(_viewToken!);
    super.dispose();
  }

  void _panel(Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => child,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: reader,
    builder: (context, _) {
      _viewToken = reader.token;
      final token = reader.token;
      final publication = reader.publication;
      final document = reader.document;
      final night = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: night
            ? const Color(0xff251e19)
            : const Color(0xfff6efe2),
        appBar: _controls
            ? AppBar(
                title: Text(
                  reader.book?.title ?? 'Reading',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'Hide reader controls',
                    onPressed: () => setState(() => _controls = false),
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ],
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              if (reader.message != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        reader.message!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (reader.book != null && reader.edition != null)
                        TextButton(
                          onPressed: () => unawaited(
                            reader.open(reader.book!, reader.edition!),
                          ),
                          child: const Text('Retry opening'),
                        ),
                    ],
                  ),
                ),
              if (publication?.warnings.isNotEmpty == true && _controls)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    publication!.warnings.join(' '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: document is PdfBook
                          ? PdfViewport(
                              key: ValueKey(token),
                              book: document,
                              initial: reader.initialAddress as PdfAddress?,
                              fontSize: MediaQuery.textScalerOf(context)
                                  .scale(reader.fontSize),
                              onReady: (navigator, entries) => reader
                                  .attachDocument(token, navigator, entries),
                              onAddress: (address) =>
                                  reader.acceptAddress(token, address),
                            )
                          : !epubViewportSupported
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'EPUB reading is available in the Android app. Your downloads and listening are unchanged.',
                                ),
                              ),
                            )
                          : reader.loading ||
                                (reader.edition == null &&
                                    publication == null &&
                                    reader.message == null)
                          ? Center(
                              child: Semantics(
                                label: 'Checking the downloaded EPUB',
                                child: const CircularProgressIndicator(),
                              ),
                            )
                          : publication == null
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'This EPUB is not open. Use the message above to retry.',
                                ),
                              ),
                            )
                          : EpubViewport(
                              key: ValueKey(token),
                              publication: publication,
                              initial: reader.initialLocation,
                              fontSize: MediaQuery.textScalerOf(context)
                                  .scale(reader.fontSize),
                              night: night,
                              onReady: (controller, contents) =>
                                  reader.attach(token, controller, contents),
                              onLocation: (location) =>
                                  reader.acceptVisible(token, location),
                              onFailure: (message) =>
                                  reader.failed(token, message),
                              onWarning: (message) =>
                                  reader.warn(token, message),
                              onTap: () {
                                if (mounted) {
                                  setState(() => _controls = !_controls);
                                }
                              },
                            ),
                    ),
                    if (!_controls)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          tooltip: 'Show reader controls',
                          onPressed: () => setState(() => _controls = true),
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      ),
                    if (publication != null &&
                        !reader.ready &&
                        epubViewportSupported &&
                        reader.message == null)
                      Center(
                        child: Semantics(
                          label: 'Laying out the book',
                          child: const CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
              if (_controls)
                Flexible(
                  flex: 0,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Contents',
                                onPressed: reader.ready
                                    ? () => _panel(_ContentsPanel(reader))
                                    : null,
                                icon: const Icon(Icons.list_rounded),
                              ),
                              IconButton(
                                tooltip: 'Search book',
                                onPressed: reader.ready
                                    ? () => _panel(_SearchPanel(reader))
                                    : null,
                                icon: const Icon(Icons.search_rounded),
                              ),
                              IconButton(
                                tooltip: 'Smaller text',
                                onPressed:
                                    document == null || reader.fontSize <= 14
                                    ? null
                                    : () => unawaited(
                                        reader.setFontSize(reader.fontSize - 2),
                                      ),
                                icon: const Icon(Icons.text_decrease_rounded),
                              ),
                              IconButton(
                                tooltip: 'Larger text',
                                onPressed:
                                    document == null || reader.fontSize >= 40
                                    ? null
                                    : () => unawaited(
                                        reader.setFontSize(reader.fontSize + 2),
                                      ),
                                icon: const Icon(Icons.text_increase_rounded),
                              ),
                              IconButton(
                                tooltip: 'Bookmark this place',
                                onPressed: !reader.canBookmark
                                    ? null
                                    : () => unawaited(reader.addBookmark()),
                                icon: const Icon(Icons.bookmark_add_outlined),
                              ),
                              IconButton(
                                tooltip: 'Reading bookmarks',
                                onPressed: document == null
                                    ? null
                                    : () => _panel(_BookmarksPanel(reader)),
                                icon: const Icon(Icons.bookmarks_outlined),
                              ),
                              IconButton(
                                tooltip: night
                                    ? 'Cream reading theme'
                                    : 'Night reading theme',
                                onPressed: () => widget.onNightChanged(!night),
                                icon: Icon(
                                  night
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                ),
                              ),
                            ],
                          ),
                          if (reader.visibleAddress?.page != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: LinearProgressIndicator(
                                value:
                                    reader.visibleAddress!.page! /
                                    reader.visibleAddress!.pages!,
                                semanticsLabel:
                                    'Current document page progress. Page ${reader.visibleAddress!.page} of ${reader.visibleAddress!.pages}',
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: reader.ready
                                    ? () => unawaited(reader.move(false))
                                    : null,
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  '${reader.visibleAddress?.chapter ?? 'Current chapter unavailable'} · ${reader.visibleAddress?.page == null ? 'Page progress unavailable' : 'Page ${reader.visibleAddress!.page} of ${reader.visibleAddress!.pages}'}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: reader.ready
                                    ? () => unawaited(reader.move(true))
                                    : null,
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                          if (widget.playback != null)
                            PlaybackMiniPlayer(playback: widget.playback!),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ContentsPanel extends StatelessWidget {
  const _ContentsPanel(this.reader);
  final ReaderSession reader;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Contents', style: Theme.of(context).textTheme.headlineSmall),
          for (final entry in reader.contents)
            ListTile(
              contentPadding: EdgeInsets.only(left: entry.depth * 16.0),
              title: Text(entry.title),
              onTap: () {
                Navigator.pop(context);
                unawaited(reader.goToContents(entry.href));
              },
            ),
        ],
      ),
    ),
  );
}

class _SearchPanel extends StatefulWidget {
  const _SearchPanel(this.reader);
  final ReaderSession reader;
  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    widget.reader.cancelSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: ListenableBuilder(
          listenable: widget.reader,
          builder: (context, _) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel search',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _query,
                autofocus: true,
                maxLength: 256,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Find in this book',
                ),
                onSubmitted: (value) => unawaited(widget.reader.search(value)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (widget.reader.searching)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Searching the book',
                      ),
                    if (widget.reader.searchError != null)
                      Text(
                        widget.reader.searchError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const Text(
                      'Search uses basic lowercase matching. Some language-specific letter forms differ. Spaces, tabs, and line breaks match as one space. Accents must match. Different Unicode spellings are not combined. Text hidden only by a stylesheet can appear in results.',
                    ),
                    if (!widget.reader.searching &&
                        widget.reader.hits.isEmpty &&
                        _query.text.isNotEmpty &&
                        widget.reader.searchError == null)
                      const Text('No matches.'),
                    for (final hit in widget.reader.hits)
                      ListTile(
                        title: Text(hit.excerpt),
                        onTap: () {
                          unawaited(widget.reader.openHit(hit));
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BookmarksPanel extends StatelessWidget {
  const _BookmarksPanel(this.reader);
  final ReaderSession reader;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: ListenableBuilder(
        listenable: reader,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Reading bookmarks',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (reader.bookmarks.isEmpty)
              const Text(
                'No reading bookmarks in this edition. Use Bookmark this place while reading.',
              ),
            for (final bookmark in reader.bookmarks)
              ListTile(
                title: Text(
                  bookmark.title?.isNotEmpty == true
                      ? bookmark.title!
                      : 'Saved reading place',
                ),
                subtitle: Text(
                  bookmark.note?.isNotEmpty == true
                      ? bookmark.note!
                      : bookmark.createdAt.toLocal().toString(),
                ),
                onTap: () {
                  unawaited(reader.restoreBookmark(bookmark.id));
                  Navigator.pop(context);
                },
                trailing: PopupMenuButton<String>(
                  tooltip: 'Edit reading bookmark',
                  onSelected: (action) async {
                    if (action == 'delete') {
                      await reader.deleteBookmark(bookmark.id);
                      return;
                    }
                    final title = TextEditingController(text: bookmark.title);
                    final note = TextEditingController(text: bookmark.note);
                    final saved = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Reading bookmark'),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: title,
                                decoration: const InputDecoration(
                                  labelText: 'Title',
                                ),
                              ),
                              TextField(
                                controller: note,
                                decoration: const InputDecoration(
                                  labelText: 'Note',
                                ),
                                minLines: 2,
                                maxLines: 5,
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (saved == true) {
                      await reader.editBookmark(
                        bookmark.id,
                        title: title.text,
                        note: note.text,
                      );
                    }
                    title.dispose();
                    note.dispose();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit title and note'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
